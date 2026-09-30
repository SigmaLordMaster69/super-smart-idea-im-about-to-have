--[[
	Prop catalogue and inspection dump.

	Builds every procedural prop (each tree kind at every size, a few
	variants, all four seasons, near and far versions; bushes, flowers,
	rocks; every sign; delineator; road end) plus samples of road furniture
	cut out of real RoadBuilder output (straight and curved guard rail, a
	rail end, a bridge, tunnel portals and lights). Each item's parts are
	written to JSON for tools/render_props.py, which draws contact sheets.

	  lune run tools/render_props [out.json] [seed]   (default tools/scratch/props.json)
	  python3 tools/render_props.py out.json outdir/

	tools/test_props.luau uses the same catalogue (Catalog.collect) for its
	automated checks: it sets env.propCatalogAsLibrary before requiring this
	file, which then returns the catalogue instead of writing JSON.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local env = require("./env")

local roblox = env.roblox
local Instance, Vector3 = roblox.Instance, roblox.Vector3
local CFrame = env.CFrame

local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")
local Props = env.require("src/client/Props")
local RoadBuilder = env.require("src/client/RoadBuilder")

local Catalog = {}

Catalog.Seasons = { "Spring", "Summer", "Autumn", "Winter" }
Catalog.TreeKinds = { "pine", "snowpine", "oak", "birch", "cypress", "palm", "cactus" }

-- Wrap loose parts (or a Part prop) in a Model so every item looks the same.
local function asModel(obj)
	if obj:IsA("Model") then
		return obj
	end
	local m = Instance.new("Model")
	m.Name = obj.Name
	obj.Parent = m
	return m
end

---------------------------------------------------------------------------
-- Props
---------------------------------------------------------------------------
local function propItems(list)
	local props = Props.new(nil)

	for _, season in Catalog.Seasons do
		props:setSeason(season)
		local sheet = "trees_" .. string.lower(season)
		for _, kind in Catalog.TreeKinds do
			for size = 1, 3 do
				local v = size - 1
				table.insert(list, {
					name = string.format("%s s%d v%d", kind, size, v),
					sheet = sheet, row = kind, category = "tree", kind = kind, season = season,
					model = props:tree(kind, size, v, false),
				})
			end
			if kind == "oak" or kind == "birch" then
				table.insert(list, {
					name = kind .. " s2 v1 autumn-section",
					sheet = sheet, row = kind, category = "tree", kind = kind, season = season,
					model = props:tree(kind, 2, 1, false, true),
				})
			end
			for _, sv in { { 2, 0 }, { 3, 1 } } do
				table.insert(list, {
					name = string.format("%s far s%d", kind, sv[1]),
					sheet = sheet, row = kind, category = "far", kind = kind, season = season,
					model = props:tree(kind, sv[1], sv[2], true),
				})
			end
		end

		-- small plants
		local plants = "plants_" .. string.lower(season)
		for _, spec in { { "bush", 1, 0 }, { "bush", 2, 1 }, { "bush", 2, 2 }, { "drybush", 1, 0 }, { "drybush", 2, 1 }, { "flowers", 1, 0 }, { "flowers", 1, 1 }, { "flowers", 1, 2 } } do
			table.insert(list, {
				name = string.format("%s s%d v%d", spec[1], spec[2], spec[3]),
				sheet = plants, row = spec[1], category = "plant", kind = spec[1], season = season,
				model = props:tree(spec[1], spec[2], spec[3], false),
			})
		end
		table.insert(list, {
			name = "bush s2 v1 autumn-section",
			sheet = plants, row = "bush", category = "plant", kind = "bush", season = season,
			model = props:tree("bush", 2, 1, false, true),
		})
	end

	-- rocks
	local rng = env.Random.new(7)
	for _, style in { "default", "coast", "canyon", "snow" } do
		for _, size in { 2, 5, 8 } do
			table.insert(list, {
				name = string.format("rock %s %d", style, size),
				sheet = "rocks", row = style, category = "rock", kind = "rock",
				model = asModel(props:rock(style, size, rng)),
			})
		end
	end

	-- signs and road props
	props:setSeason("Summer")
	local signs = {
		{ "curve right", props:warningSign("CURVE\n\u{BB}", "CurveRight") },
		{ "curve left", props:warningSign("CURVE\n\u{AB}", "CurveLeft") },
		{ "falling rocks", props:warningSign("FALLING\nROCKS", "FallingRocks") },
		{ "deer crossing", props:warningSign("DEER\nCROSSING", "Deer") },
		{ "chevron right", props:chevron(true) },
		{ "chevron left", props:chevron(false) },
		{ "speed limit 60", props:speedLimit(60) },
		{ "speed limit 90", props:speedLimit(90) },
		{ "tunnel 420 m", props:tunnelSign("420 m") },
		{ "tunnel 1280 m", props:tunnelSign("1280 m") },
		{ "guide short", props:guideSign("Entering\nLake Serene") },
		{ "guide long", props:guideSign("Entering\nKingfisher River Valley") },
		{ "km 7", props:distanceMarker("7") },
		{ "km 128", props:distanceMarker("128") },
	}
	for _, s in signs do
		table.insert(list, { name = s[1], sheet = "signs", row = "signs", category = "sign", kind = s[1], model = s[2] })
	end
	table.insert(list, { name = "delineator", sheet = "signs", row = "road", category = "delineator", kind = "delineator", model = props:delineator() })
	table.insert(list, { name = "road end", sheet = "signs", row = "road", category = "roadend", kind = "roadend", model = props:roadEnd(Config.Road.HalfWidth * 2) })
end

---------------------------------------------------------------------------
-- Road furniture scenes, cut out of RoadBuilder output
---------------------------------------------------------------------------
local function sceneItems(list, seed)
	local world = World.new(Config, seed)
	local road = world.road
	local props = Props.new(nil)
	local builder = RoadBuilder.new(world, Config, props)
	local hw = Config.Road.HalfWidth
	local N = 9000
	road:ensureFlags(N + 200)

	local function find(pred, from)
		for k = from or 60, N do
			if pred(k) then
				return k
			end
		end
		return nil
	end
	local function railSide(k)
		return road:hasRail(k, 1) and 1 or (road:hasRail(k, -1) and -1 or nil)
	end
	local function maxCurv(k, r)
		local m = 0
		for j = k - r, k + r do
			m = math.max(m, math.abs(road.curv[j] or 0))
		end
		return m
	end

	-- builds samples a..b and keeps parts within `radius` studs of sample k,
	-- in the road frame at k (x right, y up, -z forward). The road beyond
	-- (8 more samples each way) is kept apart as context: the checks let it
	-- cover and hold up the scene's own parts, so cutting the scene out does
	-- not leave bare strip ends that the game never shows.
	local function scene(name, k, a, b, radius, views)
		local folder = Instance.new("Folder")
		-- far enough that every kept part (up to 32 studs long) has its
		-- neighbours in the context
		local margin = math.ceil((radius + 48) / Config.Road.SampleSpacing)
		builder:_buildRun(math.min(a, k - margin), math.max(b, k + margin), Vector3.zero, folder)
		local p, f = road:frameAtIndex(k)
		local flat = Vector3.new(f.X, 0, f.Z).Unit
		local frame = CFrame.lookAt(p, p + flat)
		local model = Instance.new("Model")
		model.Name = name
		local context = Instance.new("Folder")
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				local rel = frame:ToObjectSpace(d.CFrame)
				local reach = math.max(d.Size.X, d.Size.Y, d.Size.Z) / 2
				local owner = d:FindFirstAncestorWhichIsA("Model")
				local clone = d:Clone()
				clone.CFrame = rel
				if owner then
					clone:SetAttribute("Owner", owner.Name)
				end
				clone.Parent = rel.Position.Magnitude - reach < radius and model or context
			end
		end
		model.WorldPivot = CFrame.new()
		-- scenes off bridges get a ground plane just under the verge, standing
		-- in for the terrain (which hides buried posts and slab sides)
		local ground = not road:isBridge(k) and -0.4 or nil
		table.insert(list, { name = name, sheet = "road", row = name, category = "scene", kind = name, model = model, context = context, views = views, sample = k, ground = ground })
		return model
	end

	-- straight rail run, centred on a post
	local kS = find(function(k)
		return k % Config.GuardRail.PostSpacing == 0 and railSide(k) ~= nil and railSide(k - 6) == railSide(k)
			and railSide(k + 6) == railSide(k) and maxCurv(k, 8) < 1 / 900
	end)
	if kS then
		local s = railSide(kS)
		scene("rail straight", kS, kS - 6, kS + 6, 34, {
			{ eye = { s * (hw - 2.6), 3, 5 }, target = { s * (hw + 1.6), 1.5, -0.5 }, fov = 55 },
			{ eye = { s * (hw - 7), 5.5, 16 }, target = { s * (hw + 1.3), 1.6, -8 } },
			{ eye = { s * (hw + 9), 3.5, 7 }, target = { s * (hw + 1.5), 1.4, -1 } },
		})
	end
	-- curved rail run
	local kC = find(function(k)
		return railSide(k) ~= nil and railSide(k - 6) == railSide(k) and railSide(k + 6) == railSide(k) and math.abs(road.curv[k] or 0) > 1 / 260
	end)
	if kC then
		local s = railSide(kC)
		scene("rail curve", kC, kC - 8, kC + 8, 44, {
			{ eye = { s * (hw - 8), 6, 22 }, target = { s * (hw + 1.3), 1.6, -12 } },
			{ eye = { s * (hw + 16), 18, 4 }, target = { s * hw, 1, -6 } },
			{ eye = { s * (hw - 4), 30, 0 }, target = { s * (hw + 1), 0, -1 } },
		})
	end
	-- the start of a rail run (end treatment), away from bridges and tunnels
	local kE = find(function(k)
		local s = railSide(k)
		return s ~= nil and not road:hasRail(k - 1, s) and not road:isBridge(k - 1) and not road:isTunnel(k - 1)
			and road:hasRail(k + 8, s)
	end)
	if kE then
		local s = railSide(kE)
		scene("rail start", kE, kE - 5, kE + 6, 30, {
			{ eye = { s * (hw - 6), 5, 26 }, target = { s * (hw + 1.3), 1.2, -2 } },
			{ eye = { s * (hw + 9), 3.5, 12 }, target = { s * (hw + 1.5), 1, 0 } },
			{ eye = { s * (hw - 3), 20, 18 }, target = { s * (hw + 1.3), 0, 0 } },
		})
	end
	-- rail meeting a bridge parapet
	local kRB = find(function(k)
		return road:isBridge(k) and not road:isBridge(k - 1) and (road:hasRail(k - 1, 1) or road:hasRail(k - 1, -1))
	end)
	-- a bridge: abutment end, deck, parapets, girder and a pier
	local kB = find(function(k)
		return road:isBridge(k) and not road:isBridge(k - 1)
	end)
	if kB then
		local k = kRB or kB
		scene("bridge end", k, k - 5, k + 7, 40, {
			{ eye = { -hw + 4, 5, 22 }, target = { hw, 2, -8 } },
			{ eye = { hw + 26, -2, 18 }, target = { hw, -6, -6 } },
			{ eye = { hw + 20, 14, -10 }, target = { 0, 0, 6 } },
		})
	end
	local kP = find(function(k)
		return k % Config.Bridge.PierSpacing == 0 and road:isBridge(k - 3) and road:isBridge(k + 3)
	end)
	if kP then
		scene("bridge pier", kP, kP - 5, kP + 5, 60, {
			{ eye = { hw + 40, -6, 26 }, target = { 0, -14, 0 } },
			{ eye = { 4, 4, 18 }, target = { hw, 2.5, -10 } },
			{ eye = { 0, -30, 26 }, target = { 0, -10, 0 } },
		})
	end
	-- tunnel entry portal with its lining and lights
	local kT = find(function(k)
		return road:isTunnel(k) and not road:isTunnel(k - 1)
	end)
	if kT then
		scene("tunnel portal", kT, kT - 6, kT + 12, 62, {
			{ eye = { -6, 10, 60 }, target = { 0, 14, 0 } },
			{ eye = { 34, 30, 44 }, target = { 0, 12, -4 } },
			{ eye = { 4, 5, -6 }, target = { 0, 16, -40 }, fov = 80 },
		})
		local kX = find(function(k)
			return road:isTunnel(k) and not road:isTunnel(k + 1)
		end, kT)
		if kX then
			scene("tunnel exit", kX, kX - 12, kX + 4, 62, {
				{ eye = { 6, 10, -60 }, target = { 0, 14, 0 } },
				{ eye = { -8, 5, 26 }, target = { 0, 12, -10 }, fov = 80 },
			})
		end
	end
	return {
		straight = kS, curve = kC, railStart = kE, bridge = kB, railBridge = kRB, pier = kP, tunnel = kT,
	}
end

function Catalog.collect(seed: number?)
	local list = {}
	propItems(list)
	local found = sceneItems(list, seed or 12345)
	return list, found
end

---------------------------------------------------------------------------
-- JSON dump
---------------------------------------------------------------------------
local function round(x)
	return math.floor(x * 10000 + 0.5) / 10000
end

local function color(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end

local function texts(part)
	local out = {}
	for _, gui in part:GetChildren() do
		if gui:IsA("SurfaceGui") then
			local labels = {}
			for _, label in gui:GetDescendants() do
				if label:IsA("TextLabel") then
					local pad = label:FindFirstChildOfClass("UIPadding")
					table.insert(labels, {
						text = label.Text,
						color = color(label.TextColor3),
						pos = udim2(label.Position),
						size = udim2(label.Size),
						anchor = { label.AnchorPoint.X, label.AnchorPoint.Y },
						scaled = label.TextScaled,
						textSize = label.TextSize,
						pad = pad and { pad.PaddingLeft.Scale, pad.PaddingRight.Scale, pad.PaddingTop.Scale, pad.PaddingBottom.Scale } or { 0, 0, 0, 0 },
						bg = label.BackgroundTransparency < 1 and color(label.BackgroundColor3) or nil,
					})
				end
			end
			table.insert(out, { face = gui.Face.Name, ppu = gui.PixelsPerStud, labels = labels })
		end
	end
	return out
end

function Catalog.partRecord(d)
	local cf = d.CFrame
	local c = { cf:GetComponents() }
	for i, v in c do
		c[i] = round(v)
	end
	local rec = {
		n = d.Name,
		c = d.ClassName,
		s = d:IsA("Part") and d.Shape.Name or d.ClassName,
		z = { round(d.Size.X), round(d.Size.Y), round(d.Size.Z) },
		f = c,
		col = color(d.Color),
		m = d.Material.Name,
		t = d.Transparency,
		r = d.Reflectance,
	}
	local tx = texts(d)
	if #tx > 0 then
		rec.tx = tx
	end
	return rec
end

function Catalog.parts(model)
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

if env.propCatalogAsLibrary then
	return Catalog
end

local out = process.args[1] or "tools/scratch/props.json"
local seed = tonumber(process.args[2]) or 12345
local list, found = Catalog.collect(seed)
local items = {}
local total = 0
for _, item in list do
	local parts = {}
	for _, d in Catalog.parts(item.model) do
		table.insert(parts, Catalog.partRecord(d))
	end
	total += #parts
	table.insert(items, {
		name = item.name,
		sheet = item.sheet,
		row = item.row,
		category = item.category,
		season = item.season,
		views = item.views,
		ground = item.ground,
		parts = parts,
	})
end
fs.writeFile(out, serde.encode("json", { items = items, halfWidth = Config.Road.HalfWidth }))
local keys = {}
for k, v in found do
	table.insert(keys, k .. "=" .. tostring(v))
end
table.sort(keys)
print(string.format("wrote %d items (%d parts) to %s; scene samples: %s", #items, total, out, table.concat(keys, " ")))
return Catalog
