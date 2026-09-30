--[[
	Car
	---
	A raycast-suspension vehicle built from parts, simulated on the client.
	Every vehicle in Vehicles (cars, the tractor-trailer and the bikes) is
	one of these.

	The chassis is one invisible solid box. Each corner casts a ray down; if
	it hits, a spring/damper pushes the chassis up and tyre friction acts in
	the contact plane (drive, brake and cornering grip, limited by a
	friction circle). The forces go through one VectorForce per corner, so
	the physics engine applies them smoothly on every sub-step.

	Each corner's spring, damper and tyre forces are scaled by the weight it
	carries at rest (the lever rule between the axles), so vehicles with a
	long wheelbase or a trailer on the back sit level. The forces are only
	updated once per frame, so the damping is capped to what one frame can
	take without overshooting; that keeps light vehicles (the bikes) steady
	when the frame rate drops. Full steering lock is limited to what the
	tyres can hold at the current speed (Config.Car.SteerGrip).

	The visible body is drawn by a module in VehicleBodies (bikes by
	Motorcycle). Wheels are visual only: massless, non-colliding, moved every
	frame to where the suspension says they are.

	The tractor-trailer's trailer is a second physics body hanging on a
	BallSocketConstraint at the fifth wheel. Its tandem axle has its own
	raycast corners with the same force model, and a roll coupling keeps it
	upright relative to the tractor, like a real fifth wheel plate.

	A premade model in ReplicatedStorage.InfiniteRoadAssets.Vehicles.<Id>.Body
	(or Car.Body for the sedan) replaces the part-built body. Its wheels
	(parts named *wheel*, *tire*, *tyre* or *rim*) are found automatically
	and attached to the suspension, so they spin, steer and bounce.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Motorcycle = require(script.Parent.Motorcycle)
local Vehicles = require(script.Parent.Vehicles)
local Kit = require(script.Parent.VehicleBodies.Kit)

local Car = {}
Car.__index = Car

local sqrt, cos, sin, max, min, clamp, abs, atan = math.sqrt, math.cos, math.sin, math.max, math.min, math.clamp, math.abs, math.atan
local rgb = Color3.fromRGB

local ATTACH_Y = -0.2 -- where the suspension rays start (chassis space)
local FORCE_Y = -0.5 -- where tyre forces are applied (a bit below centre)
local CHASSIS_DENSITY = 0.9
-- AutoDrive's pure pursuit assumes this wheelbase; maxSteer() is scaled by
-- it so the autodrive steers every vehicle correctly
local REFERENCE_WHEELBASE = 9.8

local function weldTo(part: BasePart, chassis: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = chassis
	w.Part1 = part
	w.Parent = part
end

-- Vehicle tuning: Config.Car, with Config.Motorcycle on top for bikes,
-- then the vehicle's own tuning.
function Car.tuning(config, id: string)
	local spec = Vehicles.get(id)
	local tune = table.clone(config.Car)
	if spec.kind == "Motorcycle" then
		for k, v in config.Motorcycle do
			tune[k] = v
		end
	end
	for k, v in spec.tuning or {} do
		tune[k] = v
	end
	return tune
end

-- hub height at rest (chassis space) for a suspension setup
local function restHubY(cc, attachY: number): number
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local sag = Workspace.Gravity / (omega * omega)
	return attachY - (cc.SuspensionLength - sag)
end

--[[
	How much suspension damping one frame can take. The forces are held for
	a whole frame, so a damper strong enough to reverse a motion within one
	frame makes it flip back and forth every frame instead of settling.
	Returns the highest damping rate (1/s) over the heave, roll and pitch
	modes of a box body resting on `corners` (per unit damping ratio and
	suspension omega), and the share of a frame's worth of damping left for
	the springs: sideways tyre forces acting `lever` below the centre of
	mass (with the road `drop` below it) already damp the roll.
]]
local function dampingLimits(size: Vector3, corners, extraShare: number, lever: number, drop: number): (number, number)
	local sum, roll, pitch = 0, 0, 0
	for _, w in corners do
		local s = w.share + (w.kshare or 0) * extraShare
		sum += s
		roll += s * w.x * w.x
		pitch += s * w.z * w.z
	end
	local rollInertia = 12 / (size.X * size.X + size.Y * size.Y)
	local tyres = 0.6 * sum * math.abs(lever) * drop * rollInertia
	roll *= rollInertia
	pitch *= 12 / (size.Y * size.Y + size.Z * size.Z)
	return max(sum, roll, pitch), clamp(0.9 * (1 - tyres), 0.3, 1)
end

local function newCorner(chassis: BasePart, i: number, x: number, z: number, forceY: number, radius: number, front: boolean, length: number)
	local att = Instance.new("Attachment")
	att.Name = "Force" .. i
	att.Position = Vector3.new(x, forceY, z)
	att.Parent = chassis
	local force = Instance.new("VectorForce")
	force.Attachment0 = att
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = false
	force.Force = Vector3.zero
	force.Parent = chassis
	return {
		x = x,
		z = z,
		radius = radius,
		front = front,
		force = force,
		attachment = att,
		length = length,
		spin = 0,
		grounded = false,
		share = 0.25,
		kshare = 0,
		visuals = {},
	}
end

--[[
	id: a vehicle id from Vehicles (default "Sedan"; "Car" and "Motorcycle"
	still work). Cars and motorcycles use the same physics; motorcycles have
	a narrow footprint, their own tuning, and lean visually into corners.
]]
function Car.new(config, color: Color3, assets, id: string?)
	local self = setmetatable({}, Car)
	local spec = Vehicles.get(id)
	local kind = spec.kind
	self.kind = kind
	self.vehicleId = spec.id
	self.spec = spec
	local cc = Car.tuning(config, spec.id)
	self.config = cc
	self.gripScale = 1
	self.wetness = 0
	self.lean = 0
	self.attachY = cc.AttachY or ATTACH_Y
	self.forceY = cc.ForceY or FORCE_Y
	self.speed = 0
	self.steer = 0
	self.headlights = {}
	self.taillights = {}
	local hubY = restHubY(cc, self.attachY)
	self.restLength = self.attachY - hubY
	self.groundY = hubY - cc.WheelRadius -- the road under the resting car (chassis space)

	local model = Instance.new("Model")
	model.Name = kind == "Motorcycle" and "InfiniteRoadBike" or "InfiniteRoadCar"

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = cc.ChassisSize
	chassis.Color = color
	chassis.Transparency = 1 -- the body is drawn by VehicleBodies / Motorcycle
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.CanQuery = false
	chassis.CanTouch = false
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CustomPhysicalProperties = PhysicalProperties.new(CHASSIS_DENSITY, 0.2, 0.05, 1, 1)
	chassis.CFrame = CFrame.new(0, 50, 0)
	chassis.Parent = model
	model.PrimaryPart = chassis
	self.chassis = chassis
	self.model = model

	-- Corners: front-left, front-right, rear-left, rear-right (front is -Z).
	-- The motorcycle keeps four physics corners (like outriggers, which keep
	-- it stable); only its visual has two wheels.
	local frontZ, rearZ = cc.FrontZ or -cc.HalfBase, cc.RearZ or cc.HalfBase
	local trackF, trackR = cc.HalfTrack, cc.HalfTrackRear or cc.HalfTrack
	self.wheels = {}
	for i, def in { { -1, true }, { 1, true }, { -1, false }, { 1, false } } do
		local front = def[2]
		self.wheels[i] = newCorner(chassis, i, def[1] * (front and trackF or trackR), front and frontZ or rearZ, self.forceY, cc.WheelRadius, front, self.restLength)
	end
	if cc.Trailer then
		self:_buildTrailer(cc.Trailer)
	end
	self:_loadShares()

	if kind == "Motorcycle" then
		Motorcycle.build(self, color, config)
	else
		local body = require(script.Parent.VehicleBodies[spec.body or spec.id])
		local kit = Kit.new(self, chassis, self.groundY, color, model)
		body.build(kit, self)
		self.bodyPartCount = kit.count
	end

	local aero = Instance.new("VectorForce")
	aero.Name = "Aero"
	local aeroAtt = Instance.new("Attachment")
	aeroAtt.Parent = chassis
	aero.Attachment0 = aeroAtt
	aero.RelativeTo = Enum.ActuatorRelativeTo.World
	aero.ApplyAtCenterOfMass = true
	aero.Parent = chassis
	self.aero = aero

	-- stability assist: a yaw torque that pulls the spin rate towards what
	-- the steering asks for, so the vehicle does not spin out easily
	local yaw = Instance.new("Torque")
	yaw.Name = "StabilityAssist"
	yaw.Attachment0 = aeroAtt
	yaw.RelativeTo = Enum.ActuatorRelativeTo.World
	yaw.Torque = Vector3.zero
	yaw.Parent = chassis
	self.yawTorque = yaw

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.FilterDescendantsInstances = { model }
	self.rayParams.IgnoreWater = true
	self.grounded = 0

	local slot = assets and assets.vehicleBodies and assets.vehicleBodies[spec.id]
	local source, folder = slot and slot.source, slot and slot.folder
	if not source and assets then
		-- older slots: Car/Body is the sedan, Motorcycle/Body the naked bike
		if spec.id == "Sedan" then
			source, folder = assets.carSource, assets.carFolder
		elseif spec.id == "Naked" then
			source, folder = assets.bikeSource, assets.bikeFolder
		end
	end
	if source then
		local ok, err
		if kind == "Motorcycle" then
			ok, err = pcall(Motorcycle.applyBody, self, source, folder)
		else
			ok, err = pcall(self._applyBody, self, source, folder)
		end
		if not ok then
			warn("[InfiniteRoad] could not use the premade " .. spec.name .. " model: " .. tostring(err))
		end
	end
	self:_spray(cc)
	self:_sounds(config.Sounds)
	return self
end

-- Static weight share of every corner: the chassis' own weight sits at its
-- centre and is split between the axles by the lever rule; the trailer's
-- kingpin load is split the same way from the fifth wheel.
function Car:_loadShares()
	local w = self.wheels
	local front, rear = w[1].z, w[3].z
	local span = rear - front
	local frontShare = rear / span
	for _, c in w do
		c.share = (c.front and frontShare or 1 - frontShare) * 0.5
		c.kshare = 0
	end
	local ratio = 0
	local tr = self.trailer
	if tr then
		local f = (rear - tr.hitchZ) / span
		for _, c in w do
			c.kshare = tr.kingpinShare * (c.front and f or 1 - f) * 0.5
		end
		ratio = tr.config.MassRatio or 1
	end
	self.dampRate, self.dampBudget = dampingLimits(self.chassis.Size, w, ratio, self.forceY, -self.groundY)
end

-- The trailer: its own physics box on a ball joint at the fifth wheel.
function Car:_buildTrailer(tc)
	local cc = self.config
	local chassis = self.chassis
	local model = Instance.new("Model")
	model.Name = "Trailer"
	model.Parent = self.model

	local size = tc.ChassisSize
	local hitch = Vector3.new(0, self.groundY + tc.FifthWheel.Y, tc.FifthWheel.Z) -- chassis space
	-- the box: bottom at the hitch, centre of mass ComDistance behind the kingpin
	local center = hitch + Vector3.new(0, size.Y * 0.5, tc.ComDistance)
	local cs = cc.ChassisSize
	local density = CHASSIS_DENSITY * (tc.MassRatio or 1) * (cs.X * cs.Y * cs.Z) / (size.X * size.Y * size.Z)
	local part = Instance.new("Part")
	part.Name = "TrailerChassis"
	part.Size = size
	part.Transparency = 1
	part.Material = Enum.Material.SmoothPlastic
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CustomPhysicalProperties = PhysicalProperties.new(density, 0.2, 0.05, 1, 1)
	part.CFrame = chassis.CFrame * CFrame.new(center)
	part.Parent = model
	model.PrimaryPart = part

	-- fifth wheel and kingpin; the attachments' primary axis points up, so
	-- the twist limit caps the articulation and the cone caps pitch and roll
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	local a0 = Instance.new("Attachment")
	a0.Name = "FifthWheel"
	a0.CFrame = CFrame.new(hitch) * upright
	a0.Parent = chassis
	local a1 = Instance.new("Attachment")
	a1.Name = "Kingpin"
	a1.CFrame = CFrame.new(hitch - center) * upright
	a1.Parent = part
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = "Hitch"
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.LimitsEnabled = true
	socket.UpperAngle = 25
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -80
	socket.TwistUpperAngle = 80
	socket.Restitution = 0
	socket.Parent = part
	local nc = Instance.new("NoCollisionConstraint")
	nc.Part0 = chassis
	nc.Part1 = part
	nc.Parent = part

	-- trailer space: origin at the box centre
	local groundY = -(tc.FifthWheel.Y + size.Y * 0.5)
	local R = tc.WheelRadius
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local restLength = cc.SuspensionLength - Workspace.Gravity / (omega * omega)
	local attachY = groundY + R + restLength
	local forceY = -size.Y * 0.5 -- at the hitch height: braking does not pitch it
	local axleZ = tc.AxleDistance - tc.ComDistance
	local rearShare = tc.ComDistance / tc.AxleDistance
	local wheels = {}
	for i, x in { -tc.HalfTrack, tc.HalfTrack } do
		local c = newCorner(part, i, x, axleZ, forceY, R, false, restLength)
		c.share = rearShare * 0.5
		c.trailer = true
		wheels[i] = c
	end

	local att = Instance.new("Attachment")
	att.Name = "Centre"
	att.Parent = part
	local aero = Instance.new("VectorForce")
	aero.Name = "Aero"
	aero.Attachment0 = att
	aero.RelativeTo = Enum.ActuatorRelativeTo.World
	aero.ApplyAtCenterOfMass = true
	aero.Force = Vector3.zero
	aero.Parent = part
	local roll = Instance.new("Torque")
	roll.Name = "RollCoupling"
	roll.Attachment0 = att
	roll.RelativeTo = Enum.ActuatorRelativeTo.World
	roll.Torque = Vector3.zero
	roll.Parent = part
	local reaction = Instance.new("Torque")
	reaction.Name = "RollCouplingReaction"
	reaction.Attachment0 = a0
	reaction.RelativeTo = Enum.ActuatorRelativeTo.World
	reaction.Torque = Vector3.zero
	reaction.Parent = chassis

	local rate, budget = dampingLimits(size, wheels, 0, forceY, -groundY)
	self.trailer = {
		dampRate = rate,
		dampBudget = budget,
		model = model,
		chassis = part,
		socket = socket,
		wheels = wheels,
		config = tc,
		attachY = attachY,
		groundY = groundY,
		restLength = restLength,
		axleZ = axleZ,
		hitchZ = hitch.Z,
		kingpinShare = 1 - rearShare,
		rest = chassis.CFrame:ToObjectSpace(part.CFrame),
		aero = aero,
		rollTorque = roll,
		reactionTorque = reaction,
		syncVelocity = true,
	}
end

-- Water / snow thrown up behind the wheels on wet roads.
function Car:_spray(cc)
	self.sprayEmitters = {}
	local function emitter(part: BasePart, pos: Vector3)
		local att = Instance.new("Attachment")
		att.Name = "Spray"
		att.Position = pos
		att.Parent = part
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(rgb(200, 206, 212))
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.2) })
		e.Lifetime = NumberRange.new(0.35, 0.6)
		e.Speed = NumberRange.new(6, 12)
		e.SpreadAngle = Vector2.new(25, 25)
		e.EmissionDirection = Enum.NormalId.Back
		e.Drag = 3
		e.LightInfluence = 1
		e.Rate = 0
		e.Parent = att
		table.insert(self.sprayEmitters, e)
	end
	local rear = self.wheels[3]
	local groundY = self.groundY + 0.6
	if self.kind == "Motorcycle" then
		emitter(self.chassis, Vector3.new(0, groundY, rear.z + 0.6))
	else
		for _, x in { self.wheels[3].x, self.wheels[4].x } do
			emitter(self.chassis, Vector3.new(x, groundY, rear.z + rear.radius * 0.4 + 0.6))
		end
	end
	local tr = self.trailer
	if tr then
		for _, w in tr.wheels do
			emitter(tr.chassis, Vector3.new(w.x, tr.groundY + 0.6, w.z + (tr.config.AxleSpread or 0) * 0.5 + w.radius + 0.4))
		end
	end
