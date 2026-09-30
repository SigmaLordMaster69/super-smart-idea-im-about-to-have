--[[
	Vehicle test: builds every vehicle in the catalogue (procedural and with
	a fake premade model) and checks
	  * the spec and the Car interface other code relies on,
	  * part budgets (car 64, bike 45 without the rider, semi 110),
	  * no two faces of a body lie in the same plane and overlap, facing the
	    same way (they would flicker: "z-fighting"),
	  * wheels sit on the road where the suspension puts them,
	  * the trailer hangs on the fifth wheel, and teleport / shift / destroy
	    carry it along,
	  * render() and step() run, and the handling holds up.

	Handling runs the real Car:step force code: it is called once per frame
	(60 or 30 Hz) like the game does, and the forces it sets are then held
	while a rigid-body integrator below advances the bodies at 240 Hz (what
	the physics engine does between frames), on flat, sloped or banked
	ground. The trailer hitch is an impulse joint.

	  lune run tools/test_vehicles             checks (with a quick handling pass)
	  lune run tools/test_vehicles handling    full handling table: launch,
	      step steer at 60/100/150, lane change, swerve, braking in a turn,
	      wet road, the tightest bend with autodrive steering, a 7.5 % climb,
	      a banked road, and step steer / swerve at 30 FPS
]]

local process = require("@lune/process")
local env = require("./env")
local roblox = env.roblox
local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3

local Config = env.require("src/shared/Config")
local Car = env.require("src/client/Car")
local Vehicles = env.require("src/client/Vehicles")
local AssetLibrary = env.require("src/client/AssetLibrary")

local G = 196.2
env.workspace.Gravity = G
local deg = math.deg
local abs, max, min, clamp, atan2, sqrt = math.abs, math.max, math.min, math.clamp, math.atan2, math.sqrt

---------------------------------------------------------------------------
-- Rigid-body harness: Workspace:Raycast and BasePart:GetVelocityAtPosition
-- are answered from the simulated state
---------------------------------------------------------------------------
local Sim = {}

local bodies = {} -- part -> body state
local ground = { normal = Vector3.new(0, 1, 0), point = Vector3.zero }

function Sim.setGround(normal: Vector3, point: Vector3?)
	ground.normal = normal.Unit
	ground.point = point or Vector3.zero
end

roblox.implementMethod("Workspace", "Raycast", function(_, origin, dir, _params)
	local n = ground.normal
	local denom = dir:Dot(n)
	if denom >= -1e-9 then
		return nil
	end
	local t = (ground.point - origin):Dot(n) / denom
	if t < 0 or t > 1 then
		return nil
	end
	local len = dir.Magnitude
	return { Position = origin + dir * t, Normal = n, Distance = t * len, Instance = nil }
end)

roblox.implementMethod("BasePart", "GetVelocityAtPosition", function(part, pos)
	local b = bodies[part]
	if not b then
		return Vector3.zero
	end
	return b.v + b.w:Cross(pos - b.cf.Position)
end)

-- Lune keeps an Attachment's Position and CFrame separately: use whichever
-- the game code set
function Sim.attachmentPosition(att)
	local ok, p = pcall(function()
		return att.Position
	end)
	if ok and p then
		return p
	end
	return att.CFrame.Position
end

local function density(part)
	local pp = part.CustomPhysicalProperties
	if pp then
		return pp.Density
	end
	return 0.7
end

function Sim.addBody(part)
	local s = part.Size
	local m = density(part) * s.X * s.Y * s.Z
	local b = {
		part = part,
		m = m,
		I = Vector3.new(m * (s.Y * s.Y + s.Z * s.Z) / 12, m * (s.X * s.X + s.Z * s.Z) / 12, m * (s.X * s.X + s.Y * s.Y) / 12),
		cf = part.CFrame,
		v = Vector3.zero,
		w = Vector3.zero,
		forces = {},
		torques = {},
	}
	for _, d in part:GetDescendants() do
		if d:IsA("VectorForce") then
			table.insert(b.forces, d)
		elseif d:IsA("Torque") then
			table.insert(b.torques, d)
		end
	end
	bodies[part] = b
	part.AssemblyMass = m
	Sim.sync(b)
	return b
end

function Sim.sync(b)
	b.part.CFrame = b.cf
	b.part.AssemblyLinearVelocity = b.v
	b.part.AssemblyAngularVelocity = b.w
end

function Sim.reset()
	bodies = {}
end

-- world inverse inertia applied to a world vector
local function invI(b, vec)
	local lv = b.cf:VectorToObjectSpace(vec)
	return b.cf:VectorToWorldSpace(Vector3.new(lv.X / b.I.X, lv.Y / b.I.Y, lv.Z / b.I.Z))
end

local function applyImpulse(b, point, J)
	b.v += J / b.m
	b.w += invI(b, (point - b.cf.Position):Cross(J))
end

-- one integration step of dt for every body, with forces read from the instances
local function integrate(b, dt, g)
	local F = Vector3.new(0, -g * b.m, 0)
	local T = Vector3.zero
	local com = b.cf.Position
	for _, f in b.forces do
		local force = f.Force
		if f.RelativeTo ~= roblox.Enum.ActuatorRelativeTo.World then
			force = b.cf:VectorToWorldSpace(force)
		end
		F += force
		if not f.ApplyAtCenterOfMass and f.Attachment0 then
			local p = b.cf:PointToWorldSpace(Sim.attachmentPosition(f.Attachment0))
			T += (p - com):Cross(force)
		end
	end
	for _, t in b.torques do
		local tq = t.Torque
		if t.RelativeTo ~= roblox.Enum.ActuatorRelativeTo.World then
			tq = b.cf:VectorToWorldSpace(tq)
		end
		T += tq
	end
	for _, extra in b.extraF or {} do
		F += extra
	end
	b.v += F / b.m * dt
	-- Euler's equations in the body frame (with the gyroscopic term)
	local wl = b.cf:VectorToObjectSpace(b.w)
	local tl = b.cf:VectorToObjectSpace(T)
	local Iw = Vector3.new(b.I.X * wl.X, b.I.Y * wl.Y, b.I.Z * wl.Z)
	local rhs = tl - wl:Cross(Iw)
	wl += Vector3.new(rhs.X / b.I.X, rhs.Y / b.I.Y, rhs.Z / b.I.Z) * dt
	b.w = b.cf:VectorToWorldSpace(wl)
end

local function advance(b, dt)
	local p = b.cf.Position + b.v * dt
	local wm = b.w.Magnitude
	local rot = b.cf - b.cf.Position
	if wm > 1e-9 then
		rot = CFrame.fromAxisAngle(b.w / wm, wm * dt) * rot
	end
	b.cf = CFrame.new(p) * rot
	-- keep the rotation orthonormal
	b.cf = CFrame.fromMatrix(b.cf.Position, b.cf.RightVector, b.cf.UpVector)
