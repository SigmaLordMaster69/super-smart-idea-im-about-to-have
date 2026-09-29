--[[
	Props
	-----
	Everything placed next to the road, built from plain parts so the game
	needs no uploaded assets: trees, bushes, cacti, rocks, flowers, road
	signs, delineator posts and barriers.

	Trees are built once as templates and then cloned. Every template is a
	Model whose pivot is the point where it meets the ground, so placing one
	is just `clone:PivotTo(CFrame.new(groundPoint) * yaw)`.

	Each tree kind also has a one-part "far" version used by distant chunks.

	If an AssetLibrary is given, premade models dropped into
	ReplicatedStorage.InfiniteRoadAssets replace the procedural ones kind by
	kind (see AssetLibrary.luau).
]]

local AssetLibrary = require(script.Parent.AssetLibrary)

local Props = {}
Props.__index = Props

local rgb = Color3.fromRGB

local BARK = rgb(96, 70, 50)
local PINE_GREENS = { rgb(46, 86, 52), rgb(56, 98, 58), rgb(40, 76, 50) }
local FROST = rgb(184, 204, 196)
local OAK_GREENS = { rgb(86, 140, 60), rgb(104, 150, 58), rgb(72, 124, 56) }
local AUTUMN = { rgb(214, 122, 40), rgb(184, 62, 40), rgb(226, 180, 62), rgb(160, 96, 44) }
local BIRCH_LEAF = rgb(146, 184, 74)
local CYPRESS = rgb(58, 88, 56)
local CACTUS = rgb(88, 128, 70)
local FLOWERS = { rgb(240, 90, 110), rgb(250, 220, 70), rgb(240, 240, 250), rgb(170, 120, 230), rgb(250, 150, 60) }
local BLOSSOM = { rgb(244, 190, 212), rgb(250, 232, 240), rgb(236, 170, 198) }
local SPRING_GREEN = rgb(128, 184, 74)
local BARE_BARK = rgb(88, 70, 58)

local SIGN_YELLOW = rgb(244, 196, 40)
local SIGN_GREEN = rgb(30, 110, 64)
local SIGN_BLUE = rgb(30, 80, 160)
local SIGN_WHITE = rgb(242, 242, 238)
local INK = rgb(20, 20, 22)
local POST = rgb(150, 152, 156)

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's X axis up

local function newPart(className: string?, props)
	local p = Instance.new(className or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	return p
end
Props.newPart = newPart

-- vertical cylinder whose base sits at height y0
local function cylinder(model, y0: number, height: number, diameter: number, color: Color3, material, offset: Vector3?, collide: boolean?)
	local o = offset or Vector3.zero
	local p = newPart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(o.X, y0 + height / 2, o.Z) * VERTICAL,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = collide == true,
	})
	p.Parent = model
	return p
end

local function ball(model, center: Vector3, diameter: number, color: Color3)
	local p = newPart("Part", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = CFrame.new(center),
		Color = color,
	})
	p.Parent = model
	return p
end

local function finish(model: Model, name: string)
	model.Name = name
	model.WorldPivot = CFrame.new()
	return model
end

---------------------------------------------------------------------------
-- Tree builders (sc = scale)
---------------------------------------------------------------------------
local BUILDERS = {}