end

-- Road conditions from weather and season: grip multiplier and wetness
-- (0..1, drives the spray).
function Car:setSurface(gripScale: number, wetness: number)
	self.gripScale = gripScale
	self.wetness = wetness
end

-- Distance between the front and rear axle (the rear tandem centre).
function Car:wheelbase(): number
	return self.wheels[3].z - self.wheels[1].z
end

-- Steering lock (radians) at a speed: less lock as speed builds, and never
-- more than the tyres can hold (SteerGrip) on the current surface.
function Car:_lock(speed: number): number
	local cc = self.config
	local t = clamp(abs(speed) / cc.TopSpeed, 0, 1)
	local lock = cc.MaxSteerLow + (cc.MaxSteerHigh - cc.MaxSteerLow) * sqrt(t)
	local use = cc.SteerGrip or 0
	if use > 0 and abs(speed) > 1 then
		-- kinematic lateral acceleration: v^2 tan(lock) / wheelbase
		local aMax = use * cc.Grip * self.gripScale * Workspace.Gravity
		lock = min(lock, atan(aMax * self:wheelbase() / (speed * speed)))
	end
	return lock
end

-- The real steering lock at the current speed.
function Car:steerLock(): number
	return self:_lock(self.speed)
end

-- Steering lock at the current speed, for autodrive. AutoDrive plans its
-- pure-pursuit steering for a 9.8 stud wheelbase and divides by this, so
-- the lock is scaled by that reference over this vehicle's wheelbase: the
-- steering angle it ends up with is right for every vehicle.
function Car:maxSteer(): number
	return self:_lock(self.speed) * REFERENCE_WHEELBASE / self:wheelbase()
