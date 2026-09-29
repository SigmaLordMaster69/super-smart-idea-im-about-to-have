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
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

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

function Car.new(config, color: Color3)
	local self = setmetatable({}, Car)
	self.config = config.Car
	local cc = config.Car

	local model = Instance.new("Model")
	model.Name = "InfiniteRoadCar"

	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = CHASSIS_SIZE
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

	-- body
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

	-- corners: front-left, front-right, rear-left, rear-right (front is -Z)
	self.wheels = {}
	local mass = chassis:GetMass()
	for i, def in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = def[1] * HALF_TRACK, def[2] * HALF_BASE
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

		local wheel = Instance.new("Part")
		wheel.Name = "Wheel" .. i
		wheel.Shape = Enum.PartType.Cylinder
		wheel.Size = Vector3.new(1.5, cc.WheelRadius * 2, cc.WheelRadius * 2)
		wheel.Color = black
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
			front = def[2] < 0,
			force = force,
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

	self.steer = 0
	self.mass = mass
	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.FilterDescendantsInstances = { model }
	self.rayParams.IgnoreWater = true
	self.grounded = 0
	self.speed = 0
	return self
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

	local L0, R = cc.SuspensionLength, cc.WheelRadius
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local K = mw * omega * omega
	local C = 2 * cc.SuspensionDamping * mw * omega
	local rayLen = L0 + R

	local grounded = 0
	for _, w in self.wheels do
		local origin = cf:PointToWorldSpace(Vector3.new(w.x, ATTACH_Y, w.z))
		local hit = Workspace:Raycast(origin, -up * rayLen, self.rayParams)
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
		local grip = (handbrake and rear) and cc.HandbrakeGrip or cc.Grip
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
function Car:render()
	for _, w in self.wheels do
		local steer = w.front and self.steer or 0
		w.weld.C0 = CFrame.new(w.x, ATTACH_Y - w.length, w.z) * CFrame.Angles(0, -steer, 0) * CFrame.Angles(-w.spin, 0, 0)
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
