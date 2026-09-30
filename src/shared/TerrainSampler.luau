--!native
--[[
	TerrainSampler
	--------------
	The height model. For any world (x, z) it answers: how high is the
	ground, is there water, is there a tunnel void, and what kind of surface
	is it.

	Pipeline for one column:
	  1. project onto the road            -> s, d (arc length, lateral offset)
	  2. region heights, cross-faded       -> base terrain  (Meadow, Forest, ...)
	  3. crossings                         -> ridges raised, river valleys and gorges carved
	  4. rivers running beside the road    -> channels carved
	  5. water                             -> sea, lakes, rivers
	  6. road corridor                     -> cuts, embankments, tunnel voids, bridge gaps

	Steps 1-5 are "preRoad" terrain. RoadPath samples it along the road to
	decide where tunnels, bridges and guard rails go.
]]

local MathUtil = require(script.Parent.MathUtil)

local smoothstep, clamp, smin = MathUtil.smoothstep, MathUtil.clamp, MathUtil.smin
local abs, max, min, sqrt, exp, sin, cos, floor = math.abs, math.max, math.min, math.sqrt, math.exp, math.sin, math.cos, math.floor
local NEG_INF = -math.huge

local Sampler = {}
Sampler.__index = Sampler

-- surface hints (what the region thinks this ground is)
Sampler.Hint = {
	None = 0,
	CanyonFloor = 1,
	CanyonWall = 2,
	Beach = 3,
	Cliff = 4,
	Seabed = 5,
	Lakebed = 6,
	Riverbed = 7,
	Plateau = 8,
}
local HINT = Sampler.Hint

-- column flags
Sampler.Flag = {
	RoadBed = 1,
	Shoulder = 2,
	Cut = 4,
	Fill = 8,
	Tunnel = 16,
	Bridge = 32,
}
local FLAG = Sampler.Flag

Sampler.TypeIndex = {
	Meadow = 1,
	Forest = 2,
	Mountains = 3,
	Coast = 4,
	Canyon = 5,
	Lake = 6,
	RiverValley = 7,
}
local TYPE_INDEX = Sampler.TypeIndex

function Sampler.new(config, noise, sections, road)
	local self = setmetatable({}, Sampler)
	self.config = config
	self.noise = noise
	self.sections = sections
	self.road = road
	self.hw = config.Road.HalfWidth
	self.sea = config.SeaLevel
	self._crossBuf = {}
	return self
end

-- corridor attenuation: relief is scaled down near the road so the road
-- tends to run along valleys with mountains beside it
local function corr(ad: number, hw: number, width: number, minA: number): number
	return minA + (1 - minA) * smoothstep(hw + 8, width, ad)
end

---------------------------------------------------------------------------
-- Region height functions: each returns (height, hint)
---------------------------------------------------------------------------
function Sampler:_meadow(x, z, ad, E)
	local n = self.noise
	local hills = n:fbm2(x / 650, z / 650, 3, 1)
	local rolls = n:fbm2(x / 260, z / 260, 2, 2)
	local c = corr(ad, self.hw, 380, 0.35)
	return E + 6 + c * (34 * hills + 12 * rolls) + 2.5 * n:n2(x / 60, z / 60, 3), HINT.None
end

function Sampler:_forest(x, z, ad, E)
	local n = self.noise
	local hills = n:fbm2(x / 560, z / 560, 4, 4)
	local ridges = n:ridged2(x / 900, z / 900, 3, 5)
	local c = corr(ad, self.hw, 430, 0.28)
	return E + c * (55 * hills + 120 * ridges) + 3 * n:n2(x / 70, z / 70, 3), HINT.None
end

function Sampler:_mountains(x, z, ad, E)
	local n = self.noise
	local m = n:ridged2(x / 1150, z / 1150, 5, 6)
	local hills = n:fbm2(x / 480, z / 480, 3, 7)
	local c = corr(ad, self.hw, 560, 0.13)
	local peaks = 520 * m ^ 1.45
	return E + c * (peaks + 55 * hills) + (1 - c) * 16 * hills + 5 * n:n2(x / 80, z / 80, 3), HINT.None
end

function Sampler:_canyonShape(s)
	local n = self.noise
	return 0.75 + 0.5 * n:u1(s / 900, 21), 0.8 + 0.4 * n:u1(s / 1500, 22)