end

-- joints: { a = body, b = body, pa = local point on a, pb = local point on b }
local joints = {}
function Sim.addJoint(a, b, pa: Vector3, pb: Vector3)
	table.insert(joints, { a = a, b = b, pa = pa, pb = pb })
end
function Sim.clearJoints()
	joints = {}
end

local function solveJoints(dt)
	for _ = 1, 12 do
		for _, j in joints do
			local A, B = j.a, j.b
			local wa = A.cf:PointToWorldSpace(j.pa)
			local wb = B.cf:PointToWorldSpace(j.pb)
			local ra, rb = wa - A.cf.Position, wb - B.cf.Position
			local va = A.v + A.w:Cross(ra)
			local vb = B.v + B.w:Cross(rb)
			local err = wa - wb
			local vrel = va - vb + err * (0.2 / dt)
			for _, n in { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis } do
				local k = 1 / A.m + 1 / B.m + n:Dot(invI(A, ra:Cross(n)):Cross(ra)) + n:Dot(invI(B, rb:Cross(n)):Cross(rb))
				local lambda = -vrel:Dot(n) / k
				applyImpulse(A, wa, n * lambda)
				applyImpulse(B, wb, -n * lambda)
				va = A.v + A.w:Cross(ra)
				vb = B.v + B.w:Cross(rb)
				vrel = va - vb + err * (0.2 / dt)
			end
		end
	end
end

--[[
	Run one frame: call control(frameDt) (which should call car:step), then
	integrate `sub` sub-steps.
]]
function Sim.frame(list, frameDt: number, sub: number, g: number)
	local h = frameDt / sub
	for _ = 1, sub do
		for _, b in list do
			integrate(b, h, g)
		end
		solveJoints(h)
		for _, b in list do
			advance(b, h)
		end
	end
	for _, b in list do
		Sim.sync(b)
	end
end

---------------------------------------------------------------------------
-- Handling scenarios
---------------------------------------------------------------------------
local function restGroundY(car)
	local cc = car.config
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local sag = G / (omega * omega)
	local attachY = car.attachY or -0.2
	return attachY - (cc.SuspensionLength - sag) - cc.WheelRadius
end

local function build(id, gripScale)
	Sim.reset()
	Sim.clearJoints()
	local car = Car.new(Config, Color3.new(1, 0, 0), nil, id)
	car:teleport(CFrame.new(0, -restGroundY(car), 0))
	car:setSurface(gripScale or 1, 0)
	local list = { Sim.addBody(car.chassis) }
	if car.trailer then
		local tb = Sim.addBody(car.trailer.chassis)
		table.insert(list, tb)
		local sock = car.trailer.socket
		Sim.addJoint(list[1], tb, Sim.attachmentPosition(sock.Attachment0), Sim.attachmentPosition(sock.Attachment1))
	end
	return car, list
end

local function setSpeed(list, v)
	for _, b in list do
		b.v = b.cf.LookVector * v
		b.w = Vector3.zero
		Sim.sync(b)
	end
end

local function wheelbase(car)
	if car.wheelbase then
		return car:wheelbase()
	end
	return 2 * (car.config.HalfBase or 4.9)
end

-- state metrics for one frame
local function measure(car, list)
	local b = list[1]
	local cf = b.cf
	local look, right, up = cf.LookVector, cf.RightVector, cf.UpVector
	local vLong, vLat = b.v:Dot(look), b.v:Dot(right)
	local beta = abs(vLong) > 1 and deg(atan2(vLat, abs(vLong))) or 0
	local yaw = b.w:Dot(up)
	local L = wheelbase(car)
	local kin = -vLong * math.tan(car.steer) / L
	-- rear axle slip
	local rearZ = 0
	for _, w in car.wheels do
		if not w.front then
			rearZ = w.z
		end
	end
	local pr = cf:PointToWorldSpace(Vector3.new(0, 0, rearZ))
	local vr = b.v + b.w:Cross(pr - cf.Position)
	local rearSlip = abs(vLong) > 1 and deg(atan2(vr:Dot(right), abs(vr:Dot(look)))) or 0
	-- lowest corner of the collision box above the ground
	local s = car.chassis.Size * 0.5
	local lowest = math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				lowest = min(lowest, cf:PointToWorldSpace(Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)).Y)
			end
		end
	end
	local m = {
		v = vLong,
		beta = beta,
		yaw = yaw,
		kin = kin,
		rearSlip = rearSlip,
		roll = deg(math.asin(clamp(right.Y, -1, 1))),
		clearance = lowest,
		grounded = car.grounded,
		pos = cf.Position,
		heading = deg(atan2(-look.X, -look.Z)),
	}
	if car.trailer and list[2] then
		local tb = list[2]
		local tl, tr = tb.cf.LookVector, tb.cf.RightVector
		m.articulation = deg(atan2(tl:Cross(look).Y, tl:Dot(look)))
		local ta = tb.cf:PointToWorldSpace(Vector3.new(0, 0, car.trailer.axleZ or 0))
		local tv = tb.v + tb.w:Cross(ta - tb.cf.Position)
		m.trailerSlip = abs(tv:Dot(tl)) > 1 and deg(atan2(tv:Dot(tr), abs(tv:Dot(tl)))) or 0
		m.trailerRoll = deg(math.asin(clamp(tr.Y, -1, 1)))
		local ts = car.trailer.chassis.Size * 0.5
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				m.clearance = min(m.clearance, tb.cf:PointToWorldSpace(Vector3.new(ts.X * sx, -ts.Y, ts.Z * sz)).Y)
			end
		end
	end
	return m
end

local FPS = 60
local function run(car, list, seconds, control, onFrame)
	local frames = math.floor(seconds * FPS + 0.5)
	for f = 1, frames do
		local t = f / FPS
		local thr, st, hb = control(t, measure(car, list))
		car:step(1 / FPS, thr, st, hb or false)
		Sim.frame(list, 1 / FPS, math.floor(240 / FPS + 0.5), G)
		if onFrame then
			onFrame(t, measure(car, list))
		end
	end
end

local function hold(v0)
	return function(m)
		return clamp((v0 - m.v) * 0.15, -1, 1)
	end
end

local results = {}
local function report(line)
	print(line)
	table.insert(results, line)
end

