--[[
	Props
	-----
	Everything placed next to the road, built from plain parts so the game
	needs no uploaded assets: trees, bushes, cacti, rocks, flowers, road
	signs, delineator posts and barriers.

	Trees are built once as templates and then cloned. Every template is a
	Model whose pivot is the point where it meets the ground, so placing one
	is just `clone:PivotTo(CFrame.new(groundPoint) * yaw)`.

	Each tree kind also has a cheap "far" version (two parts at most) used by
	distant chunks. It keeps the near tree's silhouette: a stepped cone for
	pines, a crown on a trunk for broadleaf trees.

	Tree shapes are varied with a small seeded generator (not Random), so a
	given kind, size and variant looks the same in the game and in the
	offline tools (tools/render_props).

	If an AssetLibrary is given, premade models dropped into
	ReplicatedStorage.InfiniteRoadAssets replace the procedural ones kind by
	kind (see AssetLibrary.luau).
]]

local AssetLibrary = require(script.Parent.AssetLibrary)

local Props = {}
Props.__index = Props

local rgb = Color3.fromRGB
local BLACK, WHITE = Color3.new(0, 0, 0), Color3.new(1, 1, 1)

local BARK = rgb(96, 70, 50)
local PINE_GREENS = { rgb(50, 102, 60), rgb(58, 110, 62), rgb(44, 94, 62) }
local SNOW = rgb(236, 242, 246)
local FROST = rgb(184, 204, 196)
local OAK_GREENS = { rgb(86, 140, 60), rgb(104, 150, 58), rgb(72, 124, 56) }
local AUTUMN = { rgb(214, 122, 40), rgb(184, 62, 40), rgb(226, 180, 62), rgb(160, 96, 44) }
local BIRCH_BARK = rgb(232, 230, 222)
local BIRCH_MARK = rgb(46, 44, 44)
local BIRCH_LEAF = rgb(146, 184, 74)
local CYPRESS = rgb(62, 98, 62)
local CACTUS = rgb(88, 128, 70)
local FLOWERS = { rgb(240, 90, 110), rgb(250, 220, 70), rgb(240, 240, 250), rgb(170, 120, 230), rgb(250, 150, 60) }
local BLOSSOM = { rgb(244, 190, 212), rgb(250, 232, 240), rgb(236, 170, 198) }
local SPRING_GREEN = rgb(128, 184, 74)
local BARE_BARK = rgb(88, 70, 58)
local TWIGS = rgb(122, 108, 96)

local SIGN_YELLOW = rgb(244, 196, 40)
local SIGN_GREEN = rgb(30, 110, 64)
local SIGN_BLUE = rgb(30, 80, 160)
local SIGN_WHITE = rgb(242, 242, 238)
local SIGN_RED = rgb(200, 36, 36)
local SIGN_BACK = rgb(170, 174, 178) -- unpainted aluminium blank
local INK = rgb(20, 20, 22)
local POST = rgb(150, 152, 156)
local POST_DARK = rgb(104, 106, 110)

local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- turns a cylinder's X axis up
local FACING = CFrame.Angles(0, math.pi / 2, 0) -- turns a cylinder's X axis to face -Z
local DIAMOND = CFrame.Angles(0, 0, math.rad(45))

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

-- Deterministic number stream in [a, b) from a few integers (Park-Miller,
-- exact in doubles).
local function stream(...)
	local s = 7
	for _, v in { ... } do
		s = (s * 131 + math.floor(v)) % 2147483646
	end
	s += 1
	return function(a: number?, b: number?): number
		s = s * 48271 % 2147483647
		local r = s / 2147483647
		if a then
			return a + ((b :: number) - a) * r
		end
		return r
	end
end

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

-- flat vertical-axis cylinder centred on `center`, optionally tipped a little
local function disc(model, center: Vector3, diameter: number, height: number, color: Color3, tilt: CFrame?)
	local p = newPart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(center) * (tilt or CFrame.new()) * VERTICAL,
		Color = color,
	})
	p.Parent = model
	return p
end

-- cylinder from point a to point b
local function segment(model, a: Vector3, b: Vector3, diameter: number, color: Color3, material, collide: boolean?, extend: number?)
	local axis = (b - a).Unit
	local ref = math.abs(axis.Y) < 0.95 and Vector3.new(0, 1, 0) or Vector3.new(1, 0, 0)
	local z = axis:Cross(ref).Unit
	local e = extend or 0
	local p = newPart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new((b - a).Magnitude + e * 2, diameter, diameter),
		CFrame = CFrame.fromMatrix((a + b) * 0.5, axis, z:Cross(axis)),
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

local function darker(c: Color3, k: number): Color3
	return c:Lerp(BLACK, k)
end

local function lighter(c: Color3, k: number): Color3
	return c:Lerp(WHITE, k)
end

---------------------------------------------------------------------------
-- Tree builders (sc = scale, variant 0..2)
---------------------------------------------------------------------------
local BUILDERS = {}

-- A "tent": two wedges back to back, a ridge `len` long over a base `w`
-- wide. Crossing two tents at right angles makes a four-sided spire.
local function tent(m, base: CFrame, w: number, len: number, h: number, color: Color3)
	for _, turn in { 0, math.pi } do
		local p = newPart("WedgePart", {
			Size = Vector3.new(len, h, w / 2),
			CFrame = base * CFrame.Angles(0, turn, 0) * CFrame.new(0, h / 2, -w / 4),
			Color = color,
		})
		p.Parent = m
	end
end

