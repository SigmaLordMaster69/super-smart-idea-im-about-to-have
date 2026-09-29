--[[
	Motorcycle
	----------
	Visuals for the motorcycle variant of Car. Physics stay the same four
	raycast corners (they act like invisible outriggers and keep the bike
	stable); everything drawn hangs off a "lean root" that tilts into
	corners by the lateral acceleration, around the tyre contact line.

	The rider is a clone of the player's R15 avatar posed on the bike. If
	that is not possible (no character yet, R6 rig) a simple blocky rider in
	a helmet is used instead.

	A premade bike from InfiniteRoadAssets.Motorcycle.Body replaces the
	procedural bike (its parts named *wheel/tire/tyre/rim* spin and steer);
	the rider stays.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Motorcycle = {}

local rad, exp, atan2, clamp, abs = math.rad, math.exp, math.atan2, math.clamp, math.abs
local rgb = Color3.fromRGB

local DARK = rgb(34, 34, 38)
local METAL = rgb(186, 188, 192)
local TYRE = rgb(26, 26, 28)

-- geometry in chassis space
local function geometry(v)
	local cc = v.config
	local omega = 2 * math.pi * cc.SuspensionFrequency
	local sag = Workspace.Gravity / (omega * omega)
	local hubY = v.attachY - (cc.SuspensionLength - sag)
	return hubY, hubY - cc.WheelRadius, cc.HalfBase, cc.WheelRadius
end

local function newPart(className, props)
	local p = Instance.new(className or "Part")
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, val in props do
		p[k] = val
	end
	return p
end

-- part fixed to the lean root, `cf` in chassis space
local function fixed(v, props, cf, className)
	local p = newPart(className, props)
	p.CFrame = v.chassis.CFrame * cf
	p.Parent = v.bikeParts
	local w = Instance.new("WeldConstraint")
	w.Part0 = v.leanRoot
	w.Part1 = p
	w.Parent = p
	return p
end

-- a bar between two chassis-space points
local function bar(v, a: Vector3, b: Vector3, thickness: number, color: Color3, material)
	local mid = (a + b) * 0.5
	return fixed(v, {
		Name = "Bar",
		Size = Vector3.new(thickness, thickness, (b - a).Magnitude),
		Color = color,
		Material = material or Enum.Material.Metal,
	}, CFrame.lookAt(mid, b))
end

-- a wheel rig: a hub part driven by a Weld, with tyre and rim attached
local function wheel(v, z: number, hubY: number, r: number, name: string)
	local cf = v.chassis.CFrame * CFrame.new(0, hubY, z)
	local tyre = newPart("Part", {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.85, r * 2, r * 2),
		Color = TYRE,
	})
	tyre.CFrame = cf
	tyre.Parent = v.bikeParts
	local rim = newPart("Part", {
		Name = "Rim",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.9, r * 1.25, r * 1.25),
		Color = METAL,
		Material = Enum.Material.Metal,
	})
	rim.CFrame = cf
	rim.Parent = v.bikeParts
	local wc = Instance.new("WeldConstraint")
	wc.Part0 = tyre
	wc.Part1 = rim
	wc.Parent = rim
	local weld = Instance.new("Weld")
	weld.Part0 = v.leanRoot
	weld.Part1 = tyre
	weld.C0 = CFrame.new(0, hubY, z)
	weld.Parent = tyre
	return { part = tyre, weld = weld, z = z, spin = 0 }
end

---------------------------------------------------------------------------
-- Riders
---------------------------------------------------------------------------
local function posedAvatar(): Model?
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
	-- riding pose
	local function bend(partName, jointName, rot)
		local p = clone:FindFirstChild(partName)
		local j = p and p:FindFirstChild(jointName)
		if j and j:IsA("Motor6D") then
			j.C0 *= rot
		end
	end
	bend("LeftUpperLeg", "LeftHip", CFrame.Angles(rad(72), 0, rad(-10)))
	bend("RightUpperLeg", "RightHip", CFrame.Angles(rad(72), 0, rad(10)))
	bend("LeftLowerLeg", "LeftKnee", CFrame.Angles(rad(-80), 0, 0))
	bend("RightLowerLeg", "RightKnee", CFrame.Angles(rad(-80), 0, 0))
	bend("LeftUpperArm", "LeftShoulder", CFrame.Angles(rad(62), 0, rad(-12)))
	bend("RightUpperArm", "RightShoulder", CFrame.Angles(rad(62), 0, rad(12)))
	bend("LeftLowerArm", "LeftElbow", CFrame.Angles(rad(18), 0, 0))
	bend("RightLowerArm", "RightElbow", CFrame.Angles(rad(18), 0, 0))
	bend("UpperTorso", "Waist", CFrame.Angles(rad(-22), 0, 0))
	clone.Name = "Rider"
	return clone