end

function Sampler:_canyon(sec, x, z, s, ad, E)
	local n = self.noise
	local fh, dm = self:_canyonShape(s)
	local floorHalf = sec.floorHalf * fh
	local depth = sec.depth * dm
	local erosion = 16 * n:fbm2(x / 150, z / 150, 2, 23)
	local tierW = 30 + 16 * n:u2(x / 320, z / 320, 24)
	local u = (ad + erosion - floorHalf) / tierW
	local floorH = E + 1.5 * n:n2(x / 50, z / 50, 25)
	if u <= 0 then
		return floorH, HINT.CanyonFloor
	end
	local tiers = 3
	local i = floor(u)
	local frac
	if i >= tiers then
		frac = 1
	else
		frac = (i + smoothstep(0, 0.38, u - i)) / tiers
	end
	local plateau = 14 * n:fbm2(x / 420, z / 420, 3, 26)
	-- buttes and mesas rising out of the plateau
	local b = n:u2(x / 260, z / 260, 27)
	if b > 0.72 then
		plateau += 70 * smoothstep(0.72, 0.8, b)
	end
	local h = floorH + depth * frac + plateau * frac ^ 4
	if frac >= 1 then
		return h, HINT.Plateau
	end
	return h, HINT.CanyonWall
end

function Sampler:_coastEdge(s, x, z)
	local n = self.noise
	return self.hw + 9 + 26 * n:u1(s / 320, 31) + 10 * n:n2(x / 90, z / 90, 32)
end

function Sampler:_coast(sec, x, z, s, d, ad, roadY)
	local n = self.noise
	local sea = self.sea
	local hw = self.hw
	local dd = sec.side * d -- positive toward the ocean
	local edge = self:_coastEdge(s, x, z)
	local shelf = roadY - 1.5

	if dd >= edge then
		local beachTop = sea + 2.5
		local drop = shelf - beachTop
		local cw = max(14, drop * 0.3)
		local t = (dd - edge) / cw
		if t < 1 then
			local rough = 5 * n:n2(x / 40, z / 40, 33) * sin(t * math.pi)
			return shelf + (beachTop - shelf) * smoothstep(0, 1, t) + rough, HINT.Cliff
		end
		local u = dd - edge - cw
		local h = beachTop - u * 0.09 - max(0, u - 60) * 0.25 + 2.5 * n:n2(x / 55, z / 55, 34)
		if h < sea - 70 then
			h = sea - 70
		end
		-- sea stacks
		local p = n:u2(x / 150, z / 150, 35) * n:u2(x / 700, z / 700, 38)
		if p > 0.6 and u > 25 then
			local v = min(1, (p - 0.6) / 0.25)
			h = max(h, sea - 10 + 125 * v ^ 0.55 * smoothstep(25, 90, u))
			return h, HINT.Cliff
		end
		if h < sea - 1 then
			return h, HINT.Seabed
		end
		return h, HINT.Beach
	end

	if dd > -hw then
		return shelf, HINT.None
	end

	-- land side climbs into hills and mountains
	local rise = -dd - hw
	local c = corr(ad, hw, 480, 0)
	local m = n:ridged2(x / 900, z / 900, 4, 36)
	local f = n:fbm2(x / 420, z / 420, 3, 37)
	return shelf + min(rise * 0.22, 45) + c * (270 * m ^ 1.3 + 50 * f), HINT.None
end