end

local function isWheelName(name: string): boolean
	local n = string.lower(name)
	if string.find(n, "steer") or string.find(n, "spare") then
		return false
	end
	return string.find(n, "wheel") ~= nil or string.find(n, "tire") ~= nil or string.find(n, "tyre") ~= nil or string.find(n, "rim") ~= nil
end

-- is this part a wheel, or inside something named like one?
local function inWheel(part: Instance, root: Instance): boolean
	local node = part
	while node and node ~= root do
		if isWheelName(node.Name) then
			return true
		end
		node = node.Parent
	end
	return false
end

local function listBounds(parts)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = -lo
	for _, p in parts do
		local cf, s = p.CFrame, p.Size * 0.5
		for _, c in { -1, 1 } do
			for _, d in { -1, 1 } do
				for _, e in { -1, 1 } do
					local w = cf:PointToWorldSpace(Vector3.new(s.X * c, s.Y * d, s.Z * e))
					lo = Vector3.new(min(lo.X, w.X), min(lo.Y, w.Y), min(lo.Z, w.Z))
					hi = Vector3.new(max(hi.X, w.X), max(hi.Y, w.Y), max(hi.Z, w.Z))
				end
			end
		end
	end
	return lo, hi
end

-- Swap the part-built body for a premade model (the trailer stays).
function Car:_applyBody(source: Instance, folder: Instance?)
	local AssetLibrary = require(script.Parent.AssetLibrary)
	local cc = self.config
	local chassis = self.chassis

	local body
	if source:IsA("Model") then
		body = source:Clone()
	else
		body = Instance.new("Model")
		source:Clone().Parent = body
	end
	AssetLibrary.sanitize(body)
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
		end
	end
	if body.PrimaryPart then
		body.PrimaryPart = nil
	end

	-- face -Z, bottom centre at the origin, scaled to the vehicle's length
	local size = AssetLibrary.recenter(body)
	local yaw = AssetLibrary.attribute(source, folder, "YawOffset")
	if yaw and yaw ~= 0 then
		body:PivotTo(CFrame.Angles(0, math.rad(yaw), 0))
		size = AssetLibrary.recenter(body)
	end
	local factor = AssetLibrary.attribute(source, folder, "Scale") or 1
	if AssetLibrary.attribute(source, folder, "KeepSize") ~= true then
		factor *= cc.BodyLength / max(size.Z, 0.1)
	end
	if factor ~= 1 then
		body:ScaleTo(body:GetScale() * factor)
		size *= factor
	end

	-- the model's wheels, sorted into corners (same order as self.wheels)
	local corners = { {}, {}, {}, {} }
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 0.99 and inWheel(p, body) then
			local c = p.CFrame.Position
			if c.Y < size.Y * 0.55 and abs(c.X) > size.X * 0.12 then
				local idx = (c.X < 0 and 1 or 2) + (c.Z < 0 and 0 or 2)
				table.insert(corners[idx], p)
			end
		end
	end
	local haveWheels = #corners[1] > 0 and #corners[2] > 0 and #corners[3] > 0 and #corners[4] > 0

	local restHub = self.attachY - self.restLength
	local centers = {}
	local offsetY
	if haveWheels then
		local sumY = 0
		for i = 1, 4 do
			local lo, hi = listBounds(corners[i])
			centers[i] = { center = (lo + hi) * 0.5, radius = max(hi.Y - lo.Y, hi.Z - lo.Z) * 0.5 }
			sumY += centers[i].center.Y
		end
		offsetY = restHub - sumY / 4
	else
		offsetY = self.groundY -- body bottom on the ground
	end
	body:PivotTo(chassis.CFrame * CFrame.new(0, offsetY, 0))

	-- hide the part-built body (lights keep working from hidden parts); the
	-- trailer is not part of the premade model and stays
	local trailerModel = self.trailer and self.trailer.model
	for _, d in self.model:GetDescendants() do
		if d:IsA("BasePart") and not (trailerModel and d:IsDescendantOf(trailerModel)) then
			if not d:GetAttribute("IR_Wheel") or haveWheels then
				d.Transparency = 1
			end
		end
	end

	local wheelParts = {}
	if haveWheels then
		for i, w in self.wheels do
			local c = centers[i]
			local hubY = c.center.Y + offsetY
			w.x, w.z = c.center.X, c.center.Z
			w.radius = clamp(c.radius, 0.6, 5)
			w.attachment.Position = Vector3.new(w.x, self.forceY, w.z)
			-- the model's tyres ride on the first wheel rig of the corner
			local rig = w.visuals[1]
			w.visuals = { { part = rig.part, weld = rig.weld, dz = 0, dx = 0, rim = rig.rim, parts = rig.parts } }
			local old = rig.part.CFrame
			rig.part.CFrame = chassis.CFrame * CFrame.new(w.x, hubY, w.z)
			for _, p in rig.parts do
				p.CFrame = rig.part.CFrame * old:ToObjectSpace(p.CFrame)
			end
			for _, p in corners[i] do
				wheelParts[p] = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rig.part
				weld.Part1 = p
				weld.Parent = p
			end
			rig.weld.C0 = CFrame.new(w.x, hubY, w.z)
		end
		self:_loadShares()
	end
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") and not wheelParts[p] then
			weldTo(p, chassis)
		end
	end
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
		end
	end
	body.Name = "Body"
	body.Parent = self.model

	-- the collision box follows the body's footprint (within reason, so the
	-- handling stays close to the tuned vehicle)
	local base = cc.ChassisSize
	chassis.Size = Vector3.new(clamp(size.X * 0.9, base.X * 0.8, base.X * 1.25), base.Y, clamp(size.Z * 0.9, base.Z * 0.8, base.Z * 1.25))
	self:_loadShares()
	self.customBody = true