local function launch(id)
	local car, list = build(id)
	run(car, list, 0.5, function()
		return 0, 0
	end)
	local t60, t100, v10, vmax = nil, nil, 0, 0
	local minClear = math.huge
	local dur = car.trailer and 50 or 35
	run(car, list, dur, function()
		return 1, 0
	end, function(t, m)
		if not t60 and m.v >= 60 then
			t60 = t
		end
		if not t100 and m.v >= 100 then
			t100 = t
		end
		if abs(t - 10) < 1e-6 then
			v10 = m.v
		end
		vmax = max(vmax, m.v)
		minClear = min(minClear, m.clearance)
	end)
	report(string.format("  launch      0-60 %s s   0-100 %s s   v@10s %5.1f   top %5.1f   (TopSpeed %d)   min clearance %.2f",
		t60 and string.format("%4.1f", t60) or "  - ", t100 and string.format("%4.1f", t100) or "  - ", v10, vmax, car.config.TopSpeed, minClear))
	return vmax
end

local function stepSteer(id, v0, grip, label)
	local car, list = build(id, grip)
	setSpeed(list, v0)
	local speed = hold(v0)
	run(car, list, 1.0, function(_, m)
		return speed(m), 0
	end)
	local maxBeta, maxRear, spun = 0, 0, false
	local ratioSum, ratioN, alat, maxArt, maxTSlip, maxRoll, minGround, minClear = 0, 0, 0, 0, 0, 0, 4, math.huge
	local maxYawRatio = 0
	local steerMax = car:maxSteer()
	run(car, list, 3.5, function(_, m)
		return speed(m), 1
	end, function(t, m)
		maxBeta = max(maxBeta, abs(m.beta))
		maxRear = max(maxRear, abs(m.rearSlip))
		if abs(m.beta) > 15 or abs(m.rearSlip) > 18 then
			spun = true
		end
		if abs(m.kin) > 0.05 then
			maxYawRatio = max(maxYawRatio, m.yaw / m.kin)
		end
		if t > 2.5 and abs(m.kin) > 1e-3 then
			ratioSum += m.yaw / m.kin
			ratioN += 1
			alat = abs(m.v * m.yaw) / G
		end
		maxRoll = max(maxRoll, abs(m.roll))
		minGround = min(minGround, m.grounded)
		minClear = min(minClear, m.clearance)
		if m.articulation then
			maxArt = max(maxArt, abs(m.articulation))
			maxTSlip = max(maxTSlip, abs(m.trailerSlip))
			maxRoll = max(maxRoll, abs(m.trailerRoll))
		end
	end)
	local last = measure(car, list)
	local line = string.format("  %-10s  v %5.1f  lock %4.1f deg  yaw/kinematic %4.2f (peak %4.2f)  lat %4.2f g  max slip %4.1f deg  rear slip %4.1f  roll %4.1f  wheels>=%d  clear %.2f%s",
		label, last.v, deg(steerMax), ratioN > 0 and ratioSum / ratioN or 0, maxYawRatio, alat, maxBeta, maxRear, maxRoll, minGround, minClear, spun and "  SPUN" or "")
	if car.trailer then
		line ..= string.format("  articulation %4.1f  trailer slip %4.1f", maxArt, maxTSlip)
	end
	report(line)
	-- no slide, and the yaw rate follows the steering (within 10 %)
	return not spun and ratioN > 0 and abs(ratioSum / ratioN - 1) < 0.1
end

local function laneChange(id, grip, label)
	local car, list = build(id, grip)
	setSpeed(list, 100)
	local speed = hold(100)
	run(car, list, 1.0, function(_, m)
		return speed(m), 0
	end)
	local x0 = list[1].cf.Position
	local fwd0, right0 = list[1].cf.LookVector, list[1].cf.RightVector
	local offset = 12
	local maxBeta, maxYaw, maxLat, overshoot, settle, spun = 0, 0, 0, 0, nil, false
	local maxArt = 0
	run(car, list, 6, function(_, m)
		local b = list[1]
		local p = b.cf.Position - x0
		local along, side = p:Dot(fwd0), p:Dot(right0)
		local ahead = clamp(22 + abs(m.v) * 0.75, 26, 130)
		local target = fwd0 * (along + ahead) + right0 * offset
		local to = target - p
		local fwd = to:Dot(b.cf.LookVector)
		local sd = to:Dot(b.cf.RightVector)
		local alpha = atan2(sd, fwd)
		local dist = sqrt(fwd * fwd + sd * sd)
		local delta = math.atan(2 * car:wheelbase() * math.sin(alpha) / max(dist, 1))
		local st = clamp(delta / max(car:maxSteer(), 0.01), -1, 1)
		local _ = side
		return speed(m), st
	end, function(t, m)
		local p = list[1].cf.Position - x0
		local side = p:Dot(right0)
		maxBeta = max(maxBeta, abs(m.beta))
		maxYaw = max(maxYaw, abs(m.yaw))
		maxLat = max(maxLat, abs(m.v * m.yaw) / G)
		overshoot = max(overshoot, side - offset)
		if abs(side - offset) > 0.5 then
			settle = nil
		elseif not settle then
			settle = t
		end
		if abs(m.beta) > 15 then
			spun = true
		end
		if m.articulation then
			maxArt = max(maxArt, abs(m.articulation))
		end
	end)
	local line = string.format("  %-10s  settle %s s  overshoot %4.2f  max slip %4.1f deg  max yaw %4.2f rad/s  max lat %4.2f g%s",
		label, settle and string.format("%3.1f", settle) or " - ", overshoot, maxBeta, maxYaw, maxLat, spun and "  SPUN" or "")
	if car.trailer then
		line ..= string.format("  articulation %4.1f", maxArt)
	end
	report(line)
	return not spun and settle ~= nil
end

local function swerve(id, grip, label)
	local car, list = build(id, grip)
	setSpeed(list, 100)
	local speed = hold(100)
	run(car, list, 1.0, function(_, m)
		return speed(m), 0
	end)
	local maxBeta, spun, maxRear = 0, false, 0
	local h0 = measure(car, list).heading
	local maxArt, maxTSlip = 0, 0
	run(car, list, 4, function(t, m)
		local st = t < 0.45 and 1 or (t < 0.9 and -1 or 0)
		return speed(m), st
	end, function(_, m)
		maxBeta = max(maxBeta, abs(m.beta))
		maxRear = max(maxRear, abs(m.rearSlip))
		if abs(m.beta) > 15 then
			spun = true
		end
		if m.articulation then
			maxArt = max(maxArt, abs(m.articulation))
			maxTSlip = max(maxTSlip, abs(m.trailerSlip))
		end
	end)
	local m = measure(car, list)
	local line = string.format("  %-10s  max slip %4.1f deg  rear slip %4.1f  final yaw rate %5.2f  heading change %5.1f deg%s",
		label, maxBeta, maxRear, m.yaw, m.heading - h0, spun and "  SPUN" or "")
	if car.trailer then
		line ..= string.format("  articulation %4.1f  trailer slip %4.1f", maxArt, maxTSlip)
	end
	report(line)
	return not spun
end

