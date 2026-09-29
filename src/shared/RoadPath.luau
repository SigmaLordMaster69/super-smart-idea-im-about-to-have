--[[
	RoadPath
	--------
	One infinite, deterministic road, stored as samples every
	Config.Road.SampleSpacing studs of arc length.

	The heading always stays within +-MaxHeadingDrift of +X, so world X keeps
	increasing along the road. That gives three guarantees:
	  * the road never crosses itself,
	  * the samples are sorted by X, so a point can be matched to nearby
	    samples with a binary search,
	  * far from the road, "which side am I on" is just z vs. the road's z at
	    the same x.

	Samples are computed lazily in stages, each stage needing some look-ahead
	from the previous one:
	  XZ      heading + position                    (noise only)
	  Target  raw elevation the terrain would like  (TerrainSampler)
	  Y       gaussian-smoothed, grade-limited elevation, curvature, bank
	  Feat    terrain around the finished road, giving raw tunnel / bridge /
	          guard rail flags
	  Flags   raw flags cleaned into runs (minimum length, merged gaps, padding)
]]

local MathUtil = require(script.Parent.MathUtil)

local clamp = MathUtil.clamp
local cos, sin, sqrt, abs, exp, floor, max, min = math.cos, math.sin, math.sqrt, math.abs, math.exp, math.floor, math.max, math.min

local RoadPath = {}
RoadPath.__index = RoadPath

-- Streaming run detector. Pushed raw booleans one index at a time; writes
-- true into `out` for every index covered by a qualifying run.
-- `settled` is the highest index whose value can no longer change.
local function newRunDetector(minLen: number, maxGap: number, pad: number, out)
	local det = { runStart = nil, runLast = 0, settled = 0, marked = 0 }

	local function mark(a, b)
		for j = max(a, 1), b do
			out[j] = true
		end
		if b > det.marked then
			det.marked = b
		end
	end

	function det.push(k: number, raw: boolean)
		if raw then
			if det.runStart == nil or k - det.runLast - 1 > maxGap then
				det.runStart = k
			end
			det.runLast = k
			if det.runLast - det.runStart + 1 >= minLen then
				mark(max(det.marked + 1, det.runStart - pad), det.runLast)
				det.settled = max(det.settled, det.runLast)
			else
				det.settled = max(det.settled, det.runStart - pad - 1)
			end
		else
			if det.runStart ~= nil then
				if k - det.runLast > maxGap then
					if det.runLast - det.runStart + 1 >= minLen then
						mark(det.runLast + 1, det.runLast + pad)
					end
					det.runStart = nil
					det.settled = max(det.settled, k - pad)
				end
				-- still inside a gap: settled stays where it is
			else
				det.settled = max(det.settled, k - pad)
			end
		end
	end

	return det
end

function RoadPath.new(config, noise, sections)
	local self = setmetatable({}, RoadPath)
	local rc = config.Road
	self.config = config
	self.noise = noise
	self.sections = sections
	self.sampler = nil -- set by World once the sampler exists

	self.step = rc.SampleSpacing
	self.halfWidth = rc.HalfWidth
	self.minRadius = rc.MinRadius
	self.maxDrift = rc.MaxHeadingDrift
	self.projRadius = config.Terrain.ProjectionRadius -- max search distance

	-- sample arrays (1-based; sample k sits at s = (k - 1) * step)
	self.px, self.pz, self.hd = {}, {}, {}
	self.tgt = {}
	self.y, self.curv, self.bank = {}, {}, {}
	self.tunnel, self.bridge, self.railL, self.railR = {}, {}, {}, {}
	self.nXZ, self.nTgt, self.nY, self.nFeat = 0, 0, 0, 0

	-- gaussian kernel for elevation smoothing
	local sigma = rc.ElevationSmoothing / self.step
	local W = math.ceil(sigma * 2.6)
	local kernel = {}
	local total = 0
	for j = -W, W do
		local w = exp(-0.5 * (j / sigma) ^ 2)
		kernel[j + W + 1] = w
		total += w
	end
	for i = 1, #kernel do
		kernel[i] /= total
	end
	self.kernel, self.kernelHalf = kernel, W


	local t, b, g = config.Tunnel, config.Bridge, config.GuardRail
	self.detTunnel = newRunDetector(t.MinLength, t.MergeGap, 0, self.tunnel)
	self.detBridge = newRunDetector(b.MinLength, b.MergeGap, b.Pad, self.bridge)
	self.detRailL = newRunDetector(g.MinLength, g.MergeGap, g.Pad, self.railL)
	self.detRailR = newRunDetector(g.MinLength, g.MergeGap, g.Pad, self.railR)
	return self