function Sampler:_lake(sec, x, z, s, d, ad, roadY)
	local n = self.noise
	local hw = self.hw
	local L = sec.lakeLevel
	local dd = sec.side * d
	local shore = hw + 14 + 30 * n:u1(s / 280, 51) + 8 * n:n2(x / 80, z / 80, 52)
	local shelf = roadY - 1.5

	if dd > shore then
		local u = dd - shore
		local width = sec.lakeWidth * (0.6 + 0.8 * n:u1(s / 900, 53))
		local depth = 24 + 16 * n:u2(x / 300, z / 300, 54)
		if u < width then
			local bowl = smoothstep(0, 70, u) * smoothstep(0, 140, width - u)
			local h = L + 2 - (depth + 2) * bowl
			-- little islands
			local isl = n:u2(x / 170, z / 170, 55)
			if isl > 0.8 and bowl > 0.3 then
				h = max(h, L - 4 + 44 * smoothstep(0.8, 1, isl))
			end
			if h < L then
				return h, HINT.Lakebed
			end
			return h, HINT.Beach
		end
		local far = u - width
		local c = smoothstep(0, 320, far)
		local m = n:ridged2(x / 800, z / 800, 4, 56)
		local f = n:fbm2(x / 400, z / 400, 3, 57)
		return L + 2 + min(far * 0.3, 40) + c * (130 * m + 40 * f), HINT.None
	end

	if dd > -hw then
		local t = smoothstep(hw, shore, dd)
		local h = shelf + (L + 2 - shelf) * t
		return h, t > 0.6 and HINT.Beach or HINT.None
	end

	local c = corr(ad, hw, 420, 0)
	local m = n:ridged2(x / 850, z / 850, 3, 58)
	local f = n:fbm2(x / 380, z / 380, 3, 59)
	return shelf + min((ad - hw) * 0.12, 30) + c * (90 * f + 80 * m), HINT.None
end

function Sampler:_riverValley(x, z, s, ad, E)
	local n = self.noise
	local vf = 115 + 60 * n:u1(s / 1100, 61)
	local t = smoothstep(vf, vf + 280, ad + 20 * n:n2(x / 200, z / 200, 62))
	local m = n:ridged2(x / 1000, z / 1000, 4, 63)
	local f = n:fbm2(x / 500, z / 500, 3, 64)
	return E + 2 * n:n2(x / 60, z / 60, 65) + t * (40 + 200 * m + 50 * f), HINT.None
end

function Sampler:regionHeight(sec, x, z, s, d, ad, E, roadY)
	local t = sec.type
	if t == "Meadow" then
		return self:_meadow(x, z, ad, E)
	elseif t == "Forest" then
		return self:_forest(x, z, ad, E)
	elseif t == "Mountains" then
		return self:_mountains(x, z, ad, E)
	elseif t == "Canyon" then
		return self:_canyon(sec, x, z, s, ad, E)
	elseif t == "Coast" then
		return self:_coast(sec, x, z, s, d, ad, roadY)
	elseif t == "Lake" then
		return self:_lake(sec, x, z, s, d, ad, roadY)
	else
		return self:_riverValley(x, z, s, ad, E)
	end
end

---------------------------------------------------------------------------
-- Road elevation target (before smoothing). Must not depend on the final
-- road elevation, which is computed from it.
---------------------------------------------------------------------------
function Sampler:_targetFor(sec, s, x, z, E)
	local t = sec.type
	if t == "Coast" then
		return max(self.sea + 34, self.sea + sec.shelf + 30 * self.noise:n1(s / 1800, 71))
	elseif t == "Lake" then
		return sec.lakeLevel + 7
	elseif t == "Canyon" then
		return E
	elseif t == "RiverValley" then
		return E + 3
	end
	return (self:regionHeight(sec, x, z, s, 0, 0, E, 0))
end

function Sampler:roadTarget(s: number, x: number, z: number): number
	local sections = self.sections
	local a, wa, b, wb = sections:weightsAt(s)
	local E = sections:regionalElevation(s)
	local t = wa * self:_targetFor(a, s, x, z, E)
	if b and wb > 0 then
		t += wb * self:_targetFor(b, s, x, z, E)
	end
	return t
end

---------------------------------------------------------------------------
-- Crossings (ridges, rivers, gorges)
---------------------------------------------------------------------------
-- Half width of the band around a crossing's centre line it can affect.
local CROSSING_REACH = { ridge = 2.6, river = 0, gorge = 0 }

function Sampler:_resolveCrossing(c)
	local road = self.road
	local x, z, h = road:xzAt(c.s)
	local fx, fz = cos(h), sin(h)
	local rx, rz = -fz, fx
	local ca, sa = cos(c.angle), sin(c.angle)
	local dirX, dirZ = rx * ca + fx * sa, rz * ca + fz * sa
	c.px, c.pz = x, z
	c.dirX, c.dirZ = dirX, dirZ
	c.nx, c.nz = -dirZ, dirX
	c.roadY = road:elevationAt(c.s)
	if c.kind == "ridge" then
		c.reach = c.width * 1.2 * CROSSING_REACH.ridge
	else
		c.level0 = c.roadY - c.clearance
		c.reach = c.channelHalf + c.meander * 2 + 420
	end
	c.resolved = true