end

local function blockyRider(v, seatTop: number, color: Color3)
	local jacket = color:Lerp(DARK, 0.55)
	local pants = rgb(46, 52, 66)
	local lean = CFrame.Angles(rad(-22), 0, 0)
	local parts = {
		fixed(v, { Name = "Torso", Size = Vector3.new(1.8, 2.1, 1.0), Color = jacket }, CFrame.new(0, seatTop + 1.25, 0.9) * lean),
		fixed(v, { Name = "Helmet", Shape = Enum.PartType.Ball, Size = Vector3.new(1.45, 1.45, 1.45), Color = color }, CFrame.new(0, seatTop + 2.75, 0.35)),
		fixed(v, { Name = "Visor", Size = Vector3.new(1.05, 0.45, 0.2), Color = rgb(20, 22, 26), Material = Enum.Material.Glass, Reflectance = 0.3 }, CFrame.new(0, seatTop + 2.8, -0.35)),
	}
	for _, x in { -1, 1 } do
		table.insert(parts, bar(v, Vector3.new(x * 0.95, seatTop + 2.0, 0.6), Vector3.new(x * 1.05, seatTop + 1.15, -1.55), 0.55, jacket, Enum.Material.SmoothPlastic))
		table.insert(parts, bar(v, Vector3.new(x * 0.5, seatTop + 0.35, 1.0), Vector3.new(x * 0.62, seatTop + 0.3, -0.6), 0.7, pants, Enum.Material.SmoothPlastic))
		table.insert(parts, bar(v, Vector3.new(x * 0.62, seatTop + 0.3, -0.6), Vector3.new(x * 0.62, seatTop - 1.25, -0.2), 0.6, pants, Enum.Material.SmoothPlastic))
	end
	for _, p in parts do
		p.Name = "Rider" .. p.Name
		p:SetAttribute("IR_Rider", true)
	end
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function Motorcycle.build(v, color: Color3, config)
	local chassis = v.chassis
	local hubY, groundY, halfBase, r = geometry(v)
	v.bikeHubY, v.bikeGroundY = hubY, groundY

	local folder = Instance.new("Model")
	folder.Name = "Bike"
	folder.Parent = v.model
	v.bikeParts = folder

	local root = newPart("Part", { Name = "LeanRoot", Size = Vector3.new(0.5, 0.5, 0.5), Transparency = 1 })
	root.CFrame = chassis.CFrame
	root.Parent = folder
	local leanWeld = Instance.new("Weld")
	leanWeld.Part0 = chassis
	leanWeld.Part1 = root
	leanWeld.Parent = root
	v.leanRoot, v.leanWeld = root, leanWeld

	local seatTop = hubY + 1.95
	-- body
	fixed(v, { Name = "Engine", Size = Vector3.new(1.5, 1.4, 2.3), Color = DARK, Material = Enum.Material.Metal }, CFrame.new(0, hubY + 0.35, 0.1))
	fixed(v, { Name = "Tank", Size = Vector3.new(1.55, 0.95, 2.3), Color = color }, CFrame.new(0, hubY + 1.75, -0.95) * CFrame.Angles(rad(-8), 0, 0))
	fixed(v, { Name = "Seat", Size = Vector3.new(1.25, 0.35, 2.5), Color = rgb(24, 24, 26) }, CFrame.new(0, seatTop - 0.18, 1.2))
	fixed(v, { Name = "Tail", Size = Vector3.new(1.15, 0.45, 1.5), Color = color }, CFrame.new(0, seatTop - 0.05, 2.85) * CFrame.Angles(rad(8), 0, 0))
	fixed(v, { Name = "FrontFender", Size = Vector3.new(0.7, 0.18, 1.7), Color = color }, CFrame.new(0, hubY + r + 0.25, -halfBase))
	bar(v, Vector3.new(0, hubY + 2.1, -2.3), Vector3.new(0, hubY + 0.45, 0.6), 0.45, DARK)
	bar(v, Vector3.new(0, hubY + 0.5, 0.8), Vector3.new(0, hubY, halfBase), 0.4, DARK)
	fixed(v, {
		Name = "Exhaust", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.8, 0.45, 0.45),
		Color = METAL, Material = Enum.Material.Metal,
	}, CFrame.new(0.72, hubY + 0.1, 1.9) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, rad(-6)))

	-- steering: fork, handlebar and headlight turn with the front wheel
	local steerBase = CFrame.new(0, hubY + 2.2, -2.45)
	local steer = newPart("Part", { Name = "SteerRig", Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1 })
	steer.CFrame = chassis.CFrame * steerBase
	steer.Parent = folder
	local steerWeld = Instance.new("Weld")
	steerWeld.Part0 = root
	steerWeld.Part1 = steer
	steerWeld.C0 = steerBase
	steerWeld.Parent = steer
	v.steerWeld, v.steerBase = steerWeld, steerBase
	local function onSteer(props, cf, className)
		local p = newPart(className, props)
		p.CFrame = chassis.CFrame * cf
		p.Parent = folder
		local w = Instance.new("WeldConstraint")
		w.Part0 = steer
		w.Part1 = p
		w.Parent = p
		return p
	end
	for _, x in { -0.5, 0.5 } do
		local a, b = Vector3.new(x, hubY + 2.3, -2.45), Vector3.new(x, hubY, -halfBase)
		onSteer({ Name = "Fork", Size = Vector3.new(0.3, 0.3, (b - a).Magnitude), Color = METAL, Material = Enum.Material.Metal }, CFrame.lookAt((a + b) * 0.5, b))
	end
	onSteer({
		Name = "Handlebar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.5, 0.25, 0.25),
		Color = DARK, Material = Enum.Material.Metal,
	}, CFrame.new(0, hubY + 2.75, -2.1))
	local lamp = onSteer({
		Name = "Headlight", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.35, 0.8, 0.8),
		Color = rgb(255, 250, 235), Material = Enum.Material.Neon,
	}, CFrame.new(0, hubY + 2.25, -2.85) * CFrame.Angles(0, math.pi / 2, 0))
	local spotHost = onSteer({ Name = "HeadlightBeam", Size = Vector3.new(0.3, 0.3, 0.3), Transparency = 1 }, CFrame.new(0, hubY + 2.25, -2.9))
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 58
	spot.Range = 80
	spot.Brightness = 4
	spot.Color = rgb(255, 244, 222)
	spot.Shadows = true
	spot.Parent = spotHost
	v.headlights = { spot }
	v.taillights = {
		fixed(v, { Name = "Taillight", Size = Vector3.new(0.7, 0.3, 0.12), Color = rgb(120, 16, 16) }, CFrame.new(0, seatTop, 3.62)),
	}
	local _ = lamp

	v.frontWheel = wheel(v, -halfBase, hubY, r, "FrontWheel")
	v.rearWheel = wheel(v, halfBase, hubY, r, "RearWheel")

	-- rider
	local rider = posedAvatar()
	if rider then
		rider.Parent = folder
		local hrp = rider:FindFirstChild("HumanoidRootPart")
		if hrp then
			rider.PrimaryPart = hrp
			rider:PivotTo(root.CFrame * CFrame.new(0, seatTop + 0.95, 1.15))
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
		blockyRider(v, seatTop, color)
	end
	v.seatTop = seatTop
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
	body.Name = "BikeBody"
	body.Parent = v.bikeParts
end

---------------------------------------------------------------------------
-- Per frame: lean, wheels, steering
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
	local r = cc.WheelRadius
	local front = (w[1].length + w[2].length) * 0.5
	local rear = (w[3].length + w[4].length) * 0.5
	local fw, rw = v.frontWheel, v.rearWheel
	fw.spin = (fw.spin + v.speed / r * dt) % (2 * math.pi)
	rw.spin = fw.spin
	fw.weld.C0 = CFrame.new(0, v.attachY - front + (fw.baseY or 0), fw.z) * CFrame.Angles(0, -v.steer, 0) * CFrame.Angles(-fw.spin, 0, 0)
	rw.weld.C0 = CFrame.new(0, v.attachY - rear + (rw.baseY or 0), rw.z) * CFrame.Angles(-rw.spin, 0, 0)
	v.steerWeld.C0 = v.steerBase * CFrame.Angles(0, -v.steer * 0.8, 0)
end

return Motorcycle