end

-- Optional looping engine and wind sounds (asset ids in Config.Sounds).
function Car:_sounds(sounds)
	if not sounds then
		return
	end
	local function make(id, volume)
		if not id or id == "" then
			return nil
		end
		local snd = Instance.new("Sound")
		snd.SoundId = id
		snd.Looped = true
		snd.Volume = volume
		snd.RollOffMaxDistance = 200
		snd.Parent = self.chassis
		snd:Play()
		return snd
	end
	local own = self.spec and self.spec.sound and sounds[self.spec.sound]
	local engineId = (own and own ~= "" and own) or (self.kind == "Motorcycle" and sounds.MotorcycleEngine ~= "" and sounds.MotorcycleEngine) or sounds.Engine
	self.engineSound = make(engineId, 0.35)
	self.windSound = make(sounds.Wind, 0)
end

function Car:setIgnore(list)
	local all = { self.model }
	for _, v in list do
		table.insert(all, v)
	end
	self.rayParams.FilterDescendantsInstances = all
end

function Car:teleport(cf: CFrame)
	local c = self.chassis
	self.model:PivotTo(cf)
	c.AssemblyLinearVelocity = Vector3.zero
	c.AssemblyAngularVelocity = Vector3.zero
	local tr = self.trailer
	if tr then
		-- straight behind the tractor again
		tr.model:PivotTo(c.CFrame * tr.rest)
		tr.chassis.AssemblyLinearVelocity = Vector3.zero
		tr.chassis.AssemblyAngularVelocity = Vector3.zero
		tr.syncVelocity = true
	end
	self.steer = 0
