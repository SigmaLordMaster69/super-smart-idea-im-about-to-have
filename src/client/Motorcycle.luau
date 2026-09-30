--[[
	Motorcycle
	----------
	Visuals for the motorcycle variants of Car. Physics stay the same four
	raycast corners (they act like invisible outriggers and keep the bike
	stable); everything drawn hangs off a "lean root" that tilts into
	corners by the lateral acceleration, around the tyre contact line.

	Each bike's look comes from a module in VehicleBodies (Naked, Supermoto,
	Sportbike, Cruiser). It gives the steering geometry (rake, fork length),
	the wheels, the swingarm pivot, where the rider sits, puts their feet and
	holds the bars, and a build function for the bodywork. This module adds
	the rigs: the fork, bars and front wheel turn about the raked steering
	axis, and the swingarm follows the rear wheel up and down.

	The rider is a clone of the player's R15 avatar posed on the bike. If
	that is not possible (no character yet, R6 rig) a simple blocky rider in
	a helmet is used instead. Both are posed from the same points (seat,
	footpegs, grips, torso lean) with two-bone inverse kinematics, so a
	sportbike rider tucks in and a cruiser rider sits back with feet forward.

	A premade bike from InfiniteRoadAssets.Vehicles.<Id>.Body (or
	Motorcycle.Body for the naked bike) replaces the procedural bike (its
	parts named *wheel/tire/tyre/rim* spin and steer); the rider stays.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.VehicleBodies.Kit)

local Motorcycle = {}

local rad, exp, atan2, clamp, abs, sqrt, max, cos, sin = math.rad, math.exp, math.atan2, math.clamp, math.abs, math.sqrt, math.max, math.cos, math.sin
local rgb = Color3.fromRGB

local DARK = rgb(34, 34, 38)
local TYRE = rgb(26, 26, 28)
local SMOOTH = Enum.SurfaceType.Smooth

-- rider proportions (studs), close to an R15 avatar
local HIP_HALF = 0.5
local SHOULDER_HALF = 0.95
local TORSO = 1.85 -- hip joints to shoulder joints
local THIGH, SHIN = 1.3, 1.4
local UPPER_ARM, FOREARM = 1.15, 1.25

