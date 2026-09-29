--[[
	AssetLibrary
	------------
	Lets premade models (from the Toolbox / Creator Store asset packs) replace
	the part-built props. Drop models into folders under

	  ReplicatedStorage.InfiniteRoadAssets
	    Trees/Pine  Trees/SnowPine  Trees/Oak  Trees/OakAutumn  Trees/Birch
	    Trees/BirchAutumn  Trees/Cypress  Trees/Cactus
	    Plants/Bush  Plants/DryBush  Plants/Flowers
	    Rocks
	    Signs/CurveLeft  Signs/CurveRight  Signs/ChevronLeft  Signs/ChevronRight
	    Signs/Tunnel  Signs/SpeedLimit  Signs/FallingRocks  Signs/Deer
	    Signs/Guide  Signs/Marker
	    Road/GuardRail  Road/Delineator  Road/RoadEnd
	    Car/Body  Motorcycle/Body

	Several models in one folder become random variants. Empty folders keep
	using the built-in procedural version.

	Every model is cleaned before use: scripts, sounds, seats, humanoids,
	joints and constraints are removed (free models often carry scripts you
	do not want running), parts are anchored and made non-queryable, the
	pivot is moved to the bottom centre, and the model is scaled to a size
	that fits the game.

	Optional attributes, set on a model or on its folder:
	  KeepSize (bool)       use the model's own size, no auto-scaling
	  Scale (number)        extra scale factor applied after auto-scaling
	  YawOffset (number)    degrees to turn the model so it faces the right way
	                        (props and signs should face -Z, cars point -Z)
	  HeightOffset (number) studs to raise (+) or sink (-) the model
	  Collide (bool)        whether the model blocks the car
]]

local AssetLibrary = {}
AssetLibrary.__index = AssetLibrary

local huge, min, max, rad = math.huge, math.min, math.max, math.rad

-- kind -> folder path, target size per size class, how to measure, collide
local KINDS = {
	pine = { path = "Trees/Pine", sizes = { 26, 36, 48 } },
	snowpine = { path = "Trees/SnowPine", sizes = { 26, 36, 48 } },
	oak = { path = "Trees/Oak", sizes = { 20, 28, 36 } },
	oak_autumn = { path = "Trees/OakAutumn", sizes = { 20, 28, 36 } },
	birch = { path = "Trees/Birch", sizes = { 18, 24, 30 } },
	birch_autumn = { path = "Trees/BirchAutumn", sizes = { 18, 24, 30 } },
	cypress = { path = "Trees/Cypress", sizes = { 16, 21, 27 } },
	cactus = { path = "Trees/Cactus", sizes = { 9, 12, 16 } },
	bush = { path = "Plants/Bush", sizes = { 4, 5.5, 7 } },
	drybush = { path = "Plants/DryBush", sizes = { 3, 4, 5 } },
	flowers = { path = "Plants/Flowers", sizes = { 1.2, 1.5, 1.8 } },
	rock = { path = "Rocks", sizes = { 2.5, 4.5, 8 }, measure = "max", collide = true },

	CurveLeft = { path = "Signs/CurveLeft", sizes = { 9 }, sign = true },
	CurveRight = { path = "Signs/CurveRight", sizes = { 9 }, sign = true },
	ChevronLeft = { path = "Signs/ChevronLeft", sizes = { 6.5 }, sign = true },
	ChevronRight = { path = "Signs/ChevronRight", sizes = { 6.5 }, sign = true },
	Tunnel = { path = "Signs/Tunnel", sizes = { 8 }, sign = true },
	SpeedLimit = { path = "Signs/SpeedLimit", sizes = { 8 }, sign = true },
	FallingRocks = { path = "Signs/FallingRocks", sizes = { 9 }, sign = true },
	Deer = { path = "Signs/Deer", sizes = { 9 }, sign = true },
	Guide = { path = "Signs/Guide", sizes = { 11 }, sign = true },
	Marker = { path = "Signs/Marker", sizes = { 4 }, sign = true },
	Delineator = { path = "Road/Delineator", sizes = { 3.6 }, sign = true },
	RoadEnd = { path = "Road/RoadEnd", sizes = { 6 }, sign = true, collide = true },
}
AssetLibrary.Kinds = KINDS