function BUILDERS.pine(sc, variant, far, style)
	local m = Instance.new("Model")
	local green = PINE_GREENS[variant % #PINE_GREENS + 1]
	if far then
		cylinder(m, 5 * sc, 20 * sc, 10 * sc, green)
		return finish(m, "PineFar")
	end
	cylinder(m, -1.5, 11 * sc + 1.5, 1.9 * sc, BARK, Enum.Material.Wood, nil, true)
	for i = 1, 3 do
		local y = (5 + (i - 1) * 5.6) * sc
		local d = (15.5 - (i - 1) * 4.6) * sc
		cylinder(m, y, 6.6 * sc, d, green:Lerp(Color3.new(), (i - 1) * 0.06))
	end
	cylinder(m, 21.5 * sc, 4.5 * sc, 2.4 * sc, green)
	return finish(m, "Pine")
end

function BUILDERS.snowpine(sc, variant, far, style)
	local m = Instance.new("Model")
	if far then
		cylinder(m, 5 * sc, 20 * sc, 10 * sc, FROST)
		return finish(m, "SnowPineFar")
	end
	cylinder(m, -1.5, 11 * sc + 1.5, 1.9 * sc, BARK, Enum.Material.Wood, nil, true)
	for i = 1, 3 do
		local y = (5 + (i - 1) * 5.6) * sc
		local d = (15.5 - (i - 1) * 4.6) * sc
		cylinder(m, y, 6.6 * sc, d, PINE_GREENS[1]:Lerp(FROST, 0.45 + i * 0.12))
	end
	cylinder(m, 21.5 * sc, 4.5 * sc, 2.4 * sc, FROST)
	return finish(m, "SnowPine")
end

local function oakColor(variant, style)
	if style.autumn then
		return AUTUMN[variant % #AUTUMN + 1]
	elseif style.blossom and variant % 3 == 0 then
		return BLOSSOM[variant % #BLOSSOM + 1]
	elseif style.blossom then
		return SPRING_GREEN:Lerp(OAK_GREENS[variant % #OAK_GREENS + 1], 0.4)
	end
	return OAK_GREENS[variant % #OAK_GREENS + 1]
end

-- winter: a trunk with a few bare branches
local function bareTree(m, sc, trunkH, trunkD, bark)
	cylinder(m, -1.5, trunkH * sc + 1.5, trunkD * sc, bark, Enum.Material.Wood, nil, true)
	for i, a in { 0, 2.1, 4.2 } do
		local y = (trunkH * (0.55 + i * 0.12)) * sc
		local len = (5 - i) * sc
		local p = newPart("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(len, trunkD * 0.4 * sc, trunkD * 0.4 * sc),
			CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.rad(40)) * CFrame.new(len / 2, 0, 0),
			Color = bark,
			Material = Enum.Material.Wood,
		})
		p.Parent = m
	end
end

function BUILDERS.oak(sc, variant, far, style)
	local m = Instance.new("Model")
	if style.bare then
		if far then
			cylinder(m, 0, 11 * sc, 1.6 * sc, BARE_BARK)
			return finish(m, "OakFar")
		end
		bareTree(m, sc, 11, 2.1, BARE_BARK)
		return finish(m, "Oak")
	end
	local leaf = oakColor(variant, style)
	if far then
		ball(m, Vector3.new(0, 13 * sc, 0), 15 * sc, leaf)
		return finish(m, "OakFar")
	end
	cylinder(m, -1.5, 10 * sc + 1.5, 2.1 * sc, BARK, Enum.Material.Wood, nil, true)
	ball(m, Vector3.new(0, 14 * sc, 0), 14 * sc, leaf)
	ball(m, Vector3.new(4.2 * sc, 11.5 * sc, 1.8 * sc), 9 * sc, leaf:Lerp(Color3.new(1, 1, 1), 0.06))
	ball(m, Vector3.new(-3.8 * sc, 12 * sc, -2.4 * sc), 9.5 * sc, leaf:Lerp(Color3.new(), 0.08))
	return finish(m, "Oak")
end

function BUILDERS.birch(sc, variant, far, style)
	local m = Instance.new("Model")
	local bark = rgb(232, 230, 222)
	if style.bare then
		if far then
			cylinder(m, 0, 15 * sc, 1.2 * sc, bark)
			return finish(m, "BirchFar")
		end
		bareTree(m, sc, 15, 1.3, bark)
		return finish(m, "Birch")
	end
	local leaf = (style.autumn and AUTUMN[3]) or (style.blossom and BLOSSOM[2]:Lerp(BIRCH_LEAF, variant % 2 == 0 and 1 or 0)) or BIRCH_LEAF
	if far then
		ball(m, Vector3.new(0, 14 * sc, 0), 9 * sc, leaf)
		return finish(m, "BirchFar")
	end
	cylinder(m, -1.5, 15 * sc + 1.5, 1.3 * sc, bark, Enum.Material.SmoothPlastic, nil, true)
	ball(m, Vector3.new(0.6 * sc, 13 * sc, 0), 7.5 * sc, leaf)
	ball(m, Vector3.new(-0.5 * sc, 16.5 * sc, 0.4 * sc), 6 * sc, leaf:Lerp(Color3.new(1, 1, 1), 0.08))
	return finish(m, "Birch")
end

-- wind-swept coastal tree with a flat top
function BUILDERS.cypress(sc, variant, far, style)
	local m = Instance.new("Model")
	local CYPRESS = style.frost and CYPRESS:Lerp(FROST, 0.45) or CYPRESS
	if far then
		cylinder(m, 9 * sc, 4 * sc, 15 * sc, CYPRESS, nil, Vector3.new(2 * sc, 0, 0))
		return finish(m, "CypressFar")
	end
	cylinder(m, -1.5, 10 * sc + 1.5, 1.7 * sc, BARK, Enum.Material.Wood, nil, true)
	cylinder(m, 9 * sc, 3.6 * sc, 16 * sc, CYPRESS, nil, Vector3.new(2.5 * sc, 0, 0.5 * sc))
	cylinder(m, 12 * sc, 3 * sc, 10 * sc, CYPRESS:Lerp(Color3.new(), 0.08), nil, Vector3.new(-0.8 * sc, 0, -0.6 * sc))
	return finish(m, "Cypress")
end

function BUILDERS.cactus(sc, variant, far, style)
	local m = Instance.new("Model")
	if far then
		cylinder(m, 0, 11 * sc, 2 * sc, CACTUS)
		return finish(m, "CactusFar")
	end
	local d = 1.9 * sc
	cylinder(m, -1, 11 * sc + 1, d, CACTUS, nil, nil, true)
	ball(m, Vector3.new(0, 11 * sc, 0), d, CACTUS)
	local side = variant % 2 == 0 and 1 or -1
	-- two arms, each an elbow of a short horizontal and a vertical piece
	for arm = 0, 1 do
		local s = arm == 0 and side or -side
		local y = (4.5 + arm * 2.2) * sc
		local p = newPart("Part", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(2.6 * sc, d * 0.8, d * 0.8),
			CFrame = CFrame.new(s * 1.3 * sc, y, 0),
			Color = CACTUS,
		})
		p.Parent = m
		cylinder(m, y - 0.3 * sc, (3.4 - arm) * sc, d * 0.8, CACTUS, nil, Vector3.new(s * 2.5 * sc, 0, 0))
	end
	return finish(m, "Cactus")
end

function BUILDERS.bush(sc, variant, far, style)
	local m = Instance.new("Model")
	if style.bare then
		ball(m, Vector3.new(0, 1.1 * sc, 0), 3.4 * sc, rgb(118, 96, 74))
		return finish(m, "Bush")
	end
	local leaf = oakColor(variant + 1, { autumn = style.autumn }):Lerp(Color3.new(), 0.1)
	ball(m, Vector3.new(0, 1.4 * sc, 0), 4.6 * sc, leaf)
	ball(m, Vector3.new(1.6 * sc, 1 * sc, 0.8 * sc), 3.2 * sc, leaf)
	return finish(m, "Bush")
end

function BUILDERS.drybush(sc, variant, far, style)
	local m = Instance.new("Model")
	ball(m, Vector3.new(0, 0.9 * sc, 0), 3.2 * sc, rgb(138, 128, 74):Lerp(rgb(110, 100, 60), (variant % 3) / 3))
	return finish(m, "DryBush")
end

function BUILDERS.flowers(sc, variant, far, style)
	local m = Instance.new("Model")
	local rng = Random.new(variant * 17 + 3)
	local color = FLOWERS[variant % #FLOWERS + 1]
	for _ = 1, 4 do
		local x, z = rng:NextNumber(-2.5, 2.5), rng:NextNumber(-2.5, 2.5)
		local p = ball(m, Vector3.new(x, 0.55, z), rng:NextNumber(0.6, 1.0), color)
		p.CastShadow = false
	end
	return finish(m, "Flowers")
end

---------------------------------------------------------------------------
-- Template cache
---------------------------------------------------------------------------
-- Seasonal looks for the procedural trees.
Props.SeasonStyles = {
	Spring = { blossom = true },
	Summer = {},
	Autumn = { autumn = true },
	Winter = { bare = true, frost = true },
}

function Props.new(assets)
	local self = setmetatable({}, Props)
	self.templates = {}
	self.assets = assets
	self.season = "Summer"
	self.treeShadows = true
	return self
end

function Props:setSeason(name: string)
	self.season = Props.SeasonStyles[name] and name or "Summer"
end

function Props:setShadows(on: boolean)
	self.treeShadows = on
end

-- A premade model for `kind` if the asset packs provide one.
function Props:_asset(kind: string, sizeClass: number, variant: number): Model?
	local assets = self.assets
	if assets and assets:has(kind) then
		return assets:pick(kind, sizeClass, variant)
	end
	return nil
end

-- Returns a fresh clone of a tree/plant template.
-- kind: pine, snowpine, oak, birch, cypress, cactus, bush, drybush, flowers
-- size: 1..3, variant: any integer, far: one-part version
function Props:tree(kind: string, size: number, variant: number, far: boolean, autumn: boolean?)
	local assets = self.assets
	if assets then
		local key = kind
		if autumn and assets:has(kind .. "_autumn") then
			key = kind .. "_autumn"
		elseif kind == "snowpine" and not assets:has("snowpine") then
			key = "pine"
		end
		-- heavy asset trees fall back to the one-part stand-in far away
		if assets:has(key) and (not far or assets:partCount(key) <= 4) then
			return assets:pick(key, size, variant)
		end
	end
	local v = variant % 3
	local shadows = self.treeShadows and not far
	local key = string.format("%s/%d/%d/%s/%s/%s/%s", kind, size, v, far and "f" or "n", autumn and "a" or "g", self.season, shadows and "s" or "-")
	local t = self.templates[key]
	if not t then
		local scale = ({ 0.95, 1.3, 1.75 })[size]
		local style = Props.SeasonStyles[self.season]
		if autumn and not style.bare then
			style = table.clone(style)
			style.autumn = true
			style.blossom = nil
		end
		t = BUILDERS[kind](scale, v, far, style)
		if not shadows then
			for _, p in t:GetDescendants() do
				if p:IsA("BasePart") then
					p.CastShadow = false
				end
			end
		end
		self.templates[key] = t
	end
	return t:Clone()
end

local ROCK_STYLE = {
	default = { Enum.Material.Rock, rgb(128, 124, 118) },
	coast = { Enum.Material.Basalt, rgb(70, 68, 70) },
	canyon = { Enum.Material.Sandstone, rgb(176, 96, 62) },
	snow = { Enum.Material.Rock, rgb(150, 150, 152) },
}

-- Returns a Part (procedural) or a Model (asset); place it with Props.place.
function Props:rock(style: string, size: number, rng)
	local asset = self:_asset("rock", size < 3 and 1 or (size < 6 and 2 or 3), rng:NextInteger(0, 999))
	if asset then
		return asset
	end
	local s = ROCK_STYLE[style] or ROCK_STYLE.default
	return newPart("Part", {
		Name = "Rock",
		Size = Vector3.new(size * rng:NextNumber(0.8, 1.4), size * rng:NextNumber(0.5, 0.9), size * rng:NextNumber(0.8, 1.3)),
		Material = s[1],
		Color = s[2]:Lerp(Color3.new(), rng:NextNumber(0, 0.15)),
		CanCollide = size > 3,
	})
end

-- Move a Part or Model to `cf`.
function Props.place(obj: Instance, cf: CFrame)
	if obj:IsA("Model") then
		obj:PivotTo(cf)
	else
		(obj :: BasePart).CFrame = cf
	end
end

---------------------------------------------------------------------------
-- Signs. Every sign model faces -Z (its LookVector); place it with
-- CFrame.lookAt(base, base - roadForward) so it faces oncoming drivers.
---------------------------------------------------------------------------
local function addText(target: BasePart, text: string, color: Color3, face)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.MaxDistance = 450
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.07, 0)
	pad.PaddingRight = UDim.new(0.07, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = target
	return label
end

local function post(model, height: number, x: number?)
	return newPart("Part", {
		Name = "Post",
		Size = Vector3.new(0.35, height + 1.5, 0.35),
		CFrame = CFrame.new(x or 0, (height - 1.5) / 2, 0.15),
		Color = POST,
		Material = Enum.Material.Metal,
		CanCollide = true,
		Parent = model,
	})
end

-- Yellow diamond warning sign with a text symbol. `kind` names the asset
-- slot that can replace it (CurveLeft, CurveRight, FallingRocks, Deer).
function Props:warningSign(text: string, kind: string?): Model
	local asset = kind and self:_asset(kind, 1, 0)
	if asset then
		return asset
	end
	local m = Instance.new("Model")
	post(m, 7.5)
	local center = Vector3.new(0, 7.5, 0)
	newPart("Part", {
		Name = "Border",
		Size = Vector3.new(3.75, 3.75, 0.12),
		CFrame = CFrame.new(center + Vector3.new(0, 0, 0.04)) * CFrame.Angles(0, 0, math.rad(45)),
		Color = INK,
		Parent = m,
	})
	newPart("Part", {
		Name = "Board",
		Size = Vector3.new(3.45, 3.45, 0.12),
		CFrame = CFrame.new(center - Vector3.new(0, 0, 0.02)) * CFrame.Angles(0, 0, math.rad(45)),
		Color = SIGN_YELLOW,
		Parent = m,
	})
	local label = newPart("Part", {
		Name = "Label",
		Size = Vector3.new(3.2, 2.6, 0.05),
		CFrame = CFrame.new(center - Vector3.new(0, 0, 0.12)),
		Transparency = 1,
		Parent = m,
	})
	addText(label, text, INK)
	return finish(m, "WarningSign")
end

-- Rectangular yellow/black chevron board for sharp curves.
function Props:chevron(pointRight: boolean): Model
	local asset = self:_asset(pointRight and "ChevronRight" or "ChevronLeft", 1, 0)
	if asset then
		return asset
	end
	local key = pointRight and "chevronR" or "chevronL"
	local t = self.templates[key]
	if not t then
		t = Instance.new("Model")
		post(t, 5.2)
		local board = newPart("Part", {
			Name = "Board",
			Size = Vector3.new(2.4, 3, 0.12),
			CFrame = CFrame.new(0, 5.2, 0),
			Color = SIGN_YELLOW,
			Parent = t,
		})
		addText(board, pointRight and ">" or "<", INK)
		finish(t, "Chevron")
		self.templates[key] = t
	end
	return t:Clone()
end

-- Generic rectangular sign on one or two posts.
function Props:panel(text: string, width: number, height: number, bg: Color3, fg: Color3, bottom: number?): Model
	local m = Instance.new("Model")
	local base = bottom or 5
	local top = base + height
	if width > 6 then
		post(m, top - 0.5, -width * 0.32)
		post(m, top - 0.5, width * 0.32)
	else
		post(m, top - 0.5)
	end
	newPart("Part", {
		Name = "Frame",
		Size = Vector3.new(width + 0.3, height + 0.3, 0.12),
		CFrame = CFrame.new(0, base + height / 2, 0.04),
		Color = fg,
		Parent = m,
	})
	local board = newPart("Part", {
		Name = "Board",
		Size = Vector3.new(width, height, 0.12),
		CFrame = CFrame.new(0, base + height / 2, -0.02),
		Color = bg,
		Parent = m,
	})
	addText(board, text, fg)
	return finish(m, "Sign")
end

-- Asset sign with its text swapped in (if it has a TextLabel).
function Props:_textSign(kind: string, text: string): Model?
	local asset = self:_asset(kind, 1, 0)
	if asset then
		AssetLibrary.setText(asset, text)
	end
	return asset
end

function Props:speedLimit(limit: number): Model
	return self:_textSign("SpeedLimit", tostring(limit)) or self:panel("SPEED\nLIMIT\n" .. limit, 3.2, 4, SIGN_WHITE, INK, 4)
end

function Props:guideSign(text: string): Model
	return self:_textSign("Guide", text) or self:panel(text, 13, 5, SIGN_GREEN, SIGN_WHITE, 6)
end

function Props:tunnelSign(lengthText: string): Model
	return self:_textSign("Tunnel", lengthText) or self:panel("TUNNEL\n" .. lengthText, 4.4, 3.4, SIGN_BLUE, SIGN_WHITE, 4.5)
end

function Props:distanceMarker(text: string): Model
	return self:_textSign("Marker", text) or self:panel(text, 1.6, 1.3, SIGN_GREEN, SIGN_WHITE, 2.4)
end

-- White roadside post with an amber reflector.
function Props:delineator(): Model
	local asset = self:_asset("Delineator", 1, 0)
	if asset then
		return asset
	end
	local t = self.templates.delineator
	if not t then
		t = Instance.new("Model")
		newPart("Part", {
			Name = "Post",
			Size = Vector3.new(0.4, 3.6, 0.4),
			CFrame = CFrame.new(0, 1.3, 0),
			Color = SIGN_WHITE,
			CastShadow = false,
			Parent = t,
		})
		newPart("Part", {
			Name = "Reflector",
			Size = Vector3.new(0.25, 0.35, 0.05),
			CFrame = CFrame.new(0, 2.5, -0.22),
			Color = rgb(255, 170, 40),
			Material = Enum.Material.Neon,
			CastShadow = false,
			Parent = t,
		})
		finish(t, "Delineator")
		self.templates.delineator = t
	end
	return t:Clone()
end

-- Red/white barrier across the road where it begins.
function Props:roadEnd(width: number): Model
	local asset = self:_asset("RoadEnd", 1, 0)
	if asset then
		return asset
	end
	local m = Instance.new("Model")
	local stripes = math.floor(width / 3)
	for i = 0, stripes - 1 do
		newPart("Part", {
			Size = Vector3.new(width / stripes, 1.2, 0.4),
			CFrame = CFrame.new(-width / 2 + (i + 0.5) * width / stripes, 3, 0),
			Color = i % 2 == 0 and rgb(210, 40, 40) or SIGN_WHITE,
			CanCollide = true,
			CanQuery = true,
			Parent = m,
		})
	end
	for _, x in { -width / 2 + 0.5, width / 2 - 0.5 } do
		newPart("Part", {
			Size = Vector3.new(0.5, 4, 0.5),
			CFrame = CFrame.new(x, 1.5, 0),
			Color = POST,
			CanCollide = true,
			Parent = m,
		})
	end
	local board = newPart("Part", {
		Size = Vector3.new(8, 2.4, 0.2),
		CFrame = CFrame.new(0, 5.3, 0),
		Color = rgb(210, 40, 40),
		Parent = m,
	})
	addText(board, "ROAD ENDS", SIGN_WHITE)
	return finish(m, "RoadEnd")
end

Props.addText = addText

return Props