end

---------------------------------------------------------------------------
-- Stage 1: horizontal path
---------------------------------------------------------------------------
function RoadPath:_targetHeading(s: number): number
	local n = self.noise
	local drift = 0.95 * n:n1(s / 9000, 11)
	local wander = 1.3 * n:n1(s / 1400, 12) + 1.15 * n:n1(s / 560, 13) + 0.6 * n:n1(s / 250, 14)
	return drift + self.sections:twistAt(s) * wander * 0.9
end

function RoadPath:_ensureXZ(n: number)
	local px, pz, hd = self.px, self.pz, self.hd
	local step = self.step
	local maxTurn = step / self.minRadius
	local maxDrift = self.maxDrift
	for k = self.nXZ + 1, n do
		local s = (k - 1) * step
		local target = self:_targetHeading(s)
		if k == 1 then
			hd[1] = clamp(target, -maxDrift, maxDrift)
			px[1], pz[1] = 0, 0
		else
			local prev = hd[k - 1]
			local h = prev + clamp(target - prev, -maxTurn, maxTurn)
			h = clamp(h, -maxDrift, maxDrift)
			local mid = (prev + h) * 0.5
			px[k] = px[k - 1] + cos(mid) * step
			pz[k] = pz[k - 1] + sin(mid) * step
			hd[k] = h
		end
	end
	if n > self.nXZ then
		self.nXZ = n
	end
end

-- Make sure the path reaches at least world X = x.
function RoadPath:ensureX(x: number)
	while self.nXZ == 0 or self.px[self.nXZ] < x do
		self:_ensureXZ(self.nXZ + 256)
	end
end

---------------------------------------------------------------------------
-- Stage 2: elevation target
---------------------------------------------------------------------------
function RoadPath:_ensureTarget(n: number)
	if n <= self.nTgt then
		return
	end
	self:_ensureXZ(n)
	local px, pz, tgt, step = self.px, self.pz, self.tgt, self.step
	local sampler = self.sampler
	for k = self.nTgt + 1, n do
		tgt[k] = sampler:roadTarget((k - 1) * step, px[k], pz[k])
	end
	self.nTgt = n
end

---------------------------------------------------------------------------
-- Stage 3: smoothed elevation, curvature, bank
---------------------------------------------------------------------------
function RoadPath:_ensureY(n: number)
	if n <= self.nY then
		return
	end
	local W = self.kernelHalf
	self:_ensureTarget(n + W + 12)
	local tgt, y, hd, curv, bank = self.tgt, self.y, self.hd, self.curv, self.bank
	local kernel = self.kernel
	local rc = self.config.Road
	local step = self.step
	local maxRise = rc.MaxGrade * step
	local minY = self.config.SeaLevel + rc.MinElevation
	local bankK, maxBank = rc.BankPerCurvature, rc.MaxBank

	for k = self.nY + 1, n do
		local acc = 0
		for j = -W, W do
			local idx = k + j
			if idx < 1 then
				idx = 1
			end
			acc += tgt[idx] * kernel[j + W + 1]
		end
		if acc < minY then
			acc = minY
		end
		if k > 1 then
			local prev = y[k - 1]
			acc = clamp(acc, prev - maxRise, prev + maxRise)
		end
		y[k] = acc

		-- curvature over +-8 samples, bank from curvature
		local a, b = max(1, k - 8), k + 8
		local c = (hd[b] - hd[a]) / ((b - a) * step)
		curv[k] = c
		bank[k] = clamp(c * bankK, -maxBank, maxBank)
	end
	self.nY = n
