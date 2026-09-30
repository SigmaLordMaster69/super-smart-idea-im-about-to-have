--[[
	Car
	---
	A raycast-suspension car built from parts, simulated on the client.

	The chassis is one solid box. Each corner casts a ray down; if it hits,
	a spring/damper pushes the chassis up and tyre friction acts in the
	contact plane (drive, brake and cornering grip, limited by a friction
	circle). The forces go through one VectorForce per corner, so the
	physics engine applies them smoothly on every sub-step.

	Wheels are visual only: massless, non-colliding, moved every frame to
	where the suspension says they are.

	A premade car model in ReplicatedStorage.InfiniteRoadAssets.Car.Body
	replaces the part-built body. Its wheels (parts named *wheel*, *tire*,
	*tyre* or *rim*) are found automatically and attached to the suspension,
	so they spin, steer and bounce.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Motorcycle = require(script.Parent.Motorcycle)
local Vehicles = require(script.Parent.Vehicles)

local Car = {}
Car.__index = Car

local sqrt, cos, sin, max, min, clamp, abs = math.sqrt, math.cos, math.sin, math.max, math.min, math.clamp, math.abs
local rgb = Color3.fromRGB

local CHASSIS_SIZE = Vector3.new(7, 2.2, 15)
local HALF_TRACK = 3.15
local HALF_BASE = 4.9
local ATTACH_Y = -0.2 -- where the suspension rays start (chassis space)
local FORCE_Y = -0.5 -- where tyre forces are applied (a bit below centre)

local function weldTo(part: BasePart, chassis: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = chassis
	w.Part1 = part
	w.Parent = part
end

local function visual(model, chassis, className, props)
	local p = Instance.new(className)
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	local cf = props.CFrame
	props.CFrame = nil
	for k, v in props do
		p[k] = v
	end
	p.CFrame = chassis.CFrame * cf
	p.Parent = model
	weldTo(p, chassis)
	return p
end

-- the procedural car body (the chassis box itself is the lower body)
local function buildCarBody(self, model, chassis, color)
	local black = rgb(28, 28, 30)
	local glass = rgb(36, 44, 54)
	visual(model, chassis, "Part", { Name = "Hood", Size = Vector3.new(6.9, 0.5, 4.8), CFrame = CFrame.new(0, 1.35, -4.9), Color = color })
	visual(model, chassis, "Part", { Name = "Trunk", Size = Vector3.new(6.9, 0.5, 2.8), CFrame = CFrame.new(0, 1.35, 6.1), Color = color })
	visual(model, chassis, "Part", {
		Name = "Cabin", Size = Vector3.new(6.3, 2.3, 6.6), CFrame = CFrame.new(0, 2.25, 0.9),
		Color = glass, Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.15,
	})
	visual(model, chassis, "Part", { Name = "Roof", Size = Vector3.new(6.4, 0.35, 5.8), CFrame = CFrame.new(0, 3.55, 1.0), Color = color })
	visual(model, chassis, "WedgePart", {
		Name = "Windshield", Size = Vector3.new(6.3, 2.3, 2.4), CFrame = CFrame.new(0, 2.25, -3.6),
		Color = glass, Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.15,
	})
	visual(model, chassis, "WedgePart", {
		Name = "RearWindow", Size = Vector3.new(6.3, 2.3, 1.6), CFrame = CFrame.new(0, 2.25, 5.0) * CFrame.Angles(0, math.pi, 0),
		Color = glass, Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.15,
	})
	visual(model, chassis, "Part", { Name = "BumperFront", Size = Vector3.new(7.2, 0.8, 0.6), CFrame = CFrame.new(0, -0.55, -7.6), Color = black })
	visual(model, chassis, "Part", { Name = "BumperRear", Size = Vector3.new(7.2, 0.8, 0.6), CFrame = CFrame.new(0, -0.55, 7.6), Color = black })
	visual(model, chassis, "Part", { Name = "Grille", Size = Vector3.new(2.8, 0.6, 0.1), CFrame = CFrame.new(0, 0.35, -7.55), Color = black })

	self.headlights = {}
	for _, x in { -2.5, 2.5 } do
		local lamp = visual(model, chassis, "Part", {
			Name = "Headlight", Size = Vector3.new(1.6, 0.55, 0.15), CFrame = CFrame.new(x, 0.4, -7.55),
			Color = rgb(255, 250, 235), Material = Enum.Material.Neon,
		})
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 62
		spot.Range = 85
		spot.Brightness = 4
		spot.Color = rgb(255, 244, 222)
		spot.Shadows = true
		spot.Parent = lamp
		table.insert(self.headlights, spot)
	end
	self.taillights = {}
	for _, x in { -2.5, 2.5 } do
		table.insert(self.taillights, visual(model, chassis, "Part", {
			Name = "Taillight", Size = Vector3.new(1.6, 0.5, 0.15), CFrame = CFrame.new(x, 0.45, 7.55),
			Color = rgb(120, 16, 16),
		}))
	end
end

-- Vehicle tuning: Config.Car, with Config.Motorcycle on top for bikes.
-- Tuning for a vehicle id (or the old "Car" / "Motorcycle" kinds).
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

--[[
	id: a vehicle id from Vehicles (default "Sedan"; "Car" and "Motorcycle"
	still work). Cars and motorcycles use the same physics; motorcycles have
	a narrower, shorter footprint, their own tuning, and lean visually into
	corners.
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
	self.attachY = ATTACH_Y
	self.speed = 0
	self.steer = 0

	local model = Instance.new("Model")
	model.Name = kind == "Motorcycle" and "InfiniteRoadBike" or "InfiniteRoadCar"

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = cc.ChassisSize or CHASSIS_SIZE
	chassis.Color = color
	chassis.Material = Enum.Material.SmoothPlastic
	chassis.CanQuery = false
	chassis.CanTouch = false
	chassis.TopSurface = Enum.SurfaceType.Smooth
	chassis.BottomSurface = Enum.SurfaceType.Smooth
	chassis.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.2, 0.05, 1, 1)
	chassis.CFrame = CFrame.new(0, 50, 0)
	chassis.Parent = model
	model.PrimaryPart = chassis
	self.chassis = chassis
	self.model = model

	if kind == "Motorcycle" then
		chassis.Transparency = 1 -- the bike body is drawn by Motorcycle
		Motorcycle.build(self, color, config)
	else
		buildCarBody(self, model, chassis, color)
	end

	-- Corners: front-left, front-right, rear-left, rear-right (front is -Z).
	-- The motorcycle keeps four physics corners (like outriggers, which keep
	-- it stable); only its visual has two wheels.
	local halfTrack, halfBase = cc.HalfTrack or HALF_TRACK, cc.HalfBase or HALF_BASE
	self.wheels = {}
	for i, def in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = def[1] * halfTrack, def[2] * halfBase
		local att = Instance.new("Attachment")
		att.Name = "Force" .. i
		att.Position = Vector3.new(x, FORCE_Y, z)
		att.Parent = chassis
		local force = Instance.new("VectorForce")
		force.Attachment0 = att
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.ApplyAtCenterOfMass = false
		force.Force = Vector3.zero
		force.Parent = chassis

		if kind == "Motorcycle" then
			self.wheels[i] = {
				x = x,
				z = z,
				radius = cc.WheelRadius,
				front = def[2] < 0,
				force = force,
				attachment = att,
				length = cc.SuspensionLength,
				spin = 0,
				grounded = false,
			}
			continue
		end

		local wheel = Instance.new("Part")
		wheel.Name = "Wheel" .. i
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(1.5, cc.WheelRadius * 2, cc.WheelRadius * 2)
		wheel.Color = rgb(28, 28, 30)
		wheel.Material = Enum.Material.SmoothPlastic
		wheel.Massless = true
		wheel.CanCollide = false
		wheel.CanQuery = false
		wheel.CanTouch = false
		wheel.CFrame = chassis.CFrame * CFrame.new(x, ATTACH_Y - cc.SuspensionLength, z)
		wheel.Parent = model
		local hub = Instance.new("Part")
		hub.Name = "Hub"
		hub.Shape = Enum.PartType.Cylinder
		hub.Size = Vector3.new(1.56, cc.WheelRadius * 1.1, cc.WheelRadius * 1.1)
		hub.Color = rgb(196, 198, 202)
		hub.Material = Enum.Material.Metal
		hub.Massless = true
		hub.CanCollide = false
		hub.CanQuery = false
		hub.CanTouch = false
		hub.CFrame = wheel.CFrame
		hub.Parent = model
		local hw = Instance.new("WeldConstraint")
		hw.Part0 = wheel
		hw.Part1 = hub
		hw.Parent = hub
		local weld = Instance.new("Weld")
		weld.Part0 = chassis
		weld.Part1 = wheel
		weld.C0 = CFrame.new(x, ATTACH_Y - cc.SuspensionLength, z)
		weld.Parent = wheel

		self.wheels[i] = {
			x = x,
			z = z,
			radius = cc.WheelRadius,
			front = def[2] < 0,
			force = force,
			attachment = att,
			part = wheel,
			hub = hub,
			weld = weld,
			length = cc.SuspensionLength,
			spin = 0,
			grounded = false,
		}
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

	self.steer = 0
	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.FilterDescendantsInstances = { model }
	self.rayParams.IgnoreWater = true
	self.grounded = 0
	self.speed = 0

	if kind == "Car" and assets and assets.carSource then
		local ok, err = pcall(function()
			self:_applyBody(assets.carSource, assets.carFolder)
		end)
		if not ok then
			warn("[InfiniteRoad] could not use the car model from InfiniteRoadAssets.Car.Body: " .. tostring(err))
		end
	elseif kind == "Motorcycle" and assets and assets.bikeSource then
		local ok, err = pcall(Motorcycle.applyBody, self, assets.bikeSource, assets.bikeFolder)
		if not ok then
			warn("[InfiniteRoad] could not use the model from InfiniteRoadAssets.Motorcycle.Body: " .. tostring(err))
		end
	end
	self:_spray(cc)
	self:_sounds(config.Sounds)
	return self
end

-- Water / snow thrown up behind the wheels on wet roads.
function Car:_spray(cc)
	self.sprayEmitters = {}
	local halfTrack, halfBase = cc.HalfTrack or HALF_TRACK, cc.HalfBase or HALF_BASE
	local groundY = ATTACH_Y - cc.SuspensionLength - cc.WheelRadius + 0.6
	local xs = self.kind == "Motorcycle" and { 0 } or { -halfTrack, halfTrack }
	for _, x in xs do
		local att = Instance.new("Attachment")
		att.Name = "Spray"
		att.Position = Vector3.new(x, groundY, halfBase + 0.6)
		att.Parent = self.chassis
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
end

-- Road conditions from weather and season: grip multiplier and wetness
-- (0..1, drives the spray).
function Car:setSurface(gripScale: number, wetness: number)
	self.gripScale = gripScale
	self.wetness = wetness
end

-- Steering lock at the current speed (for autodrive).
function Car:maxSteer(): number
	local cc = self.config
	local t = clamp(abs(self.speed) / cc.TopSpeed, 0, 1)
	return cc.MaxSteerLow + (cc.MaxSteerHigh - cc.MaxSteerLow) * sqrt(t)
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

-- Swap the part-built body for a premade model.
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

	-- face -Z, bottom centre at the origin, scaled to the car's length
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

	local omega = 2 * math.pi * cc.SuspensionFrequency
	local restHubY = ATTACH_Y - (cc.SuspensionLength - Workspace.Gravity / (omega * omega))
	local centers = {}
	local offsetY
	if haveWheels then
		local sumY = 0
		for i = 1, 4 do
			local lo, hi = listBounds(corners[i])
			centers[i] = { center = (lo + hi) * 0.5, radius = max(hi.Y - lo.Y, hi.Z - lo.Z) * 0.5 }
			sumY += centers[i].center.Y
		end
		offsetY = restHubY - sumY / 4
	else
		offsetY = restHubY - cc.WheelRadius -- body bottom on the ground
	end
	body:PivotTo(chassis.CFrame * CFrame.new(0, offsetY, 0))

	-- hide the part-built body (lights keep working from hidden parts)
	for _, d in self.model:GetDescendants() do
		if d:IsA("BasePart") then
			local isOurWheel = false
			for _, w in self.wheels do
				if d == w.part or d == w.hub then
					isOurWheel = true
				end
			end
			if not isOurWheel or haveWheels then
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
			w.attachment.Position = Vector3.new(w.x, FORCE_Y, w.z)
			w.part.CFrame = chassis.CFrame * CFrame.new(w.x, hubY, w.z)
			w.hub.CFrame = w.part.CFrame
			for _, p in corners[i] do
				wheelParts[p] = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = w.part
				weld.Part1 = p
				weld.Parent = p
			end
			w.weld.C0 = CFrame.new(w.x, hubY, w.z)
		end
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

	-- the collision box follows the body's footprint
	chassis.Size = Vector3.new(clamp(size.X * 0.9, 5, 10), CHASSIS_SIZE.Y, clamp(size.Z * 0.95, 10, 22))
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
	self.steer = 0
end

-- Keep velocity, move by an offset (used when the world origin shifts).
function Car:shift(delta: Vector3)
	local c = self.chassis
	local v, w = c.AssemblyLinearVelocity, c.AssemblyAngularVelocity
	self.model:PivotTo(self.model:GetPivot() - delta)
	c.AssemblyLinearVelocity = v
	c.AssemblyAngularVelocity = w
end

function Car:getCFrame(): CFrame
	return self.chassis.CFrame
end

function Car:getVelocity(): Vector3
	return self.chassis.AssemblyLinearVelocity
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
	local mw = mass / 4
	local g = Workspace.Gravity
	local cf = chassis.CFrame
	local look, right, up = cf.LookVector, cf.RightVector, cf.UpVector
	local vel = chassis.AssemblyLinearVelocity
	local speed = vel:Dot(look)
	self.speed = speed

	-- steering: less lock at speed, rate limited
	local t = clamp(abs(speed) / cc.TopSpeed, 0, 1)
	local maxSteer = cc.MaxSteerLow + (cc.MaxSteerHigh - cc.MaxSteerLow) * sqrt(t)
	local target = clamp(steerInput, -1, 1) * maxSteer
	local rate = cc.SteerSpeed * cc.MaxSteerLow * dt
	self.steer += clamp(target - self.steer, -rate, rate)

	local L0 = cc.SuspensionLength
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local K = mw * omega * omega
	local C = 2 * cc.SuspensionDamping * mw * omega

	local grounded = 0
	for _, w in self.wheels do
		local R = w.radius
		local origin = cf:PointToWorldSpace(Vector3.new(w.x, ATTACH_Y, w.z))
		local hit = Workspace:Raycast(origin, -up * (L0 + R), self.rayParams)
		if not hit then
			w.force.Force = Vector3.zero
			w.length = L0
			w.grounded = false
			continue
		end
		grounded += 1
		w.grounded = true
		local length = max(hit.Distance - R, 0)
		w.length = length
		local compression = L0 - length
		local pv = chassis:GetVelocityAtPosition(origin)
		local spring = K * compression - C * pv:Dot(up)
		if compression > L0 * 0.92 then
			spring += K * 6 * (compression - L0 * 0.92) -- bump stop
		end
		spring = clamp(spring, 0, mass * g * 3)

		-- tyre frame in the contact plane
		local n = hit.Normal
		local steer = w.front and self.steer or 0
		local wf = look * cos(steer) + right * sin(steer)
		wf = (wf - n * wf:Dot(n)).Unit
		local wr = wf:Cross(n)
		local cv = chassis:GetVelocityAtPosition(hit.Position)
		local vLong, vLat = cv:Dot(wf), cv:Dot(wr)

		local rear = not w.front
		local grip = ((handbrake and rear) and cc.HandbrakeGrip or cc.Grip) * self.gripScale * (rear and (cc.RearGrip or 1) or 1)
		local limit = grip * spring

		-- gravity pulling this corner along the ground; friction has to hold
		-- it (sideways always, lengthways only when parked)
		local gLong, gLat = -mw * g * wf.Y, -mw * g * wr.Y
		local fLat = -vLat * mw / dt * 0.6 - gLat
		local fLong
		if handbrake and rear then
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
			-- parked: hold the car, even on a slope
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
	self.grounded = grounded

	-- stability assist (off with the handbrake, so drifts still work)
	local assist = cc.StabilityAssist or 0
	if assist > 0 and grounded >= 2 and not handbrake and abs(speed) > 6 then
		local size = chassis.Size
		local inertia = mass * (size.X * size.X + size.Z * size.Z) / 12
		local wheelbase = 2 * (cc.HalfBase or HALF_BASE)
		-- steering right (+) turns clockwise seen from above: negative yaw
		local wanted = -speed * math.tan(self.steer) / wheelbase
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
	local vmag = vel.Magnitude
	self.aero.Force = -vel * vmag * mass * 1.6e-4

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
	for _, w in self.wheels do
		local steer = w.front and self.steer or 0
		w.weld.C0 = CFrame.new(w.x, ATTACH_Y - w.length, w.z) * CFrame.Angles(0, -steer, 0) * CFrame.Angles(-w.spin, 0, 0)
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