end

-- Keep velocity, move by an offset (used when the world origin shifts).
function Car:shift(delta: Vector3)
	local c = self.chassis
	local v, w = c.AssemblyLinearVelocity, c.AssemblyAngularVelocity
	local tr = self.trailer
	local tv, tw
	if tr then
		tv, tw = tr.chassis.AssemblyLinearVelocity, tr.chassis.AssemblyAngularVelocity
	end
	self.model:PivotTo(self.model:GetPivot() - delta)
	c.AssemblyLinearVelocity = v
	c.AssemblyAngularVelocity = w
	if tr then
		tr.chassis.AssemblyLinearVelocity = tv
		tr.chassis.AssemblyAngularVelocity = tw
	end
end

function Car:getCFrame(): CFrame
	return self.chassis.CFrame
end

function Car:getVelocity(): Vector3
	return self.chassis.AssemblyLinearVelocity
end

--[[
	Suspension and tyre forces for the corners of one body (the chassis or
	the trailer). `mass` is the body's own mass, `extra` the trailer mass
	whose kingpin load the chassis carries. Returns how many corners touch
	the ground.
]]
function Car:_corners(part: BasePart, corners, attachY: number, mass: number, extra: number, dt: number, throttle: number, handbrake: boolean, damp: number): number
	local cc = self.config
	local g = Workspace.Gravity
	local cf = part.CFrame
	local look, right, up = cf.LookVector, cf.RightVector, cf.UpVector
	local L0 = cc.SuspensionLength
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local zeta = cc.SuspensionDamping * damp
	local grip0 = cc.Grip * self.gripScale
	local grounded = 0
	for _, w in corners do
		local R = w.radius
		local origin = cf:PointToWorldSpace(Vector3.new(w.x, attachY, w.z))
		local hit = Workspace:Raycast(origin, -up * (L0 + R), self.rayParams)
		if not hit then
			w.force.Force = Vector3.zero
			w.length = L0
			w.grounded = false
			continue
		end
		grounded += 1
		w.grounded = true
		-- this corner's share of the weight sets its spring, damper and tyre
		local mw = mass * w.share + extra * w.kshare
		local K = mw * omega * omega
		local C = 2 * zeta * mw * omega
		local length = max(hit.Distance - R, 0)
		w.length = length
		local compression = L0 - length
		local pv = part:GetVelocityAtPosition(origin)
		local spring = K * compression - C * pv:Dot(up)
		if compression > L0 * 0.92 then
			spring += K * 6 * (compression - L0 * 0.92) -- bump stop
		end
		spring = clamp(spring, 0, mw * g * 12)

		-- tyre frame in the contact plane
		local n = hit.Normal
		local steer = w.front and self.steer or 0
		local wf = look * cos(steer) + right * sin(steer)
		wf = (wf - n * wf:Dot(n)).Unit
		local wr = wf:Cross(n)
		local cv = part:GetVelocityAtPosition(hit.Position)
		local vLong, vLat = cv:Dot(wf), cv:Dot(wr)

		local rear = not w.front and not w.trailer
		local grip
		if w.trailer then
			grip = grip0 * (cc.RearGrip or 1)
		elseif handbrake and rear then
			grip = cc.HandbrakeGrip * self.gripScale * (cc.RearGrip or 1)
		else
			grip = grip0 * (rear and (cc.RearGrip or 1) or 1)
		end
		local limit = grip * spring

		-- gravity pulling this corner along the ground; friction has to hold
		-- it (sideways always, lengthways only when parked)
		local gLong, gLat = -mw * g * wf.Y, -mw * g * wr.Y
		local fLat = -vLat * mw / dt * 0.6 - gLat
		local fLong
		if handbrake and (rear or w.trailer) then
			fLong = -clamp(vLong * mw / dt * 0.5, -mw * cc.BrakeDeceleration, mw * cc.BrakeDeceleration)
		elseif throttle > 0.05 then
			if vLong < -2 then
				fLong = mw * cc.BrakeDeceleration * throttle
			else
				fLong = throttle * mw * cc.Acceleration * max(0, 1 - (vLong / cc.TopSpeed) ^ 2)
			end
		elseif throttle < -0.05 then
			if vLong > 2 then
				fLong = mw * cc.BrakeDeceleration * throttle
			else
				fLong = throttle * mw * cc.Acceleration * 0.7 * max(0, 1 - (vLong / cc.ReverseSpeed) ^ 2)
			end
		elseif abs(vLong) < 4 then
			-- parked: hold the vehicle, even on a slope
			fLong = -clamp(vLong * mw / dt * 0.8, -mw * cc.BrakeDeceleration, mw * cc.BrakeDeceleration) - gLong
		else
			fLong = -clamp(vLong * mw / dt * 0.5, -mw * cc.CoastDeceleration, mw * cc.CoastDeceleration)
		end

		local mag = sqrt(fLat * fLat + fLong * fLong)
		if mag > limit and mag > 0 then
			local k = limit / mag
			fLat *= k
			fLong *= k
		end
		-- the spring pushes along the ground normal; pushing along the chassis'
		-- up axis would leak a horizontal force whenever the body pitches
		w.force.Force = n * spring + wf * fLong + wr * fLat
		w.spin = (w.spin + vLong / R * dt) % (2 * math.pi)
	end
	return grounded