end

---------------------------------------------------------------------------
-- Stage 4 + 5: terrain features along the road, then flags
---------------------------------------------------------------------------
function RoadPath:_extendFeat(n: number)
	-- anything farther ahead (crossings) is pulled in on demand
	self:_ensureY(n + 4)
	local sampler = self.sampler
	local px, pz, hd, y = self.px, self.pz, self.hd, self.y
	local step, hw = self.step, self.halfWidth
	local cover = self.config.Tunnel.CoverThreshold
	local gapT = self.config.Bridge.GapThreshold
	local drop = self.config.GuardRail.DropThreshold
	local detT, detB, detL, detR = self.detTunnel, self.detBridge, self.detRailL, self.detRailR

	for k = self.nFeat + 1, n do
		local s = (k - 1) * step
		local x, z, ry = px[k], pz[k], y[k]
		local h = hd[k]
		local rx, rz = -sin(h), cos(h)

		local hc, wc = sampler:preRoad(x, z, s, 0, ry)
		local hl, wl = sampler:preRoad(x - rx * hw, z - rz * hw, s, -hw, ry)
		local hr, wr = sampler:preRoad(x + rx * hw, z + rz * hw, s, hw, ry)

		local lowest = min(hc, hl, hr)
		local highest = max(hc, hl, hr)
		local wet = wc > hc or wl > hl or wr > hr
		local rawTunnel = lowest - ry > cover
		local rawBridge = not rawTunnel and (ry - highest > gapT or wet)

		local o1, o2 = hw + 14, hw + 30
		local l1, lw1 = sampler:preRoad(x - rx * o1, z - rz * o1, s, -o1, ry)
		local r1, rw1 = sampler:preRoad(x + rx * o1, z + rz * o1, s, o1, ry)
		local l2, lw2 = sampler:preRoad(x - rx * o2, z - rz * o2, s, -o2, ry)
		local r2, rw2 = sampler:preRoad(x + rx * o2, z + rz * o2, s, o2, ry)
		local railLeft = l1 < ry - drop or l2 < ry - drop - 10 or lw1 > l1 or lw2 > l2
		local railRight = r1 < ry - drop or r2 < ry - drop - 10 or rw1 > r1 or rw2 > r2

		detT.push(k, rawTunnel)
		detB.push(k, rawBridge)
		detL.push(k, railLeft and not rawTunnel)
		detR.push(k, railRight and not rawTunnel)
	end
	self.nFeat = n
end

function RoadPath:_settled(): number
	return min(self.detTunnel.settled, self.detBridge.settled, self.detRailL.settled, self.detRailR.settled)
end

-- Make sure every flag up to sample k is final.
function RoadPath:ensureFlags(k: number)
	while self:_settled() < k do
		self:_extendFeat(self.nFeat + 64)
	end
end

-- Make sure elevation is known up to sample k.
function RoadPath:ensureY(k: number)
	self:_ensureY(k)
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
function RoadPath:sToIndex(s: number): (number, number)
	local f = s / self.step + 1
	local k = floor(f)
	if k < 1 then
		return 1, 0
	end
	return k, f - k
end

function RoadPath:indexToS(k: number): number
	return (k - 1) * self.step
end

-- Largest sample index whose X is <= x (1 if x is before the start).
function RoadPath:indexAtX(x: number): number
	local px = self.px
	local lo, hi = 1, self.nXZ
	if px[1] > x then
		return 1
	end
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if px[mid] <= x then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