--[[
	Pine: three faceted, tapering tiers on a short trunk. The lower two
	tiers are pairs of crossed tents (four-sided cones), the top one a
	single tent. Each tier is turned and nudged off centre, so the
	silhouette is jagged and no two trees are alike.
]]
local PINE_TIERS = {
	-- base height, width, height, tents
	{ 3, 13.2, 10.5, 2 },
	{ 9.6, 9.4, 9, 2 },
	{ 15.8, 5.6, 8.6, 1 },
}
local function pineTiers(m, sc, variant, green: Color3)
	local r = stream(3, variant, sc * 100)
	cylinder(m, -1.5, 10 * sc + 1.5, 1.6 * sc, BARK, Enum.Material.Wood, nil, true)
	for i, t in PINE_TIERS do
		local w, h = t[2] * sc * r(0.94, 1.05), t[3] * sc
		local base = CFrame.new(r(-0.35, 0.35) * sc, t[1] * sc, r(-0.35, 0.35) * sc) * CFrame.Angles(0, r(0, 6.28), 0)
		local color = i == 1 and darker(green, 0.12) or (i == 2 and green or lighter(green, 0.06))
		tent(m, base, w, w * 0.42, h, color)
		if t[4] == 2 then
			-- the crossing tent sits a hair higher so the two bases never
			-- share a plane
			tent(m, base * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, math.pi / 2, 0), w, w * 0.42, h - 0.05, darker(color, 0.05))
		end
	end
end

--[[
	Snowy pine: five stacked branch tiers, each under a snow cap a little
	wider than the tier, so the green only shows as a band underneath, and
	a snowy tip. Tiers are nudged and tipped for an irregular outline.
]]
local function snowTiers(m, sc, variant, green: Color3)
	local r = stream(3, variant, sc * 100)
	cylinder(m, -1.5, 10 * sc + 1.5, 1.6 * sc, BARK, Enum.Material.Wood, nil, true)
	local y = 3.2 * sc
	for i = 0, 4 do
		local d = (13 - 2.2 * i) * sc * r(0.94, 1.05)
		local h = (3.6 - 0.3 * i) * sc
		local c = Vector3.new(r(-0.3, 0.3) * sc, y + h / 2, r(-0.3, 0.3) * sc)
		local tilt = CFrame.Angles(r(-0.06, 0.06), 0, r(-0.06, 0.06))
		disc(m, c, d, h, darker(green, 0.1 - i * 0.03), tilt)
		if i < 4 then
			disc(m, c + Vector3.new(0, h / 2 + 0.05 * sc, 0), d * 1.03, 0.6 * sc, SNOW, tilt)
		else
			disc(m, c + Vector3.new(0, h / 2 + 1.2 * sc, 0), d * 0.55, 2.6 * sc, SNOW, tilt)
		end
		y += (3.5 - 0.25 * i) * sc
	end
end

-- far conifer: the same outline as a stepped cone of two parts
local function coniferFar(m, sc, lower: Color3, upper: Color3)
	cylinder(m, -0.5, 12.5 * sc, 10.5 * sc, lower)
	cylinder(m, 11.5 * sc, 9 * sc, 6.2 * sc, upper)
end