end

--[[
	Crossings are straight bands in world space, so they are looked up by
	world X (the road's X increases with arc length, so crossings are sorted
	by X too) and rejected with a band test. Looking them up by arc length
	instead would clip them wherever the road runs close to north-south.
]]
-- Crossing candidates for every x in [xMin, xMax]. Chunk builders call
-- this once per chunk so each column skips the lookup.
function Sampler:beginArea(xMin: number, xMax: number)
	local road = self.road
	local reach = self.sections.MaxCrossingLength + 500
	road:ensureX(xMax + reach + 64)
	local list = self._areaBuf
	if not list then
		list = {}
		self._areaBuf = list
	end
	local count = self.sections:crossingsBetween(road:sAtX(xMin - reach), road:sAtX(xMax + reach), list)
	self._areaMin, self._areaMax, self._areaCount = xMin, xMax, count
end

function Sampler:endArea()
	self._areaMin, self._areaMax = nil, nil
end

function Sampler:_applyCrossings(x, z, h, water, hint)
	local buf, count
	local areaMin = self._areaMin
	if areaMin and x >= areaMin and x <= self._areaMax then
		buf, count = self._areaBuf, self._areaCount
	else
		local road = self.road
		local reach = self.sections.MaxCrossingLength + 500
		road:ensureX(x + reach + 64)
		buf = self._crossBuf
		count = self.sections:crossingsBetween(road:sAtX(x - reach), road:sAtX(x + reach), buf)
	end
	if count == 0 then
		return h, water, hint
	end
	local n = self.noise
	for i = 1, count do
		local c = buf[i]
		if not c.resolved then
			self:_resolveCrossing(c)
		end
		local dx, dz = x - c.px, z - c.pz
		local t = dx * c.dirX + dz * c.dirZ
		local at = abs(t)
		if at >= c.length then
			continue
		end
		local u = dx * c.nx + dz * c.nz
		if abs(u) > c.reach then
			continue
		end
		if c.kind == "ridge" then
			local fade = 1 - smoothstep(c.length * 0.45, c.length, at)
			if fade > 0 then
				local wv = c.width * (0.8 + 0.4 * n:u1(t / 400, 91))
				local q = u / wv
				local bump = exp(-q * q)
				if bump > 0.01 then
					local peak = c.roadY + c.height * (0.75 + 0.5 * n:u1(t / 500, 92)) + 45 * n:ridged2(x / 220, z / 220, 2, 93)
					local lift = peak - h
					if lift > 0 then
						h += lift * bump * fade
					end
				end
			end
		else
			local fade = 1 - smoothstep(c.length * 0.5, c.length, at)
			if fade > 0 then
				local mu = u - c.meander * 2 * n:n1(t / 280, 94) * smoothstep(40, 260, at)
				local au = abs(mu)
				local level = c.level0 - t * c.slope * c.flow
				local ch = c.channelHalf
				local hr
				if au < ch then
					local q = au / ch
					hr = level - c.depth + q * q * (c.depth - 0.5)
				else
					hr = level - 0.5 + (au - ch) * c.valleySlope
				end
				hr += (1 - fade) * 400
				if hr < h + 6 then
					local before = h
					h = smin(h, hr, 4)
					if au < ch + 2 and before >= level - 1.5 then
						if level > water then
							water = level
						end
						hint = HINT.Riverbed
					end
				end
			end
		end
	end
	return h, water, hint
end

---------------------------------------------------------------------------
-- Rivers running alongside the road (RiverValley, Canyon)
---------------------------------------------------------------------------
-- Lateral offset (signed d) of the river centre and its half width.
function Sampler:riverOffset(sec, s: number, weight: number): (number, number)
	local n = self.noise
	local hw = self.hw
	local off, half
	if sec.type == "RiverValley" then
		half = sec.channelHalf
		local A = hw + half + 22 + 40 * n:u1(s / 600, 81)
		local sw = math.tanh(6 * n:n1(s / 1500, 82))
		off = A * sw
	else
		half = 11
		local fh = self:_canyonShape(s)
		local floorHalf = sec.floorHalf * fh
		local room = max(0, floorHalf - hw - 12 - 2 * half - 8)
		off = sec.riverSide * (hw + 12 + half + room * n:u1(s / 700, 83))
	end
	-- near the ends of the section the river swings away and leaves
	local away = 1 - weight
	off += (off >= 0 and 1 or -1) * away * away * 900
	return off, half