end

--[[
	throttle: -1..1 (negative brakes, then reverses)
	steerInput: -1..1 (positive = right)
	handbrake: boolean
]]
function Car:step(dt: number, throttle: number, steerInput: number, handbrake: boolean)
	dt = clamp(dt, 1 / 240, 1 / 30)
	local cc = self.config
	local chassis = self.chassis
	local mass = chassis.AssemblyMass
	local cf = chassis.CFrame
	local look, up = cf.LookVector, cf.UpVector
	local vel = chassis.AssemblyLinearVelocity
	local speed = vel:Dot(look)
	self.speed = speed

	-- steering: less lock at speed, rate limited
	local target = clamp(steerInput, -1, 1) * self:_lock(speed)
	local rate = cc.SteerSpeed * cc.MaxSteerLow * dt
	self.steer += clamp(target - self.steer, -rate, rate)

	local tr = self.trailer
	local trailerMass = 0
	if tr then
		if tr.syncVelocity then
			-- just placed (or swapped in at speed): move with the tractor
			tr.chassis.AssemblyLinearVelocity = vel
			tr.chassis.AssemblyAngularVelocity = chassis.AssemblyAngularVelocity
			tr.syncVelocity = false
		end
		trailerMass = tr.chassis.AssemblyMass
	end

	-- damping is capped so one frame's force can never overshoot (the
	-- forces are held for the whole frame)
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local damp = min(1, self.dampBudget / (dt * self.dampRate * 2 * cc.SuspensionDamping * omega))
	local grounded = self:_corners(chassis, self.wheels, self.attachY, mass, trailerMass, dt, throttle, handbrake, damp)
	self.grounded = grounded

	-- stability assist (off with the handbrake, so drifts still work)
	local assist = cc.StabilityAssist or 0
	if assist > 0 and grounded >= 2 and not handbrake and abs(speed) > 6 then
		local size = chassis.Size
		local inertia = mass * (size.X * size.X + size.Z * size.Z) / 12
		-- steering right (+) turns clockwise seen from above: negative yaw
		local wanted = -speed * math.tan(self.steer) / self:wheelbase()
		local actual = chassis.AssemblyAngularVelocity:Dot(up)
		-- only against too much rotation (a spin, or turning the wrong way);
		-- never adds turn, so it cannot make the car oversteer
		if actual * wanted < 0 or abs(actual) > abs(wanted) then
			local tq = clamp(-(actual - wanted) * inertia * assist, -mass * 400, mass * 400)
			self.yawTorque.Torque = up * tq
		elseif self.yawTorque.Torque ~= Vector3.zero then
			self.yawTorque.Torque = Vector3.zero
		end
	elseif self.yawTorque.Torque ~= Vector3.zero then
		self.yawTorque.Torque = Vector3.zero
	end

	-- air drag, a gentle cap on top speed
	local drag = cc.Drag or 1.6e-4
	self.aero.Force = -vel * vel.Magnitude * mass * drag

	if tr then
		self:_stepTrailer(dt, throttle, handbrake, trailerMass, drag)
	end

	-- brake lights (only touch the parts when the state changes)
	local braking = (throttle < -0.05 and speed > 2) or handbrake
	if braking ~= self.braking then
		self.braking = braking
		for _, tl in self.taillights do
			tl.Material = braking and Enum.Material.Neon or Enum.Material.SmoothPlastic
			tl.Color = braking and rgb(255, 40, 30) or rgb(120, 16, 16)
		end
	end