local function brakeTurn(id, grip, label)
	local car, list = build(id, grip)
	setSpeed(list, 100)
	local speed = hold(100)
	run(car, list, 1.0, function(_, m)
		return speed(m), 0
	end)
	local maxBeta, spun, stopT = 0, false, nil
	local maxArt = 0
	run(car, list, 5, function(t, m)
		if t < 1.5 then
			return speed(m), 0.5
		end
		return -1, 0.5
	end, function(t, m)
		if abs(m.v) > 20 then
			maxBeta = max(maxBeta, abs(m.beta))
			if abs(m.beta) > 15 or abs(m.rearSlip) > 15 then
				spun = true
			end
		end
		if not stopT and t > 1.5 and m.v < 2 then
			stopT = t - 1.5
		end
		if m.articulation then
			maxArt = max(maxArt, abs(m.articulation))
		end
	end)
	local line = string.format("  %-10s  max slip %4.1f deg  stopped in %s s%s", label, maxBeta, stopT and string.format("%3.1f", stopT) or " - ", spun and "  SPUN" or "")
	if car.trailer then
		line ..= string.format("  articulation %4.1f", maxArt)
	end
	report(line)
	return not spun
end

-- follow a circle of radius R (the road's tightest bend) with AutoDrive's
-- pure pursuit, normalised by car:maxSteer()
local function curve(id, R, v0, label)
	local car, list = build(id)
	setSpeed(list, v0)
	local speed = hold(v0)
	-- circle to the right of the start, centre at +R along the right vector
	local b0 = list[1].cf
	local centre = b0.Position + b0.RightVector * R
	local maxErr, maxBeta, maxRear, maxArt, maxTSlip, alat = 0, 0, 0, 0, 0, 0
	local spun = false
	run(car, list, 12, function(_, m)
		local b = list[1]
		local p = b.cf.Position
		local rel = Vector3.new(p.X - centre.X, 0, p.Z - centre.Z)
		local ang = math.atan2(rel.Z, rel.X)
		-- the lookahead point further round the circle (clockwise seen from above)
		local ahead = clamp(22 + abs(m.v) * 0.75, 26, 130)
		local dir = 1
		local a2 = ang + dir * ahead / R
		local target = Vector3.new(centre.X + math.cos(a2) * R, p.Y, centre.Z + math.sin(a2) * R)
		local to = target - p
		local fwd = to:Dot(b.cf.LookVector)
		local sd = to:Dot(b.cf.RightVector)
		local alpha = atan2(sd, fwd)
		local dist = sqrt(fwd * fwd + sd * sd)
		local delta = math.atan(2 * car:wheelbase() * math.sin(alpha) / max(dist, 1))
		return speed(m), clamp(delta / max(car:maxSteer(), 0.01), -1, 1)
	end, function(t, m)
		if t > 4 then
			local p = list[1].cf.Position
			local r = Vector3.new(p.X - centre.X, 0, p.Z - centre.Z).Magnitude
			maxErr = max(maxErr, abs(r - R))
			maxBeta = max(maxBeta, abs(m.beta))
			maxRear = max(maxRear, abs(m.rearSlip))
			alat = abs(m.v * m.yaw) / G
			if m.articulation then
				maxArt = max(maxArt, abs(m.articulation))
				maxTSlip = max(maxTSlip, abs(m.trailerSlip))
			end
			if abs(m.rearSlip) > 12 then
				spun = true
			end
		end
	end)
	local line = string.format("  %-10s  R %d at %3d: path error %4.2f  lat %4.2f g  slip %4.1f deg  rear slip %4.1f%s", label, R, v0, maxErr, alat, maxBeta, maxRear, spun and "  SPUN" or "")
	if car.trailer then
		line ..= string.format("  articulation %4.1f  trailer slip %4.1f", maxArt, maxTSlip)
	end
	report(line)
	return not spun and maxErr < 5
end

-- climb a 7.5 % grade flat out from 60, then drive straight across a road
-- banked 4.5 degrees
local function slopes(id)
	local grade = 0.075
	Sim.setGround(Vector3.new(0, 1, grade).Unit)
	local car, list = build(id)
	setSpeed(list, 60)
	local vEnd
	run(car, list, 8, function()
		return 1, 0
	end, function(_, m)
		vEnd = m.v
	end)
	Sim.setGround(Vector3.new(math.sin(math.rad(4.5)), math.cos(math.rad(4.5)), 0))
	local car2, list2 = build(id)
	setSpeed(list2, 100)
	local speed = hold(100)
	local x0 = list2[1].cf.Position.X
	local maxBeta = 0
	run(car2, list2, 4, function(_, m)
		return speed(m), 0
	end, function(_, m)
		maxBeta = max(maxBeta, abs(m.beta))
	end)
	local drift = list2[1].cf.Position.X - x0
	Sim.setGround(Vector3.new(0, 1, 0))
	report(string.format("  %-10s  7.5%% climb: %5.1f studs/s after 8 s flat out   4.5 deg bank: drift %5.2f studs in 4 s, slip %4.1f deg", "slopes", vEnd, drift, maxBeta))
	return true
end

if process.args[1] == "handling" then
	local allOk = true
	for _, id in Vehicles.Order do
		local spec = Vehicles.get(id)
		report(string.format("%s (%s)", spec.name, spec.id))
		local top = launch(id)
		for _, v0 in { 60, 100, 150 } do
			if v0 <= top * 0.97 then
				allOk = stepSteer(id, v0, 1, "step " .. v0) and allOk
			else
				report(string.format("  step %-5d  skipped (top speed %.0f)", v0, top))
			end
		end
		allOk = laneChange(id, 1, "lane") and allOk
		allOk = swerve(id, 1, "swerve") and allOk
		allOk = brakeTurn(id, 1, "brake") and allOk
		for _, v0 in { 100, 150 } do
			if v0 <= top * 0.97 then
				allOk = stepSteer(id, v0, 0.78, "wet step " .. v0) and allOk
			end
		end
		allOk = laneChange(id, 0.78, "wet lane") and allOk
		allOk = swerve(id, 0.78, "wet swerve") and allOk
		allOk = curve(id, 154, math.min(95, math.floor(top * 0.9)), "curve") and allOk
		allOk = slopes(id) and allOk
		FPS = 30
		allOk = stepSteer(id, 100, 1, "30fps step") and allOk
		allOk = swerve(id, 1, "30fps swerve") and allOk
		FPS = 60
	end
	print(allOk and "NO SPIN-OUTS" or "SOME RUNS SPUN OR FAILED")
	process.exit(allOk and 0 or 1)
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local BUDGET = { Car = 64, Motorcycle = 45, Semi = 110 }

---------------------------------------------------------------------------
-- Faces of a part (world space), for the coplanar overlap check
---------------------------------------------------------------------------
local function partFaces(p)
	local cf, s = p.CFrame, p.Size * 0.5
	local hx, hy, hz = s.X, s.Y, s.Z
	local function W(x, y, z)
		return cf:PointToWorldSpace(Vector3.new(x, y, z))
	end
	local out = {}
	local centre
	local function face(verts)
		table.insert(out, { verts = verts })
	end
	if p:IsA("WedgePart") then
		centre = W(0, -hy / 3, hz / 3)
		face({ W(-hx, -hy, -hz), W(hx, -hy, -hz), W(hx, -hy, hz), W(-hx, -hy, hz) })
		face({ W(-hx, -hy, hz), W(hx, -hy, hz), W(hx, hy, hz), W(-hx, hy, hz) })
		face({ W(-hx, -hy, -hz), W(hx, -hy, -hz), W(hx, hy, hz), W(-hx, hy, hz) })
		face({ W(-hx, -hy, -hz), W(-hx, -hy, hz), W(-hx, hy, hz) })
		face({ W(hx, -hy, -hz), W(hx, -hy, hz), W(hx, hy, hz) })
	elseif p:IsA("CornerWedgePart") then
		centre = W(hx / 5, -3 * hy / 5, -hz / 5)
		local a, b, c, d = W(-hx, -hy, -hz), W(hx, -hy, hz), W(hx, -hy, -hz), W(-hx, -hy, hz)
		local apex = W(hx, hy, -hz)
		face({ a, c, b, d })
		face({ a, apex, c })
		face({ c, apex, b })
		face({ b, apex, d })
		face({ d, apex, a })
	elseif p:IsA("Part") and p.Shape == roblox.Enum.PartType.Cylinder then
		centre = cf.Position
		local r = min(p.Size.Y, p.Size.Z) * 0.5
		for _, sx in { -1, 1 } do
			local verts = {}
			for i = 0, 15 do
				local a = i / 16 * math.pi * 2
				table.insert(verts, W(sx * hx, r * math.cos(a), r * math.sin(a)))
			end
			face(verts)
		end
	elseif p:IsA("Part") and p.Shape == roblox.Enum.PartType.Ball then
		return {}
	else
		centre = cf.Position
		local function q(a, b, c, d)
			face({ W(a[1], a[2], a[3]), W(b[1], b[2], b[3]), W(c[1], c[2], c[3]), W(d[1], d[2], d[3]) })
		end
		q({ hx, -hy, -hz }, { hx, hy, -hz }, { hx, hy, hz }, { hx, -hy, hz })
		q({ -hx, -hy, -hz }, { -hx, hy, -hz }, { -hx, hy, hz }, { -hx, -hy, hz })
		q({ -hx, hy, -hz }, { hx, hy, -hz }, { hx, hy, hz }, { -hx, hy, hz })
		q({ -hx, -hy, -hz }, { hx, -hy, -hz }, { hx, -hy, hz }, { -hx, -hy, hz })
		q({ -hx, -hy, hz }, { hx, -hy, hz }, { hx, hy, hz }, { -hx, hy, hz })
		q({ -hx, -hy, -hz }, { hx, -hy, -hz }, { hx, hy, -hz }, { -hx, hy, -hz })
	end
	for _, f in out do
		local v = f.verts
		local n = (v[2] - v[1]):Cross(v[3] - v[1])
		if n.Magnitude < 1e-9 then
			n = (v[3] - v[1]):Cross(v[4] - v[1])
		end
		n = n.Unit
		local c = Vector3.zero
		for _, x in v do
			c += x
		end
		c /= #v
		if n:Dot(c - centre) < 0 then
			n = -n
		end
		f.normal, f.centre = n, c
		local lo, hi = v[1], v[1]
		for _, x in v do
			lo = Vector3.new(min(lo.X, x.X), min(lo.Y, x.Y), min(lo.Z, x.Z))
			hi = Vector3.new(max(hi.X, x.X), max(hi.Y, x.Y), max(hi.Z, x.Z))
		end
		f.lo, f.hi = lo, hi
	end
	return out
end

-- area of the overlap of two convex polygons (2D, lists of {x, y})
local function signedArea(poly)
	local a = 0
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		a += p[1] * q[2] - q[1] * p[2]
	end
	return a * 0.5
end

local function clipArea(subject, clip)
	if signedArea(subject) < 0 then
		local r = {}
		for i = #subject, 1, -1 do
			table.insert(r, subject[i])
		end
		subject = r
	end
	if signedArea(clip) < 0 then
		local r = {}
		for i = #clip, 1, -1 do
			table.insert(r, clip[i])
		end
		clip = r
	end
	local output = subject
	for i = 1, #clip do
		if #output == 0 then
			break
		end
		local a, b = clip[i], clip[i % #clip + 1]
		local function inside(p)
			return (b[1] - a[1]) * (p[2] - a[2]) - (b[2] - a[2]) * (p[1] - a[1]) >= -1e-9
		end
		local function cross(p, q)
			local dx1, dy1 = q[1] - p[1], q[2] - p[2]
			local dx2, dy2 = b[1] - a[1], b[2] - a[2]
			local den = dx1 * dy2 - dy1 * dx2
			if abs(den) < 1e-12 then
				return p
			end
			local t = ((a[1] - p[1]) * dy2 - (a[2] - p[2]) * dx2) / den
			return { p[1] + dx1 * t, p[2] + dy1 * t }
		end
		local input = output
		output = {}
		for j = 1, #input do
			local cur, prev = input[j], input[(j - 2) % #input + 1]
			if inside(cur) then
				if not inside(prev) then
					table.insert(output, cross(prev, cur))
				end
				table.insert(output, cur)
			elseif inside(prev) then
				table.insert(output, cross(prev, cur))
			end
		end
	end
	if #output < 3 then
		return 0
	end
	return abs(signedArea(output))
end

-- Coplanar, same-facing, overlapping faces between different parts.
local function coplanarOverlaps(parts)
	local faces = {}
	for _, p in parts do
		for _, f in partFaces(p) do
			f.part = p
			table.insert(faces, f)
		end
	end
	local found = {}
	for i = 1, #faces do
		local a = faces[i]
		for j = i + 1, #faces do
			local b = faces[j]
			if a.part ~= b.part and a.normal:Dot(b.normal) > 0.9995 then
				local tol = 0.03
				if a.lo.X <= b.hi.X + tol and b.lo.X <= a.hi.X + tol and a.lo.Y <= b.hi.Y + tol and b.lo.Y <= a.hi.Y + tol and a.lo.Z <= b.hi.Z + tol and b.lo.Z <= a.hi.Z + tol then
					if abs(a.normal:Dot(b.centre - a.centre)) < 0.0199 then
						local n = a.normal
						local u = n:Cross(abs(n.Y) < 0.9 and Vector3.yAxis or Vector3.xAxis).Unit
						local v = n:Cross(u)
						local function flat(verts)
							local out = {}
							for _, x in verts do
								table.insert(out, { x:Dot(u), x:Dot(v) })
							end
							return out
						end
						local area = clipArea(flat(a.verts), flat(b.verts))
						if area > 2e-3 then
							table.insert(found, string.format("%s / %s (%.3f studs^2)", a.part.Name, b.part.Name, area))
						end
					end
				end
			end
		end
	end
	return found
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function visibleParts(root, filter)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 and (not filter or filter(d)) then
			table.insert(out, d)
		end
	end
	return out
end

local function isWheelPart(d)
	return d:GetAttribute("IR_Wheel") == true
end

local function restHub(car)
	return car.attachY - car.restLength
end

-- place the vehicle on flat ground at y = 0 and start the integrator
local function onGround(car)
	Sim.reset()
	Sim.clearJoints()
	Sim.setGround(Vector3.new(0, 1, 0))
	car:teleport(CFrame.new(0, -car.groundY, 0))
	car:setSurface(1, 0)
	local list = { Sim.addBody(car.chassis) }
	if car.trailer then
		local tb = Sim.addBody(car.trailer.chassis)
		table.insert(list, tb)
		local sock = car.trailer.socket
		Sim.addJoint(list[1], tb, Sim.attachmentPosition(sock.Attachment0), Sim.attachmentPosition(sock.Attachment1))
	end
	return list
end

local function drive(car, list, seconds, throttle, steer)
	for _ = 1, math.floor(seconds * 60) do
		car:step(1 / 60, throttle, steer, false)
		Sim.frame(list, 1 / 60, 4, G)
	end
end

local function finite(v)
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and abs(v.X) < 1e7 and abs(v.Y) < 1e7 and abs(v.Z) < 1e7
end

-- fake premade model for a vehicle, deliberately off-origin and oversized
local function fakeBody(car)
	local cc = car.config
	local m = Instance.new("Model")
	m.Name = "Pack" .. car.vehicleId
	local L = cc.BodyLength * 1.4
	local function part(name, size, pos, parent)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = CFrame.new(pos + Vector3.new(300, 40, -200))
		p.Parent = parent or m
		return p
	end
	if car.kind == "Motorcycle" then
		part("Frame", Vector3.new(1.4, 3, L), Vector3.new(0, 3, 0))
		part("FrontWheel", Vector3.new(0.8, 3, 3), Vector3.new(0, 1.5, -L * 0.35))
		part("BackTire", Vector3.new(0.8, 3, 3), Vector3.new(0, 1.5, L * 0.35))
	else
		part("BodyShell", Vector3.new(9, 5, L), Vector3.new(0, 4, 0))
		for _, x in { -3.8, 3.8 } do
			for _, z in { -L * 0.32, L * 0.32 } do
				local w = Instance.new("Model")
				w.Name = "Wheel"
				part("Tyre", Vector3.new(1.4, 3.4, 3.4), Vector3.new(x, 1.7, z), w)
				w.Parent = m
			end
		end
	end
	local s = Instance.new("Script")
	s.Parent = m
	return m
end

---------------------------------------------------------------------------
-- catalogue
---------------------------------------------------------------------------
check(#Vehicles.Order == 8, "eight vehicles")
check(Vehicles.resolve("Car") == "Sedan" and Vehicles.resolve("Motorcycle") == "Naked", "old names still resolve")
check(Vehicles.resolve("nope") == Vehicles.Default, "unknown ids fall back to the default")
check(Vehicles.next("Cruiser") == "Sedan", "next wraps around")
for _, id in Vehicles.Order do
	local spec = Vehicles.get(id)
	check(spec.id == id and type(spec.name) == "string" and type(spec.description) == "string", id .. " spec strings")
	check(spec.category == "Car" or spec.category == "Bike", id .. " category")
	check(spec.kind == "Car" or spec.kind == "Motorcycle", id .. " kind")
	check(type(spec.colors) == "table" and #spec.colors > 0, id .. " colors")
	check(type(spec.tuning) == "table", id .. " tuning")
	check(Config.Sounds[spec.sound] ~= nil, id .. " sound key " .. tostring(spec.sound) .. " in Config.Sounds")
	check(spec.camera and spec.camera.distance and spec.camera.height and typeof(spec.camera.hood) == "Vector3", id .. " camera settings")
end

---------------------------------------------------------------------------
-- every vehicle, procedural
---------------------------------------------------------------------------
for _, id in Vehicles.Order do
	local spec = Vehicles.get(id)
	local color = spec.colors[1]
	local car = Car.new(Config, color, nil, id)
	local label = id

	-- interface
	check(car.kind == spec.kind and car.vehicleId == id and car.spec == spec, label .. " identity fields")
	check(car.model:IsA("Model") and car.chassis:IsA("BasePart") and car.model.PrimaryPart == car.chassis, label .. " model and chassis")
	check(car.speed == 0 and car.steer == 0 and #car.wheels == 4, label .. " speed, steer, four corners")
	check(#car.headlights >= 1 and #car.taillights >= 1, label .. " has headlights and brake lights")
	for _, spot in car.headlights do
		check(spot:IsA("SpotLight"), label .. " headlight is a SpotLight")
	end
	for _, name in { "step", "render", "setSurface", "maxSteer", "teleport", "shift", "getCFrame", "getVelocity", "setIgnore", "destroy" } do
		check(type(car[name]) == "function", label .. " method " .. name)
	end
	if spec.kind == "Motorcycle" then
		check(car.leanRoot ~= nil and car.seatTop ~= nil and car.frontWheel and car.rearWheel, label .. " lean root, seat and wheel rigs")
	end

	-- every visible part is a massless, non-colliding visual
	for _, p in visibleParts(car.model) do
		check(p.Massless and not p.CanCollide and not p.Anchored, label .. " visual part " .. p.Name .. " must be massless, non-colliding, unanchored")
	end

	-- part budget
	local bodyParts = visibleParts(car.model, function(d)
		return not d:GetAttribute("IR_Rider")
	end)
	local budget = id == "Semi" and BUDGET.Semi or BUDGET[spec.kind]
	print(string.format("%-10s %3d parts (budget %d)%s", id, #bodyParts, budget, car.trailerPartCount and string.format(", trailer %d", car.trailerPartCount) or ""))
	check(#bodyParts <= budget, string.format("%s has %d parts, budget %d", label, #bodyParts, budget))

	-- no coplanar overlapping faces: the static body, each wheel, the rider
	local static = visibleParts(car.model, function(d)
		return not isWheelPart(d) and not d:GetAttribute("IR_Rider")
	end)
	-- wheels move, so each wheel is checked on its own; bike wheel rigs are
	-- a tyre with the other pieces welded to it
	local wheelGroups = {}
	for _, w in car.wheels do
		for _, v in w.visuals or {} do
			local g = { v.part }
			for _, p in v.parts do
				table.insert(g, p)
			end
			table.insert(wheelGroups, g)
		end
	end
	if car.frontWheel then
		for _, rig in { car.frontWheel, car.rearWheel } do
			local g = { rig.part }
			for _, d in car.model:GetDescendants() do
				if d:IsA("WeldConstraint") and d.Part0 == rig.part then
					table.insert(g, d.Part1)
				end
			end
			table.insert(wheelGroups, g)
		end
		local skip = {}
		for _, g in wheelGroups do
			for _, p in g do
				skip[p] = true
			end
		end
		local kept = {}
		for _, p in static do
			if not skip[p] then
				table.insert(kept, p)
			end
		end
		static = kept
	end
	if car.trailer then
		for _, w in car.trailer.wheels do
			for _, v in w.visuals do
				local g = { v.part }
				for _, p in v.parts do
					table.insert(g, p)
				end
				table.insert(wheelGroups, g)
			end
		end
	end
	local clashes = coplanarOverlaps(static)
	for _, g in wheelGroups do
		for _, c in coplanarOverlaps(g) do
			table.insert(clashes, "wheel: " .. c)
		end
	end
	local rider = visibleParts(car.model, function(d)
		return d:GetAttribute("IR_Rider") == true
	end)
	for _, c in coplanarOverlaps(rider) do
		table.insert(clashes, "rider: " .. c)
	end
	for _, c in clashes do
		check(false, label .. " coplanar overlapping faces: " .. c)
	end

	-- wheels on the road
	local cf = car.chassis.CFrame
	if spec.kind == "Car" then
		for i, w in car.wheels do
			check(#w.visuals >= 1 and w.part and w.hub and w.weld, label .. " corner " .. i .. " has a wheel rig")
			for _, v in w.visuals do
				local p = cf:PointToObjectSpace(v.part.CFrame.Position)
				check(abs(p.Y - restHub(car)) < 0.02, string.format("%s wheel hub height %.2f, expected %.2f", label, p.Y, restHub(car)))
				check(abs(p.Z - (w.z + v.dz)) < 0.02 and abs(p.X - (w.x + v.dx)) < 0.02, label .. " wheel sits on its corner")
				check(abs((p.Y - w.radius) - car.groundY) < 0.02, label .. " tyre touches the road")
			end
			check((w.front and w.z < 0) or (not w.front and w.z > 0), label .. " front wheels are at -Z")
		end
	else
		for _, rig in { car.frontWheel, car.rearWheel } do
			local p = cf:PointToObjectSpace(rig.part.CFrame.Position)
			check(abs(p.Z - rig.z) < 0.02, label .. " bike wheel on its axle")
			check(abs((p.Y - rig.radius) - car.groundY) < 0.03, string.format("%s bike tyre touches the road (%.2f vs %.2f)", label, p.Y - rig.radius, car.groundY))
		end
		check(car.frontWheel.z < 0 and car.rearWheel.z > 0, label .. " front wheel ahead")
		check(abs(car.frontWheel.z - car.wheels[1].z) < 0.01 and abs(car.rearWheel.z - car.wheels[3].z) < 0.01, label .. " bike wheels match the physics axles")
		check(car.riderPartCount == nil or car.riderPartCount >= 9, label .. " blocky rider")
	end

	-- the trailer
	if car.trailer then
		local tr = car.trailer
		local sock = tr.socket
		check(sock:IsA("BallSocketConstraint") and sock.Attachment0.Parent == car.chassis and sock.Attachment1.Parent == tr.chassis, "trailer hitch joins tractor and trailer")
		check(tr.chassis:IsDescendantOf(car.model), "trailer is inside the vehicle model")
		local function hitchGap()
			local a = car.chassis.CFrame:PointToWorldSpace(Sim.attachmentPosition(sock.Attachment0))
			local b = tr.chassis.CFrame:PointToWorldSpace(Sim.attachmentPosition(sock.Attachment1))
			return (a - b).Magnitude
		end
		check(hitchGap() < 1e-3, "kingpin sits on the fifth wheel")
		local nc = false
		for _, d in tr.chassis:GetChildren() do
			nc = nc or (d:IsA("NoCollisionConstraint") and d.Part0 == car.chassis and d.Part1 == tr.chassis)
		end
		check(nc, "tractor and trailer do not collide with each other")
		check(#tr.wheels == 2, "trailer tandem has two physics corners")
		for _, w in tr.wheels do
			check(#w.visuals == 2, "trailer corner has two axles of wheels")
			for _, v in w.visuals do
				local p = tr.chassis.CFrame:PointToObjectSpace(v.part.CFrame.Position)
				check(abs((p.Y - w.radius) - tr.groundY) < 0.02, "trailer tyres touch the road")
			end
		end
		-- the trailer's road is the tractor's road
		local tractorRoad = car.chassis.CFrame:PointToWorldSpace(Vector3.new(0, car.groundY, 0)).Y
		local trailerRoad = tr.chassis.CFrame:PointToWorldSpace(Vector3.new(0, tr.groundY, 0)).Y
		check(abs(tractorRoad - trailerRoad) < 1e-3, "tractor and trailer rest on the same road height")
		-- teleport straightens it, shift keeps velocities, destroy takes it along
		tr.chassis.CFrame = tr.chassis.CFrame * CFrame.Angles(0, 0.4, 0)
		car:teleport(CFrame.new(100, 20, 50) * CFrame.Angles(0, 1.2, 0))
		check(hitchGap() < 1e-3, "teleport puts the trailer back on the hitch")
		check(tr.chassis.CFrame.LookVector:Dot(car.chassis.CFrame.LookVector) > 0.9999, "teleport straightens the trailer")
		car.chassis.AssemblyLinearVelocity = Vector3.new(0, 0, -50)
		car.chassis.AssemblyAngularVelocity = Vector3.new(0, 0.1, 0)
		tr.chassis.AssemblyLinearVelocity = Vector3.new(1, 0, -49)
		tr.chassis.AssemblyAngularVelocity = Vector3.new(0, 0.05, 0)
		local before = tr.chassis.CFrame.Position
		car:shift(Vector3.new(16000, 0, 0))
		check((tr.chassis.CFrame.Position - (before - Vector3.new(16000, 0, 0))).Magnitude < 1e-3, "shift moves the trailer")
		check(tr.chassis.AssemblyLinearVelocity == Vector3.new(1, 0, -49), "shift keeps the trailer's velocity")
		check(hitchGap() < 1e-3, "shift keeps the hitch together")
	end

	-- rendering a few frames
	car.speed = 40
	car.steer = 0.2
	car.chassis.AssemblyAngularVelocity = Vector3.new(0, -0.6, 0)
	car:setSurface(0.8, 0.9)
	local okRender, err = pcall(function()
		for _ = 1, 30 do
			car:render(1 / 60)
		end
	end)
	check(okRender, label .. " render: " .. tostring(err))
	if spec.kind == "Motorcycle" then
		-- a right turn tilts the top of the bike to +X (a negative roll)
		check(car.lean < -0.05 and car.leanWeld.C0.UpVector.X > 0.05, label .. " leans into a right turn")
	else
		local v = car.wheels[1].visuals[1]
		check(v.weld.C0.LookVector:Dot(Vector3.new(0, 0, -1)) < 0.999, label .. " front wheels steer")
	end
	check(car.sprayEmitters[1].Rate > 0, label .. " spray on a wet road")

	-- physics on flat ground
	car.speed, car.steer = 0, 0
	local list = onGround(car)
	drive(car, list, 1.2, 0, 0)
	local rest = car.chassis.CFrame.Position.Y
	check(abs(rest - (-car.groundY)) < 0.08, string.format("%s rides at its designed height (%.2f vs %.2f)", label, rest, -car.groundY))
	check(car.grounded == 4, label .. " all corners on the ground at rest")
	if car.trailer then
		check((car.trailer.grounded or 0) == 2, "trailer corners on the ground")
	end
	drive(car, list, 2, 1, 0)
	local fwd = car.chassis.CFrame.LookVector
	local v = car.chassis.AssemblyLinearVelocity:Dot(fwd)
	check(v > (car.trailer and 25 or 45), string.format("%s accelerates (%.1f studs/s after 2 s)", label, v))
	local h0 = car.chassis.CFrame.LookVector
	drive(car, list, 1, 0.3, 1)
	local h1 = car.chassis.CFrame.LookVector
	check(h0:Cross(h1).Y < -0.05, label .. " turns right when steered right")
	check(finite(car.chassis.CFrame.Position) and finite(car.chassis.AssemblyLinearVelocity), label .. " state stays finite")
	check(car:maxSteer() > 0 and car:steerLock() <= car.config.MaxSteerLow + 1e-6, label .. " steering lock")
	if car.trailer then
		local tr = car.trailer
		local a = car.chassis.CFrame:PointToWorldSpace(Sim.attachmentPosition(tr.socket.Attachment0))
		local b = tr.chassis.CFrame:PointToWorldSpace(Sim.attachmentPosition(tr.socket.Attachment1))
		check((a - b).Magnitude < 0.05, "hitch holds while driving")
	end

	local model = car.model
	car:destroy()
	check(model.Parent == nil, label .. " destroy removes the model")
end

---------------------------------------------------------------------------
-- premade models in Vehicles/<Id>/Body
---------------------------------------------------------------------------
local root = Instance.new("Folder")
root.Name = "InfiniteRoadAssets"
local vehiclesFolder = Instance.new("Folder")
vehiclesFolder.Name = "Vehicles"
vehiclesFolder.Parent = root
for _, id in Vehicles.Order do
	local probe = Car.new(Config, Color3.new(1, 1, 1), nil, id)
	local f = Instance.new("Folder")
	f.Name = id
	f.Parent = vehiclesFolder
	local body = Instance.new("Folder")
	body.Name = "Body"
	body.Parent = f
	fakeBody(probe).Parent = body
	probe:destroy()
end
local assets = AssetLibrary.new(root)
for _, id in Vehicles.Order do
	check(assets.vehicleBodies[id] ~= nil, id .. " premade slot picked up")
	local spec = Vehicles.get(id)
	local car = Car.new(Config, Color3.new(0.2, 0.4, 0.8), assets, id)
	car.chassis.AssemblyAngularVelocity = Vector3.zero
	for _, d in car.model:GetDescendants() do
		check(not d:IsA("LuaSourceContainer"), id .. " premade model kept a script")
	end
	if spec.kind == "Motorcycle" then
		local body = car.bikeParts:FindFirstChild("BikeBody")
		check(body ~= nil, id .. " premade bike attached")
		-- scaled to BodyLength: the wheels were at +-0.35 of 1.4 x length
		local expect = car.config.BodyLength * 0.35
		check(abs(car.frontWheel.z + expect) < 0.1 and abs(car.rearWheel.z - expect) < 0.1, string.format("%s premade bike wheels at %.2f / %.2f, expected %.2f", id, car.frontWheel.z, car.rearWheel.z, expect))
		local riderVisible = false
		for _, d in car.bikeParts:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("IR_Rider") then
				riderVisible = riderVisible or d.Transparency < 1
			end
		end
		check(riderVisible, id .. " rider stays on the premade bike")
	else
		check(car.model:FindFirstChild("Body") ~= nil and car.customBody, id .. " premade body attached")
		local expect = car.config.BodyLength * 0.32
		local w = car.wheels[1]
		check(abs(w.z + expect) < 0.1, string.format("%s premade wheel at z %.2f, expected %.2f", id, w.z, -expect))
		for _, p in visibleParts(car.model) do
			check(p:IsDescendantOf(car.model:FindFirstChild("Body")) or (car.trailer and p:IsDescendantOf(car.trailer.model)), id .. " procedural part " .. p.Name .. " still visible with a premade body")
		end
		if car.trailer then
			check(#visibleParts(car.trailer.model) > 20, "the trailer stays visible with a premade tractor")
		end
	end
	car:render(1 / 60)
	local list = onGround(car)
	drive(car, list, 0.5, 1, 0)
	check(finite(car.chassis.CFrame.Position), id .. " premade vehicle drives")
	car:destroy()
end

---------------------------------------------------------------------------
-- quick handling pass: full lock at 100 studs/s (dry, wet, and at 30 FPS,
-- where the old bike physics shook itself loose), a swerve, and the semi on
-- the road's tightest bend with autodrive steering
---------------------------------------------------------------------------
for _, id in Vehicles.Order do
	print(id .. " handling")
	check(stepSteer(id, 100, 1, "step 100"), id .. " holds full lock at 100 without sliding")
	check(stepSteer(id, 100, 0.78, "wet step 100"), id .. " holds full lock on a wet road")
	check(swerve(id, 1, "swerve"), id .. " swerve without a spin")
	FPS = 30
	check(stepSteer(id, 100, 1, "30fps step"), id .. " holds full lock at 30 FPS")
	FPS = 60
end
check(curve("Semi", 154, 94, "curve"), "tractor-trailer follows the tightest bend")

if failures == 0 then
	print("ALL VEHICLE CHECKS PASSED")
else
	print(failures .. " FAILURES")
	process.exit(1)
end