end

function Sampler:_applyRiver(sec, weight, s, d, roadY, h, water, hint)
	if weight < 0.02 then
		return h, water, hint
	end
	local off, half = self:riverOffset(sec, s, weight)
	local u = abs(d - off)
	local level = roadY - (sec.type == "Canyon" and 4 or 6)
	local depth = 4
	-- channel, a gently sloping bank, then a steep rise so the carve stays
	-- a river and does not eat into canyon walls or valley sides
	local hr
	local bank = 14
	if u < half then
		local q = u / half
		hr = level - depth + q * q * (depth - 0.5)
	elseif u < half + bank then
		hr = level - 0.5 + (u - half) * 0.45
	else
		hr = level - 0.5 + bank * 0.45 + (u - half - bank) * 3
	end
	-- as the river swings away it fades out instead of cutting a trench
	-- across the far field
	local strength = smoothstep(0.02, 0.3, weight) * (1 - smoothstep(260, 480, abs(off)))
	if strength <= 0 then
		return h, water, hint
	end
	if hr < h then
		local before = h
		local carved = smin(h, hr, 3)
		h = before + (carved - before) * strength
		if u < half + 2 and before >= level - 1.5 and strength > 0.5 then
			if level > water then
				water = level
			end
			hint = HINT.Riverbed
		end
	end
	return h, water, hint
end

---------------------------------------------------------------------------
-- preRoad: everything except the road corridor
---------------------------------------------------------------------------
-- Returns height, water level (-inf if dry), hint, dominant section.
function Sampler:preRoad(x: number, z: number, s: number, d: number, roadY: number)
	local n = self.noise
	local sections = self.sections
	local ad = abs(d)

	-- Region blending coordinate. Near the road it is the arc length. Far
	-- away, road-relative coordinates get compressed wherever the road bends,
	-- so blend over to the arc length at the same world X, plus a noisy
	-- offset so region borders are not straight lines.
	--
	-- The nearest road point also jumps wherever two stretches of road are
	-- equally close (inside bends), so everything road-relative switches to
	-- that smooth coordinate far out as well.
	local sj = s
	if ad > 100 then
		local wFar = smoothstep(350, 1100, ad)
		if wFar > 0 then
			s += (self.road:sAtX(x) - s) * wFar
			roadY = self.road:elevationAt(s)
		end
		sj = s + 520 * n:fbm2(x / 700, z / 700, 2, 99) * smoothstep(100, 700, ad)
	end
	local a, wa, b, wb = sections:weightsAt(sj)
	local E = sections:regionalElevation(sj)

	local h, hint = self:regionHeight(a, x, z, s, d, ad, E, roadY)
	local dom = a
	if b and wb > 0.001 then
		local h2, hint2 = self:regionHeight(b, x, z, s, d, ad, E, roadY)
		h = h * wa + h2 * wb
		if wb > wa then
			hint = hint2
			dom = b
		end
	end

	local water = NEG_INF
	h, water, hint = self:_applyCrossings(x, z, h, water, hint)

	-- rivers and lakes are tied to the road, so use the true arc length
	local ra, rwa, rb, rwb = a, wa, b, wb
	if sj ~= s then
		ra, rwa, rb, rwb = sections:weightsAt(s)
	end
	if ra.type == "RiverValley" or ra.type == "Canyon" then
		h, water, hint = self:_applyRiver(ra, rwa, s, d, roadY, h, water, hint)
	end
	if rb and (rb.type == "RiverValley" or rb.type == "Canyon") then
		h, water, hint = self:_applyRiver(rb, rwb, s, d, roadY, h, water, hint)
	end

	-- lakes: only on the lake side of the road
	if ra.type == "Lake" and rwa > 0.3 and ra.side * d > self.hw and h < ra.lakeLevel then
		water = max(water, ra.lakeLevel)
	end
	if rb and rb.type == "Lake" and rwb > 0.3 and rb.side * d > self.hw and h < rb.lakeLevel then
		water = max(water, rb.lakeLevel)
	end

	if h < self.sea then
		water = max(water, self.sea)
	end
	return h, water, hint, dom