-- Arc length of the road point that has world X = x. Smooth and cheap; used
-- to key far-away terrain to the road without projection artefacts.
function RoadPath:sAtX(x: number): number
	local px = self.px
	if x <= px[1] then
		return (x - px[1]) / cos(self.hd[1])
	end
	local k0 = self:indexAtX(x)
	if k0 >= self.nXZ then
		k0 = self.nXZ - 1
	end
	local span = px[k0 + 1] - px[k0]
	local t0 = span > 0 and clamp((x - px[k0]) / span, 0, 1) or 0
	return (k0 - 1 + t0) * self.step
end

-- Elevation at a fractional sample position. Needs nY to cover k + 1.
function RoadPath:elevationAtIndex(k: number, t: number): number
	local y = self.y
	local n = self.nY
	if k >= n then
		return y[n]
	end
	return y[k] + (y[k + 1] - y[k]) * t
end

function RoadPath:elevationAt(s: number): number
	local k, t = self:sToIndex(s)
	self:_ensureY(k + 2)
	return self:elevationAtIndex(k, t)
end

function RoadPath:bankAtIndex(k: number, t: number): number
	local b = self.bank
	local n = self.nY
	if k >= n then
		return b[n]
	end
	return b[k] + (b[k + 1] - b[k]) * t
end

-- Tunnels win where the padding of a bridge overlaps one.
function RoadPath:isTunnel(k: number): boolean
	return self.tunnel[k] == true
end

function RoadPath:isBridge(k: number): boolean
	return self.bridge[k] == true and self.tunnel[k] ~= true
end

-- side: -1 left, +1 right
function RoadPath:hasRail(k: number, side: number): boolean
	if self.tunnel[k] or self.bridge[k] then
		return false
	end
	if side < 0 then
		return self.railL[k] == true
	end
	return self.railR[k] == true
end

function RoadPath:curvature(k: number): number
	return self.curv[k] or 0
end

-- Heading/position of the horizontal path at arc length s.
function RoadPath:xzAt(s: number): (number, number, number)
	local k, t = self:sToIndex(s)
	self:_ensureXZ(k + 2)
	local px, pz, hd = self.px, self.pz, self.hd
	if s < 0 then
		local h = hd[1]
		return px[1] + cos(h) * s, pz[1] + sin(h) * s, h
	end
	return px[k] + (px[k + 1] - px[k]) * t, pz[k] + (pz[k + 1] - pz[k]) * t, hd[k] + (hd[k + 1] - hd[k]) * t
end

--[[
	Full 3D frame of the road surface at arc length s:
	  position (centre of the road surface), forward, right, up.
	Forward follows the grade, right/up include the bank.
]]
function RoadPath:frameAt(s: number)
	local k, t = self:sToIndex(s)
	self:_ensureY(k + 3)
	local x, z, h = self:xzAt(s)
	local yy = self:elevationAtIndex(k, t)
	local y = self.y
	local ka, kb = max(1, k - 1), k + 2
	local grade = (y[kb] - y[ka]) / ((kb - ka) * self.step)
	local b = self:bankAtIndex(k, t)
	return self:_frame(x, yy, z, h, grade, b)
end

-- Frame at an exact sample index (faster, no interpolation).
function RoadPath:frameAtIndex(k: number)
	self:_ensureY(k + 2)
	local y = self.y
	local ka, kb = max(1, k - 1), k + 1
	local grade = (y[kb] - y[ka]) / ((kb - ka) * self.step)
	return self:_frame(self.px[k], y[k], self.pz[k], self.hd[k], grade, self.bank[k])
end