end

function Car:_stepTrailer(dt: number, throttle: number, handbrake: boolean, mass: number, drag: number)
	local cc = self.config
	local tr = self.trailer
	local part = tr.chassis
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local damp = min(1, tr.dampBudget / (dt * tr.dampRate * 2 * cc.SuspensionDamping * omega))
	tr.grounded = self:_corners(part, tr.wheels, tr.attachY, mass, 0, dt, throttle, handbrake, damp)
	local vel = part.AssemblyLinearVelocity
	tr.aero.Force = -vel * vel.Magnitude * mass * drag

	-- roll coupling: a spring on the roll between trailer and tractor (a
	-- real fifth wheel plate is stiff in roll). The suspension dampers of
	-- both bodies damp it; a damper here, updated once per frame, fights
	-- the hitch joint and makes the rig shake.
	local tcf, ccf = part.CFrame, self.chassis.CFrame
	local lean = tcf.RightVector:Dot(ccf.UpVector) -- right side raised: > 0
	local tq = tcf.LookVector * ((tr.config.RollStiffness or 0) * lean * mass)
	tr.rollTorque.Torque = tq
	tr.reactionTorque.Torque = -tq
end

-- Move the visual wheels (call every render frame).
function Car:render(dt: number?)
	dt = dt or 1 / 60
	local speed = math.abs(self.speed)
	local spray = self.wetness > 0.2 and math.floor(math.min(speed / 60, 1) * self.wetness * 90) or 0
	if spray ~= self.sprayRate then
		self.sprayRate = spray
		for _, e in self.sprayEmitters do
			e.Rate = spray
		end
	end
	if self.kind == "Motorcycle" then
		Motorcycle.render(self, dt)
		self:_renderLights()
		return
	end
	local attachY = self.attachY
	for _, w in self.wheels do
		local steer = w.front and self.steer or 0
		local turn = CFrame.Angles(0, -steer, 0) * CFrame.Angles(-w.spin, 0, 0)
		for _, v in w.visuals do
			v.weld.C0 = CFrame.new(w.x + v.dx, attachY - w.length, w.z + v.dz) * turn
		end
	end
	local tr = self.trailer
	if tr then
		for _, w in tr.wheels do
			local turn = CFrame.Angles(-w.spin, 0, 0)
			for _, v in w.visuals do
				v.weld.C0 = CFrame.new(w.x + v.dx, tr.attachY - w.length, w.z + v.dz) * turn
			end
		end
	end
	self:_renderLights()
end

function Car:_renderLights()
	local speed = math.abs(self.speed)
	if self.engineSound then
		self.engineSound.PlaybackSpeed = 0.7 + math.min(speed / self.config.TopSpeed, 1.2) * 1.3
	end
	if self.windSound then
		self.windSound.Volume = math.min(speed / self.config.TopSpeed, 1) * 0.5
	end
	local clock = Lighting.ClockTime
	local night = clock < 6.6 or clock > 17.9
	if night ~= self.night then
		self.night = night
		for _, spot in self.headlights do
			spot.Enabled = night
		end
	end
end

function Car:destroy()
	self.model:Destroy()
end

return Car