end

---------------------------------------------------------------------------
-- Full column, including the road corridor.
---------------------------------------------------------------------------
--[[
	Returns:
	  h        ground surface height
	  vb, vt   tunnel void bottom/top (vb == vt when there is no void)
	  water    water surface height (-inf if dry)
	  s, d     road coordinates
	  typeIdx  dominant region type index
	  hint     surface hint
	  flags    column flags
	  ys       road surface height at this lateral position
]]
function Sampler:column(x: number, z: number)
	local road = self.road
	local cfg = self.config
	local hw = self.hw
	local s, d, k, t = road:project(x, z)
	-- extend on demand, never clamp: the result must not depend on how much
	-- road happens to be computed already, or neighbouring chunks built at
	-- different times would not line up
	road:ensureY(k + 2)
	local roadY = road:elevationAtIndex(k, t)
	local bank = road:bankAtIndex(k, t)
	local kn = t < 0.5 and k or k + 1

	local pre, water, hint, dom = self:preRoad(x, z, s, d, roadY)
	local ad = abs(d)
	local flags = 0
	local h = pre
	local vb, vt = 0, 0

	local dc = clamp(d, -hw, hw)
	local ys = roadY - sin(bank) * dc

	local inner = hw + 3
	if ad < inner + 250 then
		road:ensureFlags(kn)
		local tunnel = road:isTunnel(kn)
		local bridge = not tunnel and road:isBridge(kn)
		-- well below the road slab (smooth terrain can bulge a little above
		-- its nominal height), also under the edges: a 4-stud voxel column
		-- centred just outside the road still reaches under it
		local target = ys - (ad <= hw + 1 and 1.5 or (ad <= hw + 3 and 1.1 or 0.8))
		local diff = pre - target
		local tc = cfg.Tunnel
		local tunnelHalf = hw + 4

		if tunnel then
			-- cut-and-cover: always keep enough rock over the tunnel lining
			local coverMin = ys + tc.CeilingHeight + 10 - max(0, ad - (hw + 8)) * 0.9
			if pre < coverMin then
				h = coverMin
			end
			if ad < tunnelHalf then
				local q = ad / tunnelHalf
				local ceiling = ys + tc.WallHeight + 1 + (tc.CeilingHeight - tc.WallHeight + 1) * sqrt(max(0, 1 - q * q))
				vb, vt = ys - 1.5, ceiling
				flags += FLAG.Tunnel
				if water > vb then
					water = NEG_INF
				end
			end
		elseif bridge and diff < 0 then
			-- natural ground under the bridge, only pushed down right under the deck
			local under = ys - cfg.Bridge.Clearance
			if pre > under then
				h = pre + (under - pre) * (1 - smoothstep(hw + 2, hw + 24, ad))
			end
			flags += FLAG.Bridge
		else
			local slope
			if diff > 0 then
				-- rock cuts in rocky regions are steeper
				local ty = dom.type
				slope = (ty == "Mountains" or ty == "Canyon" or ty == "Coast") and 0.6 or 0.9
			else
				slope = 1.5
			end
			-- not steeper than 4-stud voxels can show cleanly on a diagonal
			local bw = clamp(abs(diff) * slope, 7, 240)
			local tt = smoothstep(inner, inner + bw, ad)
			h = target + diff * tt
			if tt < 0.98 and abs(diff) > 3 then
				flags += diff > 0 and FLAG.Cut or FLAG.Fill
			end
			if water > h and ad < inner + 4 then
				-- never flood the road itself
				water = NEG_INF
			end
		end
		if ad <= hw + 0.5 and not bridge and not tunnel then
			flags += FLAG.RoadBed
		elseif ad <= hw + 4 and abs(h - ys) < 2 then
			flags += FLAG.Shoulder
		end
	end

	return h, vb, vt, water, s, d, TYPE_INDEX[dom.type], hint, flags, ys
end

-- Ground height only (for props like bridge piers).
function Sampler:groundAt(x: number, z: number): (number, number)
	local h, _, _, water = self:column(x, z)
	return h, water
end

return Sampler