local function isStripped(d: Instance): boolean
	return d:IsA("LuaSourceContainer")
		or d:IsA("Humanoid")
		or d:IsA("Seat")
		or d:IsA("VehicleSeat")
		or d:IsA("ClickDetector")
		or d:IsA("ProximityPrompt")
		or d:IsA("Sound")
		or d:IsA("Constraint")
		or d:IsA("JointInstance")
		or d:IsA("WeldConstraint")
		or d:IsA("NoCollisionConstraint")
		or d:IsA("BodyMover")
		or d:IsA("Tool")
		or d:IsA("ForceField")
		or d:IsA("Explosion")
end

-- Remove everything that should not come along with a prop.
function AssetLibrary.sanitize(root: Instance)
	for _, d in root:GetDescendants() do
		if d.Parent and isStripped(d) then
			d:Destroy()
		end
	end
end

-- World-axis bounds of the visible parts of a model.
function AssetLibrary.bounds(model: Instance): (Vector3, Vector3)
	return AssetLibrary.boundsOf(model:GetDescendants())
end

-- World-axis bounds of the visible parts in a list of instances.
function AssetLibrary.boundsOf(list): (Vector3, Vector3)
	local lx, ly, lz, hx, hy, hz = huge, huge, huge, -huge, -huge, -huge
	local any = false
	for _, p in list do
		if p:IsA("BasePart") and p.Transparency < 0.99 then
			any = true
			local cf, s = p.CFrame, p.Size * 0.5
			for _, c in { -1, 1 } do
				for _, d in { -1, 1 } do
					for _, e in { -1, 1 } do
						local w = cf:PointToWorldSpace(Vector3.new(s.X * c, s.Y * d, s.Z * e))
						lx, ly, lz = min(lx, w.X), min(ly, w.Y), min(lz, w.Z)
						hx, hy, hz = max(hx, w.X), max(hy, w.Y), max(hz, w.Z)
					end
				end
			end
		end
	end
	if not any then
		return Vector3.zero, Vector3.zero
	end
	return Vector3.new(lx, ly, lz), Vector3.new(hx, hy, hz)
end

-- Put the pivot at the bottom centre of the model and move it to the origin.
function AssetLibrary.recenter(model: Model): Vector3
	local lo, hi = AssetLibrary.bounds(model)
	model.WorldPivot = CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2)
	model:PivotTo(CFrame.new())
	return hi - lo
end

local function attribute(source: Instance, folder: Instance?, name: string)
	local v = source:GetAttribute(name)
	if v == nil and folder then
		v = folder:GetAttribute(name)
	end
	return v
end
AssetLibrary.attribute = attribute

-- Clone, clean, orient and centre one source object. Returns the model and
-- its size, or nil if it has nothing visible.
function AssetLibrary.prepare(source: Instance, folder: Instance?, collideDefault: boolean?)
	local m
	if source:IsA("Model") then
		m = source:Clone()
	elseif source:IsA("BasePart") then
		m = Instance.new("Model")
		m.Name = source.Name
		source:Clone().Parent = m
	else
		return nil
	end
	AssetLibrary.sanitize(m)
	local collide = attribute(source, folder, "Collide")
	if collide == nil then
		collide = collideDefault == true
	end
	local count = 0
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanTouch = false
			p.CanQuery = false
			p.CanCollide = collide and p.Transparency < 0.99 and p.CanCollide
			count += 1
		end
	end
	if count == 0 then
		m:Destroy()
		return nil
	end
	if m.PrimaryPart then
		m.PrimaryPart = nil -- pivot from WorldPivot, which recenter sets
	end
	local size = AssetLibrary.recenter(m)
	if size.Magnitude < 0.01 then
		m:Destroy()
		return nil
	end
	local yaw = attribute(source, folder, "YawOffset")
	if yaw and yaw ~= 0 then
		m:PivotTo(CFrame.Angles(0, rad(yaw), 0))
		size = AssetLibrary.recenter(m)
	end
	return m, size, count
end

local function findFolder(root: Instance, path: string): Instance?
	local node = root
	for name in string.gmatch(path, "[^/]+") do
		node = node:FindFirstChild(name)
		if not node then
			return nil
		end
	end
	return node
