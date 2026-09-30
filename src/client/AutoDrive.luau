--[[
	AutoDrive
	---------
	Drives the car along the road hands-free, like slowroads' autodrive.

	Steering is pure pursuit: aim at a point in the middle of the lane a
	speed-dependent distance ahead. Speed comes from the tightest curve
	within braking distance, so the car slows down before bends.
]]

local AutoDrive = {}
AutoDrive.__index = AutoDrive

local abs, sqrt, max, min, clamp, atan, atan2 = math.abs, math.sqrt, math.max, math.min, math.clamp, math.atan, math.atan2

local WHEELBASE = 9.8

function AutoDrive.new(world, config)
	local self = setmetatable({}, AutoDrive)
	self.world = world
	self.config = config
	self.enabled = false
	self.lastS = nil
	return self
end

function AutoDrive:setEnabled(on: boolean)
	self.enabled = on
end

--[[
	carPos, carLook, carRight: world-space car frame
	speed: forward speed (studs/s)
	maxSteer: steering lock (radians) at the current speed
	wheelbase: the vehicle's wheelbase (studs)
	Returns throttle, steer in -1..1.
]]
function AutoDrive:compute(carPos: Vector3, carLook: Vector3, carRight: Vector3, speed: number, maxSteer: number, wheelbase: number?)
	local cfg = self.config
	local road = self.world.road
	local s = road:project(carPos.X, carPos.Z)
	self.lastS = s

	local lane = cfg.Road.LaneWidth * 0.5 * cfg.Road.DriveSide
	local ahead = clamp(22 + abs(speed) * 0.75, 26, 130)
	local p, _, r = road:frameAt(s + ahead)
	local target = p + r * lane

	-- pure pursuit in the horizontal plane
	local to = target - carPos
	local fwd = to:Dot(carLook)
	local side = to:Dot(carRight)
	local alpha = atan2(side, fwd)
	local dist = sqrt(fwd * fwd + side * side)
	local delta = atan(2 * (wheelbase or WHEELBASE) * math.sin(alpha) / max(dist, 1))
	local steer = clamp(delta / max(maxSteer, 0.01), -1, 1)

	-- speed limit from the curvature ahead
	local step = road.step
	local k0 = math.floor(s / step) + 1
	local lookSamples = math.floor((abs(speed) * abs(speed) / (2 * 55) + 80) / step)
	road:ensureY(k0 + lookSamples + 2)
	local latA = cfg.Car.AutoDriveLateralAccel
	local wanted = cfg.Car.AutoDriveSpeed
	for k = k0, k0 + lookSamples do
		local c = abs(road.curv[k] or 0)
		if c > 1e-4 then
			-- allow for braking from here to there
			local vCurve = sqrt(latA / c)
			local distTo = (k - k0) * step
			local vHere = sqrt(vCurve * vCurve + 2 * 55 * distTo)
			wanted = min(wanted, vHere)
		end
	end
	local throttle = clamp((wanted - speed) * 0.09, -1, 1)
	return throttle, steer
end

return AutoDrive