function BUILDERS.pine(sc, variant, far, style)
	local m = Instance.new("Model")
	local green = PINE_GREENS[variant % #PINE_GREENS + 1]
	if far then
		coniferFar(m, sc, darker(green, 0.08), green)
		return finish(m, "PineFar")
	end
	pineTiers(m, sc, variant, green)
	return finish(m, "Pine")
end

function BUILDERS.snowpine(sc, variant, far, style)
	local m = Instance.new("Model")
	local green = darker(PINE_GREENS[variant % #PINE_GREENS + 1], 0.08)
	if far then
		coniferFar(m, sc, green:Lerp(SNOW, 0.55), SNOW:Lerp(green, 0.2))
		return finish(m, "SnowPineFar")
	end
	snowTiers(m, sc, variant, green)
	return finish(m, "SnowPine")
end

-- Leaf colour of one blob of a broadleaf crown.
local function leafColor(base: Color3, variant: number, blob: number, style): Color3
	if style.autumn then
		-- mixed autumn crowns: neighbouring blobs turn at different rates
		return AUTUMN[(variant + blob) % #AUTUMN + 1]:Lerp(AUTUMN[(variant + blob * 2 + 1) % #AUTUMN + 1], 0.25)
	elseif style.blossom and variant % 3 == 0 then
		return BLOSSOM[(variant + blob) % #BLOSSOM + 1]
	elseif style.blossom then
		return SPRING_GREEN:Lerp(base, 0.4)
	end
	return base
end

local function oakColor(variant, style)
	return leafColor(OAK_GREENS[variant % #OAK_GREENS + 1], variant, 0, style)
end

--[[
	Winter: a bare crown. Four limbs leave the trunk one above the other,
	each carrying a twig, and the twigs get a touch of frost.
]]
local function bareTree(m, sc, variant, trunkH, trunkD, bark, twig)
	local r = stream(5, variant, sc * 100)
	cylinder(m, -1.5, trunkH * sc + 1.5, trunkD * sc, bark, Enum.Material.Wood, nil, true)
	local yaw0 = r(0, 6.28)
	for i = 0, 3 do
		-- limbs leave the trunk one above the other and spread like a vase
		local a = yaw0 + i * 1.9 + r(-0.3, 0.3)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = Vector3.new(0, trunkH * (0.62 + i * 0.12) * sc, 0)
		local tip = base + out * r(3.6, 4.8) * sc + Vector3.new(0, r(4.6, 6.2) * sc, 0)
		segment(m, base, tip, trunkD * (0.5 - i * 0.05) * sc, bark:Lerp(FROST, 0.08), Enum.Material.Wood, false, 0.2 * sc)
		-- a twig off the limb, turned the other way
		local mid = base:Lerp(tip, 0.6)
		local b = a + (i % 2 == 0 and 0.9 or -0.9)
		local twigTip = mid + Vector3.new(math.cos(b), 0, math.sin(b)) * 2.6 * sc + Vector3.new(0, 2.8 * sc, 0)
		segment(m, mid, twigTip, trunkD * 0.22 * sc, twig:Lerp(FROST, 0.3), Enum.Material.Wood, false, 0.1 * sc)
	end
end

-- Broadleaf crown: a big central blob, three or four around it and one on
-- top, placed from the seeded stream so crowns are irregular.
local function crown(m, sc, variant, base: Color3, style, center: Vector3, big: number, spread: number, n: number)
	local r = stream(9, variant, sc * 100)
	ball(m, center, big * sc, darker(leafColor(base, variant, 0, style), 0.05))
	local yaw0 = r(0, 6.28)
	for i = 1, n do
		local a = yaw0 + i * (6.28 / n) + r(-0.35, 0.35)
		local c = center + Vector3.new(math.cos(a) * spread * sc, r(-1.8, 0.6) * sc, math.sin(a) * spread * sc)
		local color = leafColor(base, variant, i, style)
		-- lower blobs sit in the crown's shade, upper ones catch the light
		color = c.Y < center.Y and darker(color, 0.1) or lighter(color, 0.04)
		ball(m, c, r(0.66, 0.8) * big * sc, color)
	end
	local topC = center + Vector3.new(r(-1, 1) * sc, big * 0.36 * sc, r(-1, 1) * sc)
	ball(m, topC, big * 0.66 * sc, lighter(leafColor(base, variant, n + 1, style), 0.08))
end

function BUILDERS.oak(sc, variant, far, style)
	local m = Instance.new("Model")
	if style.bare then
		if far then
			cylinder(m, -0.5, 9.5 * sc, 1.9 * sc, BARE_BARK)
			ball(m, Vector3.new(0, 12.5 * sc, 0), 11 * sc, lighter(TWIGS, 0.15))
			return finish(m, "OakFar")
		end
		bareTree(m, sc, variant, 7, 2.1, BARE_BARK, TWIGS)
		return finish(m, "Oak")
	end
	local leaf = OAK_GREENS[variant % #OAK_GREENS + 1]
	if far then
		cylinder(m, -0.5, 8.5 * sc, 2.1 * sc, BARK)
		ball(m, Vector3.new(0, 13 * sc, 0), 15 * sc, oakColor(variant, style))
		return finish(m, "OakFar")
	end
	cylinder(m, -1.5, 8 * sc + 1.5, 2.1 * sc, BARK, Enum.Material.Wood, nil, true)
	-- a limb leads from the trunk up into the crown
	local a = stream(4, variant, sc * 100)(0, 6.28)
	segment(m, Vector3.new(0, 5.8 * sc, 0), Vector3.new(math.cos(a) * 3.4 * sc, 10.2 * sc, math.sin(a) * 3.4 * sc), 0.95 * sc, BARK, Enum.Material.Wood, false, 0.3 * sc)
	crown(m, sc, variant, leaf, style, Vector3.new(0, 13 * sc, 0), 10.5, 4.7, 4)
	return finish(m, "Oak")
end

--[[
	Birch: a slim white trunk with a dark foot and a dark mark, under an
	oval crown that tapers upwards. The mark is a thin ring set off centre,
	so it shows as a patch on one side of the trunk.
]]
function BUILDERS.birch(sc, variant, far, style)
	local m = Instance.new("Model")
	if style.bare then
		if far then
			cylinder(m, -0.5, 14.5 * sc, 1.2 * sc, BIRCH_BARK)
			ball(m, Vector3.new(0, 15 * sc, 0), 7.5 * sc, lighter(TWIGS, 0.15))
			return finish(m, "BirchFar")
		end
		bareTree(m, sc, variant, 11, 1.3, BIRCH_BARK, rgb(92, 78, 72))
		return finish(m, "Birch")
	end
	-- birches turn gold in autumn, some blobs a little more orange
	local function leaf(blob)
		if style.autumn then
			return AUTUMN[3]:Lerp(AUTUMN[1], ((variant + blob) % 3) * 0.2)
		end
		return leafColor(BIRCH_LEAF, variant, blob, style)
	end
	if far then
		cylinder(m, -0.5, 11 * sc, 1.2 * sc, BIRCH_BARK)
		ball(m, Vector3.new(0, 14.5 * sc, 0), 9.5 * sc, leaf(0))
		return finish(m, "BirchFar")
	end
	local d = 1.25 * sc
	cylinder(m, -1.5, 16 * sc + 1.5, d, BIRCH_BARK, Enum.Material.SmoothPlastic, nil, true)
	cylinder(m, -1.4, 2.2 * sc, d + 0.14 * sc, darker(BIRCH_BARK, 0.62), Enum.Material.Wood)
	local r = stream(6, variant, sc * 100)
	local a = r(0, 6.28)
	cylinder(m, r(4.8, 5.6) * sc, 0.32 * sc, d + 0.1 * sc, BIRCH_MARK, nil, Vector3.new(math.cos(a), 0, math.sin(a)) * d * 0.14)
	-- an oval crown: two blobs side by side, one above, a small top
	local blobs = {
		{ Vector3.new(1.3, 12, 0.5), 5.8 },
		{ Vector3.new(-1.3, 12.6, -0.5), 5.6 },
		{ Vector3.new(0.2, 15.1, 0.3), 6.2 },
		{ Vector3.new(-0.3, 17.9, -0.2), 4.4 },
	}
	for i, b in blobs do
		local c = Vector3.new(b[1].X + r(-0.4, 0.4), b[1].Y, b[1].Z + r(-0.4, 0.4)) * sc
		local color = leaf(i)
		color = i == 1 and darker(color, 0.08) or lighter(color, (i - 2) * 0.04)
		ball(m, c, b[2] * sc, color)
	end
	return finish(m, "Birch")
end

--[[
	Wind-swept coastal cypress: a leaning trunk, a short branch into the
	wind, and flat-topped foliage pads streaming downwind (+X).
]]
function BUILDERS.cypress(sc, variant, far, style)
	local m = Instance.new("Model")
	local green = style.frost and CYPRESS:Lerp(FROST, 0.3) or CYPRESS
	if far then
		segment(m, Vector3.new(0, -0.5, 0), Vector3.new(1.4 * sc, 9.5 * sc, 0), 1.5 * sc, BARK)
		cylinder(m, 9 * sc, 3.6 * sc, 15 * sc, green, nil, Vector3.new(2.6 * sc, 0, 0))
		return finish(m, "CypressFar")
	end
	local r = stream(8, variant, sc * 100)
	local knee = Vector3.new(0.8 * sc, 5 * sc, 0)
	local top = Vector3.new(1.9 * sc, 9.6 * sc, r(-0.4, 0.4) * sc)
	segment(m, Vector3.new(0, -1.5, 0), knee, 1.7 * sc, BARK, Enum.Material.Wood, true, 0.4 * sc)
	segment(m, knee, top, 1.25 * sc, BARK, Enum.Material.Wood, false, 0.3 * sc)
	local branchTip = Vector3.new(-3 * sc, 8.2 * sc, r(0.4, 1.2) * sc)
	segment(m, knee + Vector3.new(0, 0.6 * sc, 0), branchTip, 0.75 * sc, BARK, Enum.Material.Wood, false, 0.2 * sc)
	local pads = {
		{ Vector3.new(3.4, 11.2, 0.2), 13, 3.8, 0 },
		{ Vector3.new(1, 13.6, -0.6), 8.4, 3, 0.07 },
		{ Vector3.new(7.6, 10.3, 1), 6.6, 3, -0.06 },
		{ branchTip / sc + Vector3.new(-0.4, 0.6, 0), 5.4, 2.6, -0.1 },
	}
	for i, pd in pads do
		local c = (pd[1] + Vector3.new(r(-0.4, 0.4), r(-0.25, 0.25), r(-0.4, 0.4))) * sc
		local tilt = CFrame.Angles(r(-0.06, 0.06), r(0, 6), r(-0.06, 0.06))
		disc(m, c, pd[2] * sc * r(0.94, 1.06), pd[3] * sc, green:Lerp(i == 2 and WHITE or BLACK, math.abs(pd[4])), tilt)
		if i == 1 and style.frost then
			disc(m, c + Vector3.new(0, pd[3] * sc / 2 + 0.1 * sc, 0), pd[2] * sc * 0.7, 0.4 * sc, SNOW:Lerp(green, 0.12), tilt)
		end
	end
	return finish(m, "Cypress")
end

local PALM_TRUNK = rgb(150, 124, 92)
local PALM_LEAF = rgb(70, 132, 60)
local COCONUT = rgb(110, 84, 50)

--[[
	Coconut palm: a trunk of three tapering segments that bends more
	towards the top, a crown of seven fronds (three younger ones rising,
	four long ones drooping) and a pair of coconuts.
]]
function BUILDERS.palm(sc, variant, far, style)
	local m = Instance.new("Model")
	local leaf = style.frost and PALM_LEAF:Lerp(FROST, 0.4) or (style.autumn and PALM_LEAF:Lerp(rgb(150, 140, 60), 0.35) or PALM_LEAF)
	local r = stream(10, variant, sc * 100)
	local lean = math.rad(8 + (variant % 3) * 5)
	-- trunk points, bending progressively
	local pts = { Vector3.new(0, -1.5, 0) }
	local lens = { 5.8, 4.8, 3.8 }
	for i, len in lens do
		local a = lean * (0.35 + 0.5 * i)
		table.insert(pts, pts[i] + Vector3.new(math.sin(a), math.cos(a), 0) * len * sc)
	end
	local top = pts[4]
	if far then
		segment(m, pts[1], top, 1.2 * sc, PALM_TRUNK, Enum.Material.Wood)
		cylinder(m, top.Y - 1.6 * sc, 2 * sc, 10 * sc, leaf, nil, top + Vector3.new(0.4 * sc, 0, 0))
		return finish(m, "PalmFar")
	end
	for i = 1, 3 do
		segment(m, pts[i], pts[i + 1], (1.55 - i * 0.17) * sc, darker(PALM_TRUNK, (i % 2) * 0.08), Enum.Material.Wood, i == 1, 0.25 * sc)
	end
	local yaw0 = r(0, 6.28)
	for i = 1, 7 do
		local young = i <= 3
		local yaw = yaw0 + (young and i * 2.09 or i * 1.57 + 0.6) + r(-0.25, 0.25)
		local pitch = young and math.rad(r(14, 28)) or -math.rad(r(30, 48))
		local len = (young and r(4.8, 5.6) or r(7.2, 8.2)) * sc
		-- lying flat, then rolled a little so side views still catch the leaf
		local flat = (i % 2 == 0 and 1 or -1) * (math.pi / 2 + r(0.2, 0.4))
		local frond = newPart("WedgePart", {
			Name = "Frond",
			Size = Vector3.new(0.18 * sc, 2.5 * sc, len),
			-- base at the crown, tip out along -Z
			CFrame = CFrame.new(top) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, 0, 0.5 * sc - len / 2) * CFrame.Angles(0, 0, flat),
			Color = leaf:Lerp(BLACK, young and 0 or 0.1 + (i % 2) * 0.05),
		})
		frond.Parent = m
	end
	for i = 0, 1 do
		local a = yaw0 + i * 2.4
		ball(m, top + Vector3.new(math.cos(a) * 0.55 * sc, -0.75 * sc, math.sin(a) * 0.55 * sc), 1.05 * sc, COCONUT)
	end
	return finish(m, "Palm")
end

-- Saguaro: a trunk and two arms, each a horizontal stub, an elbow, an
-- upright and a rounded tip. A dusting of frost on the tips in winter.
function BUILDERS.cactus(sc, variant, far, style)
	local m = Instance.new("Model")
	local d = 1.9 * sc
	if far then
		cylinder(m, -0.5, 11.5 * sc, 2 * sc, CACTUS)
		cylinder(m, 4.5 * sc, 3.6 * sc, 1.5 * sc, CACTUS, nil, Vector3.new(1.55 * sc, 0, 0))
		return finish(m, "CactusFar")
	end
	local tipColor = style.frost and CACTUS:Lerp(SNOW, 0.7) or lighter(CACTUS, 0.05)
	cylinder(m, -1, 11 * sc + 1, d, CACTUS, nil, nil, true)
	-- tips a touch wider than the stems, so the two never just graze
	ball(m, Vector3.new(0, 11 * sc, 0), d * 1.05, tipColor)
	local side = variant % 2 == 0 and 1 or -1
	local arm = d * 0.8
	local armColor = darker(CACTUS, 0.06)
	for i = 0, 1 do
		local s = i == 0 and side or -side
		local y = (4.2 + i * 2.4 + (variant % 3) * 0.3) * sc
		local x = s * (2.3 - i * 0.3) * sc
		local rise = (3.6 - i * 1.2) * sc
		segment(m, Vector3.new(0, y, 0), Vector3.new(x, y, 0), arm, armColor)
		ball(m, Vector3.new(x, y, 0), arm, armColor)
		cylinder(m, y, rise, arm, armColor, nil, Vector3.new(x, 0, 0))
		ball(m, Vector3.new(x, y + rise, 0), arm * 1.05, tipColor)
	end
	return finish(m, "Cactus")
end

function BUILDERS.bush(sc, variant, far, style)
	local m = Instance.new("Model")
	if style.bare then
		ball(m, Vector3.new(0, 1.1 * sc, 0), 3.4 * sc, TWIGS)
		ball(m, Vector3.new(1.1 * sc, 0.8 * sc, 0.5 * sc), 2.4 * sc, lighter(TWIGS, 0.1):Lerp(FROST, 0.2))
		return finish(m, "Bush")
	end
	local leaf = darker(oakColor(variant + 1, { autumn = style.autumn }), 0.1)
	local r = stream(12, variant, sc * 100)
	local a = r(0, 6.28)
	ball(m, Vector3.new(0, 1.3 * sc, 0), 4.4 * sc, leaf)
	ball(m, Vector3.new(math.cos(a) * 1.6 * sc, 0.95 * sc, math.sin(a) * 1.6 * sc), 3.2 * sc, lighter(leaf, 0.06))
	ball(m, Vector3.new(math.cos(a + 2.4) * 1.4 * sc, 0.8 * sc, math.sin(a + 2.4) * 1.4 * sc), 2.7 * sc, darker(leaf, 0.08))
	return finish(m, "Bush")
end

function BUILDERS.drybush(sc, variant, far, style)
	local m = Instance.new("Model")
	local c = rgb(138, 128, 74):Lerp(rgb(110, 100, 60), (variant % 3) / 3)
	ball(m, Vector3.new(0, 0.9 * sc, 0), 3.2 * sc, c)
	ball(m, Vector3.new(0.9 * sc, 0.7 * sc, 0.6 * sc), 2.2 * sc, lighter(c, 0.08))
	return finish(m, "DryBush")
end

-- A patch of blooms around a low leafy clump.
function BUILDERS.flowers(sc, variant, far, style)
	local m = Instance.new("Model")
	local r = stream(13, variant)
	local color = FLOWERS[variant % #FLOWERS + 1]
	local p = ball(m, Vector3.new(0, 0.25, 0), 1.9, rgb(84, 140, 64))
	p.CastShadow = false
	for i = 1, 3 do
		local a = i * 2.09 + r(-0.5, 0.5)
		local dist = r(0.6, 1.3)
		local size = r(0.6, 0.85)
		-- blooms nearer the middle sit higher, on the clump
		local y = 0.35 + size / 2 + (1.3 - dist) * 0.3
		p = ball(m, Vector3.new(math.cos(a) * dist, y, math.sin(a) * dist), size, i == 3 and lighter(color, 0.3) or color)
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
-- kind: pine, snowpine, oak, birch, cypress, palm, cactus, bush, drybush, flowers
-- size: 1..3, variant: any integer, far: two-part version
function Props:tree(kind: string, size: number, variant: number, far: boolean, autumn: boolean?)
	local assets = self.assets
	if assets then
		local key = kind
		if autumn and assets:has(kind .. "_autumn") then
			key = kind .. "_autumn"
		elseif kind == "snowpine" and not assets:has("snowpine") then
			key = "pine"
		end
		-- heavy asset trees fall back to the cheap stand-in far away
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
--
-- A sign is a stack of flat plates: an aluminium blank at the back, then
-- the border, the face and any symbol, each 0.06 studs in front of the one
-- behind and sunk 0.02 into it, so no two faces share a plane (no
-- flicker) and nothing floats. The post stands behind the blank, held by a
-- bracket. Seen from the driver's side, x runs right to left (the viewer's
-- right is -X), so symbols below mirror their x.
---------------------------------------------------------------------------
local LAYER, PLATE = 0.06, 0.08

local function styleLabel(label: TextLabel, text: string, color: Color3, font)
	label.BackgroundTransparency = 1
	label.Font = font or Enum.Font.GothamBlack
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
end

-- Light legends (white on green or blue) are partly self-lit, the way
-- retroreflective lettering stands out at dusk.
local function newGui(target: BasePart, color: Color3, face)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = (color.R + color.G + color.B) > 2 and 0.8 or 1
	gui.MaxDistance = 450
	gui.Parent = target
	return gui
end

local function addText(target: BasePart, text: string, color: Color3, face)
	local gui = newGui(target, color, face)
	local label = Instance.new("TextLabel")
	styleLabel(label, text, color)
	label.Size = UDim2.fromScale(1, 1)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.07, 0)
	pad.PaddingRight = UDim.new(0.07, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	label.Parent = gui
	return label
end

-- Several text lines of their own sizes on one face. rows: { {text, top,
-- height, font?} } with top/height as fractions of the face height.
local function addRows(target: BasePart, rows, color: Color3)
	local gui = newGui(target, color)
	local main
	for i, row in rows do
		local label = Instance.new("TextLabel")
		styleLabel(label, row[1], color, row[4])
		label.Name = i == #rows and "Label" or "Header"
		label.Position = UDim2.fromScale(0.06, row[2])
		label.Size = UDim2.fromScale(0.88, row[3])
		label.Parent = gui
		main = label
	end
	return main
end

-- flat plate on layer `layer` (0 = the blank at the back); the sign face,
-- named "Board", gets a faint sheen like retroreflective sheeting
local function plate(m, name: string, w: number, h: number, x: number, y: number, layer: number, color: Color3, turn: CFrame?)
	local front = -layer * LAYER
	return newPart("Part", {
		Name = name,
		Size = Vector3.new(w, h, PLATE),
		CFrame = CFrame.new(x, y, front + PLATE / 2) * (turn or CFrame.new()),
		Color = color,
		Reflectance = name == "Board" and 0.05 or 0,
		Parent = m,
	})
end

-- Posts reach well below the pivot: the terrain hides what it covers, and
-- where the verge falls away from the road the post still meets it.
local BURY = 4

-- round galvanised post behind the blank, from BURY below ground to `top`
local function signPost(m, top: number, x: number?)
	return newPart("Part", {
		Name = "Post",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(top + BURY, 0.3, 0.3),
		CFrame = CFrame.new(x or 0, (top - BURY) / 2, 0.36) * VERTICAL,
		Color = POST,
		Material = Enum.Material.Metal,
		CanCollide = true,
		Parent = m,
	})
end

-- channel bracket joining the blank to the post(s)
local function bracket(m, x: number, y: number, w: number, h: number)
	return newPart("Part", {
		Name = "Bracket",
		Size = Vector3.new(w, h, 0.26),
		CFrame = CFrame.new(x, y, 0.19),
		Color = POST_DARK,
		Material = Enum.Material.Metal,
		Parent = m,
	})
end

-- invisible part carrying text in front of layer `layer`
local function labelPart(m, w: number, h: number, x: number, y: number, layer: number)
	return newPart("Part", {
		Name = "Label",
		Size = Vector3.new(w, h, 0.02),
		CFrame = CFrame.new(x, y, -layer * LAYER - 0.02),
		Transparency = 1,
		CastShadow = false,
		Parent = m,
	})
end

-- symbol plate given in the viewer's frame (u right, v up, angle
-- counter-clockwise as the viewer sees it)
local function glyph(m, w: number, h: number, u: number, v: number, angle: number, layer: number, color: Color3?)
	return plate(m, "Symbol", w, h, -u, v, layer, color or INK, CFrame.Angles(0, 0, -angle))
end

-- Arrowhead: a right-angled wedge whose right angle points along (wu, wv)
-- (a unit direction in the viewer's frame). (u, v) is the middle of its
-- back edge, which is `legs` * 1.41 wide.
local function arrowHead(m, u: number, v: number, wu: number, wv: number, legs: number, layer: number)
	local w = Vector3.new(-wu, wv, 0)
	local p = Vector3.new(-w.Y, w.X, 0)
	local y, z = (p - w).Unit, (p + w).Unit
	return newPart("WedgePart", {
		Name = "Symbol",
		Size = Vector3.new(PLATE, legs, legs),
		CFrame = CFrame.fromMatrix(Vector3.new(-u, v, -layer * LAYER + PLATE / 2), y:Cross(z), y),
		Color = INK,
		Parent = m,
	})
end

-- Yellow diamond warning sign. `kind` names the asset slot that can
-- replace it (CurveLeft, CurveRight, FallingRocks, Deer); curves and
-- falling rocks get a symbol, anything else shows `text`.
function Props:warningSign(text: string, kind: string?): Model
	local asset = kind and self:_asset(kind, 1, 0)
	if asset then
		return asset
	end
	local key = "warn/" .. (kind or "") .. "/" .. text
	local t = self.templates[key]
	if t then
		return t:Clone()
	end
	local m = Instance.new("Model")
	local cy = 8
	signPost(m, cy + 1.4)
	bracket(m, 0, cy, 0.22, 2.4)
	plate(m, "Blank", 3.6, 3.6, 0, cy, 0, SIGN_BACK, DIAMOND)
	plate(m, "Border", 3.7, 3.7, 0, cy, 1, INK, DIAMOND)
	plate(m, "Board", 3.3, 3.3, 0, cy, 2, SIGN_YELLOW, DIAMOND)
	if kind == "CurveRight" or kind == "CurveLeft" then
		-- bent arrow: a stem, an arm leaning into the curve, a head
		local dir = kind == "CurveRight" and 1 or -1
		local lean = math.rad(40)
		local wu, wv = math.sin(lean) * dir, math.cos(lean)
		local ju, jv = -0.3 * dir, cy + 0.1 -- where the arm leaves the stem
		glyph(m, 0.4, 1.35, ju, cy - 0.45, 0, 3)
		glyph(m, 0.4, 0.95, ju + wu * 0.275, jv + wv * 0.275, -lean * dir, 3)
		arrowHead(m, ju + wu * 0.7, jv + wv * 0.7, wu, wv, 0.95, 3)
	elseif kind == "FallingRocks" then
		-- a cliff on the left with two rocks falling off it (the wedge's
		-- upright side ends up on the viewer's left)
		newPart("WedgePart", {
			Name = "Symbol",
			Size = Vector3.new(PLATE, 1.9, 1.45),
			CFrame = CFrame.new(0.28, cy - 0.05, -3 * LAYER + PLATE / 2) * FACING,
			Color = INK,
			Parent = m,
		})
		glyph(m, 0.46, 0.46, 0.34, cy + 0.5, math.rad(20), 3)
		glyph(m, 0.58, 0.58, 0.72, cy - 0.45, math.rad(-15), 3)
	else
		-- two lines, the lower one widest where the diamond is widest
		local label = labelPart(m, 3.4, 1.4, 0, cy + 0.1, 2)
		local first, second = string.match(text, "^([^\n]+)\n(.+)$")
		if first then
			addRows(label, { { first, 0.05, 0.4 }, { second, 0.52, 0.4 } }, INK)
		else
			addText(label, text, INK)
		end
	end
	finish(m, "WarningSign")
	self.templates[key] = m
	return m:Clone()
end

-- Yellow chevron board with a black ">" for sharp curves.
function Props:chevron(pointRight: boolean): Model
	local asset = self:_asset(pointRight and "ChevronRight" or "ChevronLeft", 1, 0)
	if asset then
		return asset
	end
	local key = pointRight and "chevronR" or "chevronL"
	local t = self.templates[key]
	if not t then
		t = Instance.new("Model")
		local cy = 5.8
		signPost(t, cy + 1.3)
		bracket(t, 0, cy, 0.22, 2.2)
		plate(t, "Blank", 2.3, 2.9, 0, cy, 0, SIGN_BACK)
		plate(t, "Board", 2.4, 3, 0, cy, 1, SIGN_YELLOW)
		local dir = pointRight and 1 or -1
		local tipU = 0.42 * dir
		for _, up in { 1, -1 } do
			-- each arm runs from the tip back to the far side, 45 degrees off level
			local a = math.rad(45)
			local du, dv = -math.cos(a) * dir, math.sin(a) * up
			local len = 1.55
			glyph(t, 0.6, len, tipU + du * (len / 2 - 0.2), cy + dv * (len / 2 - 0.2), math.atan2(-du, dv), 2)
		end
		finish(t, "Chevron")
		self.templates[key] = t
	end
	return t:Clone()
end

-- Generic rectangular sign on one or two posts: blank, frame in `fg`,
-- board in `bg`, text in `fg`.
function Props:panel(text: string, width: number, height: number, bg: Color3, fg: Color3, bottom: number?): Model
	local m = Instance.new("Model")
	local base = bottom or 5
	local cy = base + height / 2
	local top = base + height - 0.4
	if width > 6 then
		signPost(m, top, -width * 0.3)
		signPost(m, top, width * 0.3)
		bracket(m, 0, cy, width * 0.6 + 0.3, 0.3)
	else
		signPost(m, top)
		bracket(m, 0, cy, 0.22, height * 0.7)
	end
	plate(m, "Blank", width + 0.2, height + 0.2, 0, cy, 0, SIGN_BACK)
	plate(m, "Frame", width + 0.3, height + 0.3, 0, cy, 1, fg)
	local board = plate(m, "Board", width, height, 0, cy, 2, bg)
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

-- A procedural sign from `build`. Signs whose text repeats (speed limits)
-- are cached; one-off texts (names, lengths, kilometres) are not, so the
-- cache cannot grow without end on an endless road.
function Props:_sign(key: string?, build): Model
	if not key then
		return build()
	end
	local t = self.templates[key]
	if not t then
		t = build()
		self.templates[key] = t
	end
	return t:Clone()
end

-- White regulatory sign: black border, SPEED LIMIT over a large number.
function Props:speedLimit(limit: number): Model
	return self:_textSign("SpeedLimit", tostring(limit)) or self:_sign("speed/" .. limit, function()
		local m = Instance.new("Model")
		local w, h, cy = 3, 3.8, 6.5
		signPost(m, cy + 1.55)
		bracket(m, 0, cy, 0.22, h * 0.7)
		plate(m, "Blank", w - 0.1, h - 0.1, 0, cy, 0, SIGN_BACK)
		plate(m, "Border", w, h, 0, cy, 1, INK)
		local face = plate(m, "Board", w - 0.26, h - 0.26, 0, cy, 2, SIGN_WHITE)
		addRows(face, {
			{ "SPEED\nLIMIT", 0.07, 0.36, Enum.Font.GothamBold },
			{ tostring(limit), 0.44, 0.5 },
		}, INK)
		return finish(m, "Sign")
	end)
end

-- Green guide sign: green margin, white border, green field. A first line
-- ("Entering") is set smaller above the name.
function Props:guideSign(text: string): Model
	return self:_textSign("Guide", text) or self:_sign(nil, function()
		local m = Instance.new("Model")
		local w, h, cy = 13, 5, 8.5
		for _, x in { -w * 0.3, w * 0.3 } do
			signPost(m, cy + h / 2 - 0.4, x)
		end
		bracket(m, 0, cy, w * 0.6 + 0.3, 0.3)
		plate(m, "Blank", w - 0.1, h - 0.1, 0, cy, 0, SIGN_BACK)
		plate(m, "Margin", w, h, 0, cy, 1, SIGN_GREEN)
		plate(m, "Frame", w - 0.3, h - 0.3, 0, cy, 2, SIGN_WHITE)
		local face = plate(m, "Board", w - 0.6, h - 0.6, 0, cy, 3, SIGN_GREEN)
		local header, name = string.match(text, "^([^\n]+)\n(.+)$")
		if header then
			addRows(face, { { header, 0.08, 0.26, Enum.Font.GothamBold }, { name, 0.36, 0.56 } }, SIGN_WHITE)
		else
			addText(face, text, SIGN_WHITE)
		end
		return finish(m, "Sign")
	end)
end

-- Blue tunnel sign: a black tunnel mouth on a white field, length below.
function Props:tunnelSign(lengthText: string): Model
	return self:_textSign("Tunnel", lengthText) or self:_sign(nil, function()
		local m = Instance.new("Model")
		local w, h, cy = 3.2, 4.2, 6.6
		signPost(m, cy + 1.7)
		bracket(m, 0, cy, 0.22, h * 0.7)
		plate(m, "Blank", w - 0.1, h - 0.1, 0, cy, 0, SIGN_BACK)
		local face = plate(m, "Board", w, h, 0, cy, 1, SIGN_BLUE)
		plate(m, "Field", 2.4, 2.1, 0, cy + 0.72, 2, SIGN_WHITE)
		local mouth = cy + 0.55
		newPart("Part", {
			Name = "Symbol",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(PLATE, 1.5, 1.5),
			CFrame = CFrame.new(0, mouth, -3 * LAYER + PLATE / 2) * FACING,
			Color = INK,
			Parent = m,
		})
		plate(m, "Symbol", 1.5, 0.78, 0, mouth - 0.39, 3, INK)
		addRows(face, { { lengthText, 0.7, 0.24 } }, SIGN_WHITE)
		return finish(m, "Sign")
	end)
end

-- Small green kilometre marker.
function Props:distanceMarker(text: string): Model
	return self:_textSign("Marker", text) or self:_sign(nil, function()
		local m = Instance.new("Model")
		local w, h, cy = 1.5, 2.2, 3.8
		signPost(m, cy + 0.8)
		bracket(m, 0, cy, 0.22, 1.4)
		plate(m, "Blank", w - 0.1, h - 0.1, 0, cy, 0, SIGN_BACK)
		plate(m, "Frame", w, h, 0, cy, 1, SIGN_WHITE)
		local face = plate(m, "Board", w - 0.2, h - 0.2, 0, cy, 2, SIGN_GREEN)
		addRows(face, { { "KM", 0.08, 0.24, Enum.Font.GothamBold }, { text, 0.36, 0.52 } }, SIGN_WHITE)
		return finish(m, "Sign")
	end)
end

-- White roadside post with a sloped top, a black band and an amber
-- reflector that glows in headlights (Neon).
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
			Size = Vector3.new(0.4, 3 + BURY / 2, 0.36),
			CFrame = CFrame.new(0, (3 - BURY / 2) / 2, 0),
			Color = SIGN_WHITE,
			CastShadow = false,
			Parent = t,
		})
		newPart("WedgePart", {
			Name = "Cap",
			Size = Vector3.new(0.4, 0.3, 0.36),
			CFrame = CFrame.new(0, 3.15, 0),
			Color = SIGN_WHITE,
			CastShadow = false,
			Parent = t,
		})
		newPart("Part", {
			Name = "Band",
			Size = Vector3.new(0.44, 0.8, 0.4),
			CFrame = CFrame.new(0, 2.45, 0),
			Color = INK,
			CastShadow = false,
			Parent = t,
		})
		newPart("Part", {
			Name = "Reflector",
			Size = Vector3.new(0.2, 0.46, 0.05),
			CFrame = CFrame.new(0, 2.45, -0.215),
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

-- Barricade across the road where it begins: two rails of red and white
-- panels on three legs, amber lamps on the end legs and a ROAD ENDS board.
function Props:roadEnd(width: number): Model
	local asset = self:_asset("RoadEnd", 1, 0)
	if asset then
		return asset
	end
	local m = Instance.new("Model")
	local half = width / 2
	for _, x in { -half + 0.6, 0, half - 0.6 } do
		local top = x == 0 and 6.6 or 4
		newPart("Part", {
			Name = "Leg",
			Size = Vector3.new(0.5, top + BURY, 0.5),
			CFrame = CFrame.new(x, (top - BURY) / 2, 0.25),
			Color = POST,
			Material = Enum.Material.Metal,
			CanCollide = true,
			Parent = m,
		})
		if x ~= 0 then
			newPart("Part", {
				Name = "Lamp",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.45, 0.5, 0.5),
				CFrame = CFrame.new(x, top + 0.2, 0.25) * VERTICAL,
				Color = rgb(255, 176, 40),
				Material = Enum.Material.Neon,
				CastShadow = false,
				Parent = m,
			})
		end
	end
	local panels = math.max(4, math.floor(width / 4))
	local pw = width / panels
	for row = 0, 1 do
		for i = 0, panels - 1 do
			newPart("Part", {
				Name = "Rail",
				Size = Vector3.new(pw, 0.9, 0.25),
				CFrame = CFrame.new(-half + (i + 0.5) * pw, 2.05 + row * 1.3, -0.1),
				Color = (i + row) % 2 == 0 and SIGN_RED or SIGN_WHITE,
				CanCollide = true,
				CanQuery = true,
				Parent = m,
			})
		end
	end
	local cy = 5.6
	plate(m, "Blank", 6.9, 1.7, 0, cy, 0, SIGN_BACK)
	plate(m, "Border", 7, 1.8, 0, cy, 1, INK)
	local board = plate(m, "Board", 6.76, 1.56, 0, cy, 2, SIGN_WHITE)
	addText(board, "ROAD ENDS", INK)
	return finish(m, "RoadEnd")
end

Props.addText = addText

return Props