local function rawPart(v, name: string, size: Vector3, cf: CFrame, color: Color3, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Size = size
	p.Color = color
	if props then
		for k, val in props do
			p[k] = val
		end
	end
	p.CFrame = cf
	p.Parent = v.bikeParts
	v.bikePartCount += 1
	return p
end

--[[
	A wheel rig: a tyre part driven by a Weld from the lean root, with the
	crown of the tread, rim, spokes, hub and brake disc attached. Style:
	  radius, width, rimRatio, rim (colour), spokes (bars across the wheel,
	  each makes two spokes; 0 = solid disc), spokeWidth, knobby, disc
	  (brake disc side: -1 left, 1 right), sprocket (side), rimProps
]]
local function wheel(v, style, z: number, name: string)
	local cc = v.config
	local R = style.radius
	local w = style.width
	local baseY = R - cc.WheelRadius -- a visual radius that differs from the physics one
	local hub = CFrame.new(0, v.attachY - v.restLength + baseY, z)
	local cf = v.chassis.CFrame * hub
	local cyl = Enum.PartType.Cylinder
	local tyre = rawPart(v, name, Vector3.new(w, (R - 0.08) * 2, (R - 0.08) * 2), cf, TYRE)
	tyre.Shape = cyl
	local parts = {}
	local crown = rawPart(v, "Tread", Vector3.new(w * (style.knobby and 0.82 or 0.62), R * 2, R * 2), cf, style.knobby and rgb(40, 40, 42) or TYRE,
		style.knobby and { Material = Enum.Material.Pebble } or nil)
	crown.Shape = cyl
	table.insert(parts, crown)
	local rr = R * (style.rimRatio or 0.7)
	local rim = rawPart(v, "Rim", Vector3.new(w + 0.04, rr * 2, rr * 2), cf, style.rim or DARK, style.rimProps)
	rim.Shape = cyl
	table.insert(parts, rim)
	local thickest = w + 0.04
	for i = 1, style.spokes or 0 do
		local t = w + 0.1 + 0.05 * i
		thickest = t
		local spoke = rawPart(v, "Spoke", Vector3.new(t, style.spokeWidth or 0.16, rr * 1.9), cf * CFrame.Angles((i - 1) * math.pi / style.spokes, 0, 0), style.spokeColor or style.rim or DARK, style.rimProps)
		table.insert(parts, spoke)
	end
	local hubPart = rawPart(v, "Hub", Vector3.new(thickest + 0.1, 0.55, 0.55), cf, style.hub or rgb(150, 152, 156), { Material = Enum.Material.Metal })
	hubPart.Shape = cyl
	table.insert(parts, hubPart)
	if style.disc then
		local disc = rawPart(v, "BrakeDisc", Vector3.new(0.06, rr * 1.75, rr * 1.75), cf * CFrame.new(style.disc * (thickest * 0.5 + 0.1), 0, 0), rgb(172, 174, 178), { Material = Enum.Material.Metal })
		disc.Shape = cyl
		table.insert(parts, disc)
	end
	if style.sprocket then
		local sp = rawPart(v, "Sprocket", Vector3.new(0.08, rr * 1.35, rr * 1.35), cf * CFrame.new(style.sprocket * (thickest * 0.5 + 0.12), 0, 0), rgb(60, 60, 64), { Material = Enum.Material.Metal })
		sp.Shape = cyl
		table.insert(parts, sp)
	end
	for _, p in parts do
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = tyre
		wc.Part1 = p
		wc.Parent = p
	end
	local weld = Instance.new("Weld")
	weld.Part0 = v.leanRoot
	weld.Part1 = tyre
	weld.C0 = hub
	weld.Parent = tyre
	return { part = tyre, weld = weld, z = z, spin = 0, radius = R, baseY = baseY }
end

---------------------------------------------------------------------------
-- Riders
---------------------------------------------------------------------------

-- Middle joint of a two-bone limb from a to c, bending towards `pole`.
local function limb(a: Vector3, c: Vector3, l1: number, l2: number, pole: Vector3): Vector3
	local d = c - a
	local dist = clamp(d.Magnitude, abs(l1 - l2) + 0.01, l1 + l2 - 0.01)
	local dir = d.Unit
	local cosA = clamp((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)
	local sinA = sqrt(max(0, 1 - cosA * cosA))
	local perp = pole - dir * pole:Dot(dir)
	perp = perp.Magnitude > 1e-6 and perp.Unit or Vector3.yAxis
	return a + dir * (l1 * cosA) + perp * (l1 * sinA)
end

-- The riding pose as joint positions (ground space), from the bike's
-- seat, footpeg and grip points and the torso lean.
local function riderPose(p)
	local lean = rad(p.lean)
	local torsoDir = Vector3.new(0, cos(lean), -sin(lean))
	local hip = p.seat + Vector3.new(0, 0.3, 0)
	local shoulders = hip + torsoDir * TORSO
	local pose = { hip = hip, shoulders = shoulders, torsoDir = torsoDir, lean = lean }
	pose.head = shoulders + torsoDir * 0.45 + Vector3.new(0, 0.5, -0.05) + Vector3.new(0, 0, -sin(lean) * 0.25)
	for _, side in { -1, 1 } do
		local h = hip + Vector3.new(side * HIP_HALF, 0, 0)
		local foot = Vector3.new(side * abs(p.foot.X), p.foot.Y, p.foot.Z)
		local knee = limb(h, foot, THIGH, SHIN, Vector3.new(side * 0.35, 0.4, -1))
		local s = shoulders + Vector3.new(side * SHOULDER_HALF, 0, 0)
		local hand = Vector3.new(side * abs(p.hand.X), p.hand.Y, p.hand.Z)
		local elbow = limb(s, hand, UPPER_ARM, FOREARM, Vector3.new(side * 0.9, -1, 0.5))
		pose[side] = { hip = h, knee = knee, foot = foot, shoulder = s, elbow = elbow, hand = hand }
	end
	return pose
end

-- Motor6D angles that point a limb (hanging straight down by default)
-- along `d`: C0 *= CFrame.Angles(ax, 0, az).
local function limbAngles(d: Vector3): (number, number)
	d = d.Unit
	return atan2(-d.Z, -d.Y), math.asin(clamp(d.X, -1, 1))
end

local function bendAngle(a: Vector3, b: Vector3): number
	return math.acos(clamp(a.Unit:Dot(b.Unit), -1, 1))
end

local function posedAvatar(pose): Model?
	local player = Players.LocalPlayer
	local char = player and player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local was = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function()
		return char:Clone()
	end)
	char.Archivable = was
	if not ok or not clone then
		return nil
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.EvaluateStateMachine = false
		hum.PlatformStand = true
		hum.BreakJointsOnDeath = false
	end
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			-- the real character is hidden; restore how it looked
			local t = d:GetAttribute("IR_Transparency")
			d.Transparency = d.Name == "HumanoidRootPart" and 1 or (t or 0)
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = true
		elseif d:IsA("Decal") then
			d.Transparency = d:GetAttribute("IR_Transparency") or 0
		end
	end
	local function bend(partName, jointName, rot)
		local p = clone:FindFirstChild(partName)
		local j = p and p:FindFirstChild(jointName)
		if j and j:IsA("Motor6D") then
			j.C0 *= rot
		end
	end
	-- the riding pose: legs from the lower torso (upright), arms from the
	-- upper torso (leaned forward by the waist)
	local lean = pose.lean
	bend("UpperTorso", "Waist", CFrame.Angles(-lean, 0, 0))
	bend("Head", "Neck", CFrame.Angles(lean * 0.65, 0, 0))
	local toTorso = CFrame.Angles(lean, 0, 0)
	for side, names in { [-1] = "Left", [1] = "Right" } do
		local j = pose[side]
		local thigh, shin = j.knee - j.hip, j.foot - j.knee
		local ax, az = limbAngles(thigh)
		bend(names .. "UpperLeg", names .. "Hip", CFrame.Angles(ax, 0, az))
		bend(names .. "LowerLeg", names .. "Knee", CFrame.Angles(-bendAngle(thigh, shin), 0, 0))
		local upper, fore = j.elbow - j.shoulder, j.hand - j.elbow
		local sx, sz = limbAngles(toTorso:VectorToWorldSpace(upper))
		bend(names .. "UpperArm", names .. "Shoulder", CFrame.Angles(sx, 0, sz))
		bend(names .. "LowerArm", names .. "Elbow", CFrame.Angles(bendAngle(upper, fore), 0, 0))
	end
	clone.Name = "Rider"
	return clone
end

local function blockyRider(kit, pose, color: Color3)
	local jacket = color:Lerp(DARK, 0.55)
	local pants = rgb(46, 52, 66)
	local boots = rgb(24, 24, 26)
	local parts = {}
	local function add(p)
		table.insert(parts, p)
		return p
	end
	-- torso: a block from hips to shoulders, leaning forward
	local td = pose.torsoDir
	local side = Vector3.xAxis
	local fwd = side:Cross(td)
	add(kit:oriented("Torso", (pose.hip + pose.shoulders) * 0.5 + td * 0.1, side * 1.7, td * (TORSO + 0.45), fwd * 0.95, jacket))
	add(kit:ball("Helmet", pose.head, 1.3, color, { Reflectance = 0.15 }))
	add(kit:oriented("Visor", pose.head + Vector3.new(0, 0.06, -0.54), side * 0.9, Vector3.yAxis * 0.38, Vector3.zAxis * 0.24, rgb(20, 22, 26), { Material = Enum.Material.Glass, Reflectance = 0.3 }))
	for _, s in { -1, 1 } do
		local j = pose[s]
		add(kit:bar("Thigh", j.hip, j.knee, 0.72, pants))
		add(kit:bar("Shin", j.knee, j.foot + Vector3.new(0, 0.12, 0.1), 0.6, pants))
		add(kit:span("Boot", j.foot + Vector3.new(-0.24, -0.08, -0.45), j.foot + Vector3.new(0.24, 0.42, 0.3), boots))
		add(kit:bar("UpperArm", j.shoulder, j.elbow, 0.56, jacket))
		add(kit:bar("Forearm", j.elbow, j.hand, 0.5, jacket))
		add(kit:ball("Glove", j.hand, 0.5, boots))
	end
	for _, p in parts do
		p.Name = "Rider" .. p.Name
		p:SetAttribute("IR_Rider", true)
	end
	return parts
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Motorcycle.build(v, color: Color3, _config)
	local spec = v.spec
	local design = require(script.Parent.VehicleBodies[spec.body or spec.id])
	local chassis = v.chassis
	local gy = v.groundY
	v.bikeHubY, v.bikeGroundY = v.attachY - v.restLength, gy
	v.bikePartCount = 0
	v.design = design

	local folder = Instance.new("Model")
	folder.Name = "Bike"
	folder.Parent = v.model
	v.bikeParts = folder

	local root = Instance.new("Part")
	root.Name = "LeanRoot"
	root.Size = Vector3.new(0.5, 0.5, 0.5)
	root.Transparency = 1
	root.Massless = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = chassis.CFrame
	root.Parent = folder
	local leanWeld = Instance.new("Weld")
	leanWeld.Part0 = chassis
	leanWeld.Part1 = root
	leanWeld.Parent = root
	v.leanRoot, v.leanWeld = root, leanWeld

	local origin = chassis.CFrame * CFrame.new(0, gy, 0) -- ground space
	local kit = Kit.new(v, root, gy, color, folder, origin)

	-- geometry (ground space)
	local frontZ, rearZ = v.wheels[1].z, v.wheels[3].z
	local rake = rad(design.rake)
	local axis = Vector3.new(0, cos(rake), sin(rake)) -- steering axis, pointing up and back
	local frontAxle = Vector3.new(0, design.front.radius, frontZ)
	local rearAxle = Vector3.new(0, design.rear.radius, rearZ)
	local head = frontAxle + axis * design.forkLength
	local geo = {
		frontAxle = frontAxle,
		rearAxle = rearAxle,
		head = head,
		axis = axis,
		rake = rake,
		front = design.front,
		rear = design.rear,
	}
	v.bikeGeometry = geo

	-- steering rig: turns about the raked axis through the steering head
	local steerBase = CFrame.new(head + Vector3.new(0, gy, 0)) * CFrame.Angles(rake, 0, 0)
	local steer = Instance.new("Part")
	steer.Name = "SteerRig"
	steer.Size = Vector3.new(0.4, 0.4, 0.4)
	steer.Transparency = 1
	steer.Massless = true
	steer.CanCollide = false
	steer.CanQuery = false
	steer.CanTouch = false
	steer.CFrame = chassis.CFrame * steerBase
	steer.Parent = folder
	local steerWeld = Instance.new("Weld")
	steerWeld.Part0 = root
	steerWeld.Part1 = steer
	steerWeld.C0 = steerBase
	steerWeld.Parent = steer
	v.steerWeld, v.steerBase = steerWeld, steerBase
	local steerKit = Kit.new(v, steer, gy, color, folder, origin)

	-- swingarm rig: pivots behind the gearbox, follows the rear wheel
	local pivot = Vector3.new(0, design.swingarmPivot.Y, design.swingarmPivot.Z)
	local armBase = CFrame.new(pivot + Vector3.new(0, gy, 0))
	local arm = Instance.new("Part")
	arm.Name = "SwingarmRig"
	arm.Size = Vector3.new(0.4, 0.4, 0.4)
	arm.Transparency = 1
	arm.Massless = true
	arm.CanCollide = false
	arm.CanQuery = false
	arm.CanTouch = false
	arm.CFrame = chassis.CFrame * armBase
	arm.Parent = folder
	local armWeld = Instance.new("Weld")
	armWeld.Part0 = root
	armWeld.Part1 = arm
	armWeld.C0 = armBase
	armWeld.Parent = arm
	local toAxle = rearAxle - pivot
	v.swingarm = { weld = armWeld, base = armBase, rest = atan2(toAxle.Y, toAxle.Z) }
	local armKit = Kit.new(v, arm, gy, color, folder, origin)

	v.frontWheel = wheel(v, design.front, frontZ, "FrontWheel")
	v.rearWheel = wheel(v, design.rear, rearZ, "RearWheel")

	design.build({ body = kit, steer = steerKit, swingarm = armKit }, geo, color, v)
	v.bikePartCount += kit.count + steerKit.count + armKit.count

	-- rider
	local pose = riderPose(design.rider)
	v.riderPose = pose
	local rider = posedAvatar(pose)
	if rider then
		rider.Parent = folder
		local hrp = rider:FindFirstChild("HumanoidRootPart")
		if hrp then
			rider.PrimaryPart = hrp
			local seat = design.rider.seat
			rider:PivotTo(root.CFrame * CFrame.new(0, gy + seat.Y + 0.95, seat.Z))
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = hrp
			w.Parent = hrp
		else
			rider:Destroy()
			rider = nil
		end
	end
	if not rider then
		local before = kit.count
		blockyRider(kit, pose, color)
		v.riderPartCount = kit.count - before
	end
	v.seatTop = gy + design.rider.seat.Y
end

---------------------------------------------------------------------------
-- Premade bike model
---------------------------------------------------------------------------
function Motorcycle.applyBody(v, source: Instance, folder: Instance?)
	local AssetLibrary = require(script.Parent.AssetLibrary)
	local cc = v.config
	local body, size = AssetLibrary.prepare(source, folder, false)
	if not body then
		return
	end
	if body.PrimaryPart then
		body.PrimaryPart = nil
	end
	local factor = AssetLibrary.attribute(source, folder, "Scale") or 1
	if AssetLibrary.attribute(source, folder, "KeepSize") ~= true then
		factor *= cc.BodyLength / math.max(size.Z, 0.1)
	end
	if factor ~= 1 then
		body:ScaleTo(body:GetScale() * factor)
		size *= factor
	end
	-- wheels: parts named like wheels, front (-Z) and rear (+Z)
	local groups = { {}, {} }
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			local n = string.lower(p.Name .. " " .. (p.Parent and p.Parent.Name or ""))
			if (string.find(n, "wheel") or string.find(n, "tire") or string.find(n, "tyre") or string.find(n, "rim")) and not string.find(n, "steer") then
				local z = p.CFrame.Position.Z
				table.insert(groups[z < 0 and 1 or 2], p)
			end
		end
	end
	local hubY, groundY = v.bikeHubY, v.bikeGroundY
	-- body bottom on the ground
	body:PivotTo(v.chassis.CFrame * CFrame.new(0, groundY, 0))
	-- hide the procedural bike, keep the rider
	local rider = v.bikeParts:FindFirstChild("Rider")
	for _, d in v.bikeParts:GetDescendants() do
		if d:IsA("BasePart") and not d:GetAttribute("IR_Rider") and not (rider and d:IsDescendantOf(rider)) then
			d.Transparency = 1
		end
	end
	local wheelParts = {}
	local haveWheels = #groups[1] > 0 and #groups[2] > 0
	for gi, rig in { v.frontWheel, v.rearWheel } do
		if haveWheels then
			local lo, hi = AssetLibrary.boundsOf(groups[gi])
			local center = (lo + hi) * 0.5
			local local_ = v.chassis.CFrame:PointToObjectSpace(center)
			rig.z = local_.Z
			rig.radius = math.max(hi.Y - lo.Y, 0.4) * 0.5
			rig.part.CFrame = v.chassis.CFrame * CFrame.new(0, local_.Y, local_.Z)
			rig.weld.C0 = CFrame.new(0, local_.Y, local_.Z)
			rig.baseY = local_.Y - hubY
			for _, p in groups[gi] do
				wheelParts[p] = true
				local w = Instance.new("WeldConstraint")
				w.Part0 = rig.part
				w.Part1 = p
				w.Parent = p
			end
		end
	end
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") and not wheelParts[p] then
			local w = Instance.new("WeldConstraint")
			w.Part0 = v.leanRoot
			w.Part1 = p
			w.Parent = p
		end
	end
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.Massless = true
		end
	end
	v.swingarm = nil -- the premade bike has its own
	body.Name = "BikeBody"
	body.Parent = v.bikeParts
end

---------------------------------------------------------------------------
-- Per frame: lean, wheels, steering, swingarm
---------------------------------------------------------------------------
function Motorcycle.render(v, dt: number)
	local cc = v.config
	local chassis = v.chassis
	local g = Workspace.Gravity
	local up = chassis.CFrame.UpVector
	local yawRate = chassis.AssemblyAngularVelocity:Dot(up)
	-- lean into the turn: tan(lean) = lateral acceleration / g
	local target = clamp(atan2(v.speed * yawRate, g), -cc.LeanMax, cc.LeanMax)
	if abs(v.speed) < 3 then
		target = 0
	end
	v.lean += (target - v.lean) * (1 - exp(-7 * dt))
	local gy = v.bikeGroundY
	v.leanWeld.C0 = CFrame.new(0, gy, 0) * CFrame.Angles(0, 0, v.lean) * CFrame.new(0, -gy, 0)

	local w = v.wheels
	local front = (w[1].length + w[2].length) * 0.5
	local rear = (w[3].length + w[4].length) * 0.5
	local fw, rw = v.frontWheel, v.rearWheel
	fw.spin = (fw.spin + v.speed / fw.radius * dt) % (2 * math.pi)
	rw.spin = (rw.spin + v.speed / rw.radius * dt) % (2 * math.pi)
	-- the fork, bars and front wheel turn about the raked steering axis
	local turned = v.steerBase * CFrame.Angles(0, -v.steer, 0)
	v.steerWeld.C0 = turned
	local frontHub = CFrame.new(0, v.attachY - front + (fw.baseY or 0), fw.z)
	fw.weld.C0 = turned * v.steerBase:Inverse() * frontHub * CFrame.Angles(-fw.spin, 0, 0)
	local rearY = v.attachY - rear + (rw.baseY or 0)
	rw.weld.C0 = CFrame.new(0, rearY, rw.z) * CFrame.Angles(-rw.spin, 0, 0)
	local arm = v.swingarm
	if arm then
		local p = arm.base.Position
		local now = atan2(rearY - p.Y, rw.z - p.Z)
		arm.weld.C0 = arm.base * CFrame.Angles(-(now - arm.rest), 0, 0)
	end
end

return Motorcycle