function RoadPath:_frame(x, yy, z, h, grade, b)
	local ch, sh = cos(h), sin(h)
	-- forward with pitch
	local inv = 1 / sqrt(1 + grade * grade)
	local fx, fy, fz = ch * inv, grade * inv, sh * inv
	-- horizontal right
	local r0x, r0z = -sh, ch
	-- up0 = right0 x forward
	local u0x = 0 * fz - r0z * fy
	local u0y = r0z * fx - r0x * fz
	local u0z = r0x * fy - 0 * fx
	local cb, sb = cos(b), sin(b)
	local rx, ry, rz = r0x * cb - u0x * sb, -u0y * sb, r0z * cb - u0z * sb
	local ux, uy, uz = u0x * cb + r0x * sb, u0y * cb, u0z * cb + r0z * sb
	return Vector3.new(x, yy, z), Vector3.new(fx, fy, fz), Vector3.new(rx, ry, rz), Vector3.new(ux, uy, uz)
end

--[[
	Project a world point onto the road.
	Returns s (arc length), d (signed lateral distance, + is to the right of
	travel), k and t (segment index and fraction).

	Exact nearest point on the polyline. The search window comes from a
	bound: the road point with the same X is |z - zRoad(x)| away, so the
	nearest point cannot be farther than that in X either. Near the road the
	window is tiny; far away a coarse-to-fine scan keeps it cheap.
]]
function RoadPath:project(x: number, z: number): (number, number, number, number)
	local R = self.projRadius
	-- generous margin so the search window never touches the end of the
	-- computed path (keeps results independent of how much is computed)
	self:ensureX(x + R + 64)
	local px, pz = self.px, self.pz
	local step = self.step
	local n = self.nXZ

	-- before the road starts: straight extension backwards
	if x < px[1] + 1 then
		local h = self.hd[1]
		local dx, dz = x - px[1], z - pz[1]
		local s = dx * cos(h) + dz * sin(h)
		if s <= 0 then
			return s, -dx * sin(h) + dz * cos(h), 1, 0
		end
	end

	-- upper bound on the distance: the road point at the same x
	local k0 = self:indexAtX(x)
	if k0 >= n then
		k0 = n - 1
	end
	local span = px[k0 + 1] - px[k0]
	local t0 = span > 0 and clamp((x - px[k0]) / span, 0, 1) or 0
	local bound = abs(z - (pz[k0] + (pz[k0 + 1] - pz[k0]) * t0)) + step
	if bound > R then
		bound = R
	end
	local kLo = self:indexAtX(x - bound)
	local kHi = min(n - 1, self:indexAtX(x + bound) + 1)

	-- coarse to fine scan over sample points
	local stride = max(1, (kHi - kLo) // 24)
	local bestK, bestD2 = kLo, math.huge
	for k = kLo, kHi, stride do
		local dx, dz = x - px[k], z - pz[k]
		local d2 = dx * dx + dz * dz
		if d2 < bestD2 then
			bestD2, bestK = d2, k
		end
	end
	while stride > 1 do
		local fine = max(1, stride // 4)
		for k = max(kLo, bestK - stride), min(kHi, bestK + stride), fine do
			local dx, dz = x - px[k], z - pz[k]
			local d2 = dx * dx + dz * dz
			if d2 < bestD2 then
				bestD2, bestK = d2, k
			end
		end
		stride = fine
	end

	-- exact projection onto the two segments touching the best sample
	local sE, dE, kE, tE = 0, 0, bestK, 0
	local bestSeg = math.huge
	for k = max(1, bestK - 1), min(n - 1, bestK) do
		local ax, az = px[k], pz[k]
		local vx, vz = px[k + 1] - ax, pz[k + 1] - az
		local len2 = vx * vx + vz * vz
		local t = ((x - ax) * vx + (z - az) * vz) / len2
		if t < 0 then
			t = 0
		elseif t > 1 then
			t = 1
		end
		local ex, ez = x - (ax + vx * t), z - (az + vz * t)
		local dist2 = ex * ex + ez * ez
		if dist2 < bestSeg then
			bestSeg = dist2
			sE = (k - 1 + t) * step
			dE = (ex * -vz + ez * vx) / sqrt(len2)
			kE, tE = k, t
		end
	end
	return sE, dE, kE, tE
end

return RoadPath
