--[[
	CameraController
	----------------
	Three camera modes, cycled with C:
	  Chase      smooth follow cam. Drag with the right mouse button (or the
	             right stick) to look around; it drifts back behind the car.
	  Hood       bonnet view.
	  Cinematic  roadside shots, like slowroads' cinematic cam: the camera
	             waits beside the road ahead, zooms in as the car approaches,
	             then jumps to the next spot.
]]

local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local CameraController = {}
CameraController.__index = CameraController

local exp, clamp, max, min, rad, deg, atan = math.exp, math.clamp, math.max, math.min, math.rad, math.deg, math.atan

CameraController.Modes = { "Chase", "Hood", "Cinematic" }

function CameraController.new(config, world, manager)
	local self = setmetatable({}, CameraController)
	self.config = config
	self.world = world
	self.manager = manager
	self.modeIndex = 1
	self.yaw, self.pitch = 0, rad(12)
	self.zoom = 1
	self.lastOrbit = 0
	self.heading = nil
	self.pos = nil
	self.rng = Random.new(world.seed + 5)
	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Include
	self.rayParams.FilterDescendantsInstances = { Workspace.Terrain }
	self.rayParams.IgnoreWater = true

	UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
				self:_orbit(input.Delta.X * 0.006, input.Delta.Y * 0.004)
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			self.zoom = clamp(self.zoom - input.Position.Z * 0.1, 0.55, 2.6)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = input.Position
			if v.Magnitude > 0.2 then
				self._stick = Vector2.new(v.X, v.Y)
			else
				self._stick = nil
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)
	return self
end

function CameraController:mode(): string
	return CameraController.Modes[self.modeIndex]
end

function CameraController:cycle(): string
	self.modeIndex = self.modeIndex % #CameraController.Modes + 1
	self.spot = nil
	self.pos = nil
	return self:mode()
end

function CameraController:_orbit(dx: number, dy: number)
	self.yaw -= dx
	self.pitch = clamp(self.pitch + dy, rad(-8), rad(60))
	self.lastOrbit = os.clock()
end

-- The world origin moved by delta: shift everything stored in Roblox space.
function CameraController:shift(delta: Vector3)
	if self.pos then
		self.pos -= delta
	end
	local cam = Workspace.CurrentCamera
	cam.CFrame -= delta
end

function CameraController:update(dt: number, car)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local cf = car:getCFrame()
	local vel = car:getVelocity()
	local speed = vel.Magnitude
	local carPos = cf.Position

	if self._stick then
		self:_orbit(-self._stick.X * dt * 2.2, -self._stick.Y * dt * 1.5)
	end

	local mode = self:mode()
	if mode == "Hood" then
		local target = cf * CFrame.new(0, 2.7, -2.2)
		if self.pos then
			target = cam.CFrame:Lerp(target, 1 - exp(-25 * dt))
		end
		cam.CFrame = target
		cam.FieldOfView = 78
		self.pos = target.Position
		return
	elseif mode == "Cinematic" then
		self:_cinematic(dt, cam, carPos, speed)
		return
	end

	-- chase: follow the direction of travel when moving
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z).Unit
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local desiredHeading = (flatVel.Magnitude > 12 and flatVel:Dot(look) > 0) and flatVel.Unit or look
	if not self.heading then
		self.heading = desiredHeading
	end
	self.heading = self.heading:Lerp(desiredHeading, 1 - exp(-3.5 * dt)).Unit

	if os.clock() - self.lastOrbit > 1.6 then
		self.yaw *= exp(-2.5 * dt)
		self.pitch += (rad(12) - self.pitch) * (1 - exp(-2.5 * dt))
	end
	local heading = CFrame.Angles(0, self.yaw, 0):VectorToWorldSpace(self.heading)
	local dist = (17 + speed * 0.035) * self.zoom
	local focus = carPos + Vector3.new(0, 3, 0)
	local desired = focus - heading * dist * math.cos(self.pitch) + Vector3.new(0, dist * math.sin(self.pitch) + 1.5, 0)

	if not self.pos then
		self.pos = desired
	end
	self.pos = self.pos:Lerp(desired, 1 - exp(-9 * dt))

	-- keep the camera out of the terrain
	local dir = self.pos - focus
	local hit = Workspace:Raycast(focus, dir, self.rayParams)
	local camPos = self.pos
	if hit then
		camPos = hit.Position - dir.Unit * 1.2
	end
	cam.CFrame = CFrame.lookAt(camPos, focus + heading * 6)
	cam.FieldOfView = 70 + clamp(speed / 150, 0, 1) * 10
end

function CameraController:_pickSpot(sCar: number)
	local world = self.world
	local road = world.road
	local rng = self.rng
	local hw = self.config.Road.HalfWidth
	local s = sCar + rng:NextNumber(170, 320)
	local k = math.floor(s / road.step) + 1
	road:ensureFlags(k + 2)
	local p, _, r = road:frameAt(s)
	local side = rng:NextNumber() < 0.5 and -1 or 1
	local d, height
	if road:isTunnel(k) then
		d, height = side * (hw - 4), 6
	elseif road:isBridge(k) then
		d, height = side * rng:NextNumber(60, 140), rng:NextNumber(-25, 10)
	else
		d, height = side * (hw + rng:NextNumber(14, 55)), rng:NextNumber(3, 20)
	end
	local spot = p + r * d
	local robloxSpot = self.manager:toRoblox(spot)
	local hit = Workspace:Raycast(robloxSpot + Vector3.new(0, 400, 0), Vector3.new(0, -900, 0), self.rayParams)
	local groundY = hit and hit.Position.Y or robloxSpot.Y
	self.spot = Vector3.new(spot.X, groundY + max(height, 3), spot.Z)
	self.spotS = s
end

function CameraController:_cinematic(dt, cam, carPos, speed)
	local worldCar = self.manager:toWorld(carPos)
	local sCar = self.world.road:project(worldCar.X, worldCar.Z)
	if not self.spot or sCar > self.spotS + 45 or (self.manager:toRoblox(self.spot) - carPos).Magnitude > 520 then
		self:_pickSpot(sCar)
	end
	local spot = self.manager:toRoblox(self.spot)
	local target = carPos + Vector3.new(0, 2, 0)
	local dist = (target - spot).Magnitude
	local aim = CFrame.lookAt(spot, target)
	if self.pos and (self.pos - spot).Magnitude < 1 then
		aim = cam.CFrame:Lerp(aim, 1 - exp(-12 * dt))
	end
	cam.CFrame = aim
	self.pos = spot
	cam.FieldOfView = clamp(2 * deg(atan(16 / max(dist, 1))), 9, 70)
end

return CameraController