end

function AssetLibrary.new(root: Instance?)
	local self = setmetatable({}, AssetLibrary)
	self.sets = {}
	self.partCounts = {}
	self.summary = {}
	if not root then
		return self
	end
	for kind, spec in KINDS do
		local folder = findFolder(root, spec.path)
		if folder then
			self:_loadKind(kind, spec, folder)
		end
	end
	local rail = findFolder(root, "Road/GuardRail")
	if rail then
		self:_loadRail(rail)
	end
	for _, slot in { { "Car/Body", "car" }, { "Motorcycle/Body", "bike" } } do
		local f = findFolder(root, slot[1])
		if f then
			for _, child in f:GetChildren() do
				if child:IsA("Model") or child:IsA("BasePart") then
					self[slot[2] .. "Source"] = child
					self[slot[2] .. "Folder"] = f
					table.insert(self.summary, slot[1])
					break
				end
			end
		end
	end
	return self
end

function AssetLibrary:_loadKind(kind: string, spec, folder: Instance)
	local set = {}
	for i = 1, #spec.sizes do
		set[i] = {}
	end
	local most = 0
	for _, child in folder:GetChildren() do
		local m, size, count = AssetLibrary.prepare(child, folder, spec.collide)
		if m then
			most = max(most, count)
			local measure = spec.measure == "max" and max(size.X, size.Y, size.Z) or size.Y
			local keep = attribute(child, folder, "KeepSize") == true
			local extra = attribute(child, folder, "Scale") or 1
			local lift = attribute(child, folder, "HeightOffset") or 0
			for i, target in spec.sizes do
				local t = i == #spec.sizes and m or m:Clone()
				local factor = extra
				if not keep and measure > 0 then
					local f = target / measure
					-- signs are usually modelled at a sensible size already
					if not spec.sign or f < 0.6 or f > 1.6 then
						factor *= f
					end
				end
				if factor ~= 1 then
					t:ScaleTo(t:GetScale() * factor)
				end
				if lift ~= 0 then
					t.WorldPivot = CFrame.new(0, -lift, 0)
				end
				table.insert(set[i], t)
			end
		end
	end
	if #set[1] > 0 then
		self.sets[kind] = set
		self.partCounts[kind] = most
		table.insert(self.summary, string.format("%s x%d", spec.path, #set[1]))
	end
end

-- Guard rail segments are laid end to end, so their length matters and they
-- keep their own size unless told otherwise.
function AssetLibrary:_loadRail(folder: Instance)
	for _, child in folder:GetChildren() do
		local m, size = AssetLibrary.prepare(child, folder, false)
		if m then
			if size.X > size.Z then
				m:PivotTo(CFrame.Angles(0, math.pi / 2, 0))
				size = AssetLibrary.recenter(m)
			end
			local extra = attribute(child, folder, "Scale") or 1
			if extra ~= 1 then
				m:ScaleTo(m:GetScale() * extra)
				size *= extra
			end
			self.rail = { template = m, length = size.Z, height = size.Y }
			table.insert(self.summary, string.format("Road/GuardRail (%.1f stud segments)", size.Z))
			return
		end
	end
end

function AssetLibrary:has(kind: string): boolean
	return self.sets[kind] ~= nil
end

-- Part count of the heaviest model of a kind (used to decide whether it is
-- cheap enough for distant chunks).
function AssetLibrary:partCount(kind: string): number
	return self.partCounts[kind] or 0
end

-- A fresh clone of a variant, or nil if the kind has no assets.
function AssetLibrary:pick(kind: string, sizeClass: number, variant: number): Model?
	local set = self.sets[kind]
	if not set then
		return nil
	end
	local list = set[math.clamp(sizeClass, 1, #set)]
	return list[variant % #list + 1]:Clone()
end

-- Put `text` into the sign's own TextLabel, if it has one.
function AssetLibrary.setText(model: Instance, text: string): boolean
	local best
	for _, d in model:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextBox") then
			if not best or d.Name == "Text" or d.Name == "Label" then
				best = d
			end
		end
	end
	if best then
		best.Text = text
		return true
	end
	return false
end

return AssetLibrary
