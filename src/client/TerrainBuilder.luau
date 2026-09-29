--!native
--[[
	TerrainBuilder
	--------------
	Turns one chunk of the height model into smooth-terrain voxels.

	Every voxel column gets a solid shell from a little below its lowest
	neighbour up to its surface, so cliffs are closed without filling whole
	mountains. Tunnel voids are cut out of the shell, and water fills from
	the ground up to the water level.

	Work is split in two so it can run on a parallel worker:
	  compute(...)  pure Luau: samples the height model and fills voxel arrays
	  write(job)    engine calls: Terrain:WriteVoxels, one per chunk quadrant

	The per-column data is kept on the chunk so the decorator can place
	trees without sampling the terrain again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("InfiniteRoad")
local TerrainSampler = require(Shared.TerrainSampler)

local HINT = TerrainSampler.Hint
local FLAG = TerrainSampler.Flag
local T = TerrainSampler.TypeIndex

-- Enum lookups go through a metamethod and are slow in hot loops, so every
-- material used here is fetched once.
local M = Enum.Material
local AIR, WATER, ICE, SNOW = M.Air, M.Water, M.Ice, M.Snow
local ASPHALT, GROUND, MUD, SAND, ROCK = M.Asphalt, M.Ground, M.Mud, M.Sand, M.Rock
local GRASS, LEAFY, SLATE, BASALT = M.Grass, M.LeafyGrass, M.Slate, M.Basalt
local SANDSTONE, LIMESTONE, SALT = M.Sandstone, M.Limestone, M.Salt

local floor, ceil, min, max, sqrt, abs = math.floor, math.ceil, math.min, math.max, math.sqrt, math.abs
local btest = bit32.btest

local TerrainBuilder = {}
TerrainBuilder.__index = TerrainBuilder

-- canyon rock layers, bottom to top, repeating every #STRATA * 11 studs
local STRATA = { SANDSTONE, LIMESTONE, SANDSTONE, SALT, SANDSTONE, LIMESTONE }
local STRATA_HEIGHT = 11

-- Columns are sampled on three nested lattices (16, 8 and 4 studs). A node
-- is interpolated from the coarser lattice when every coarser node around
-- it is at least this far from the road (and has no tunnel); otherwise it
-- is sampled exactly.
local FAR_8 = 650 -- 8-stud nodes may come from the 16-stud lattice
local FAR_4 = 300 -- 4-stud columns may come from the 8-stud lattice

-- voxel writes happen per quadrant of this many columns
local PIECE = 16

-- solid shell below each column's lowest neighbour (studs)
local SHELL = 5

local mnoise = math.noise

TerrainBuilder.DefaultSeason = { snowGround = false, frozen = false, snowLine = 0 }

function TerrainBuilder.new(world, config, terrain)
	local self = setmetatable({}, TerrainBuilder)
	self.world = world
	self.config = config
	self.terrain = terrain
	self.size = config.World.ChunkSize
	self.n = self.size // 4
	self.snowLine = config.Terrain.SnowLine
	self.sea = config.SeaLevel
	self.season = TerrainBuilder.DefaultSeason
	self._matRows, self._occRows = {}, {}
	return self
end

-- season: { snowGround: bool, frozen: bool, snowLine: number (offset) }
function TerrainBuilder:setSeason(season)
	self.season = season or TerrainBuilder.DefaultSeason
end

local function strata(y: number, jitter: number)
	local band = floor((y + jitter + 4000) / STRATA_HEIGHT) % #STRATA
	return STRATA[band + 1]
end

-- surface material for one column
function TerrainBuilder:_surface(ty, hint, flags, slope, h, water, v)
	if btest(flags, FLAG.RoadBed) then
		return ASPHALT
	end
	local season = self.season
	if btest(flags, FLAG.Shoulder) then
		return season.snowGround and SNOW or GROUND
	end
	if water > h + 0.3 then
		if hint == HINT.Riverbed then
			return v > 0 and MUD or GROUND
		elseif hint == HINT.Seabed or hint == HINT.Beach then
			return water - h > 30 and ROCK or SAND
		elseif hint == HINT.Lakebed then
			return water - h > 8 and MUD or SAND
		end
		return MUD
	end
	if hint == HINT.Beach and slope < 0.7 then
		return SAND
	end
	if hint == HINT.Cliff then
		if slope > 0.75 then
			return h < self.sea + 14 and BASALT or SLATE
		end
		if h < self.sea + 5 then
			return SAND
		end
		return (season.snowGround and slope < 0.6) and SNOW or GRASS
	end
	if ty == T.Canyon then
		if hint == HINT.CanyonFloor and slope < 0.6 then
			return v > 0.35 and SAND or GROUND
		end
		if slope > 0.55 then
			return strata(h, v * 5)
		end
		return v > 0.3 and SANDSTONE or GROUND
	end
	if btest(flags, FLAG.Cut) and slope > 0.55 then
		return (ty == T.Coast and SLATE) or ROCK
	end
	local snowGround = season.snowGround and slope < 0.85
	if btest(flags, FLAG.Fill) then
		if snowGround then
			return SNOW
		end
		return slope > 0.55 and GROUND or GRASS
	end
	local snow = self.snowLine + season.snowLine + v * 30
	if h > snow then
		return slope < 1.1 and SNOW or ROCK
	end
	if slope > 1.0 then
		return (ty == T.Coast and SLATE) or ROCK
	end
	if snowGround then
		return SNOW
	end
	if slope > 0.62 then
		if ty == T.Mountains or h > snow - 60 then
			return v > 0 and ROCK or GROUND
		end
		return GROUND
	end
	if ty == T.Forest then
		return v > -0.25 and LEAFY or GRASS
	elseif ty == T.Mountains and h > snow - 70 then
		return v > 0.1 and GROUND or GRASS
	elseif ty == T.Meadow then
		return v > 0.45 and LEAFY or GRASS
	end
	return v > 0.3 and LEAFY or GRASS
end

-- material deep inside the shell (exposed on cliff faces and cuts)
function TerrainBuilder:_deep(ty, hint, y, v)
	if ty == T.Canyon then
		return strata(y, v * 5)
	elseif ty == T.Coast then
		return y < self.sea + 12 and BASALT or SLATE
	end
	return ROCK
end

local function takeRow(pool, fill)
	local n = #pool
	if n > 0 then
		local r = pool[n]
		pool[n] = nil
		for i = 1, PIECE do
			r[i] = fill
		end
		return r
	end
	return table.create(PIECE, fill)
end

--[[
	Samples chunk (cx, cz) and fills the voxel arrays. Pure Luau apart from
	reading Enum values, so it is safe to run in parallel.
	`origin` is the floating-origin offset (world minus Roblox coordinates).
	`yieldFn` (optional) is called regularly so the caller can spread work.
	Returns a job: { pieces = { {region, mats, occs}, ... }, data = columns }.
]]
function TerrainBuilder:compute(cx: number, cz: number, origin: Vector3, yieldFn)
	yieldFn = yieldFn or function() end
	local world = self.world
	local sampler = world.sampler
	local size, N = self.size, self.n
	local x0, z0 = cx * size, cz * size
	local noiseZ = world.noise.base + 101 * 3.7131 -- channel 101 of Noise:n2

	world:prepareForX(x0 - 8, x0 + size + 8, 0)
	sampler:beginArea(x0 - 16, x0 + size + 32)

	--[[
		Three nested lattices. Level 1 samples every 16 studs. Level 2 fills
		the 8-stud lattice, interpolating nodes whose four level-1 neighbours
		are all very far from the road. Level 3 fills every 4-stud column the
		same way from level 2. Near the road everything is sampled exactly.
		The lattices are aligned to the world grid, so a column on a shared
		border gets the same value from both chunks.

		The grid runs past the chunk (indices 0 .. N + 4) so every column has
		lattice neighbours to interpolate from. Columns 1 .. N are the chunk;
		0 and N + 1 are borders used for slopes.
	]]
	local G = N + 5
	local count = G * G
	local H, VB, VT, WL = table.create(count, 0), table.create(count, 0), table.create(count, 0), table.create(count, 0)
	local S, D, TY, HI, FL, YS = table.create(count, 0), table.create(count, 0), table.create(count, 1), table.create(count, 0), table.create(count, 0), table.create(count, 0)

	local function sampleAt(idx, i, j)
		local h, vb, vt, water, s, d, ty, hint, flags, ys = sampler:column(x0 + (i - 0.5) * 4, z0 + (j - 0.5) * 4)
		H[idx], VB[idx], VT[idx], WL[idx] = h, vb, vt, water
		S[idx], D[idx], TY[idx], HI[idx], FL[idx], YS[idx] = s, d, ty, hint, flags, ys
	end
	-- Fill node (i, j) from the coarser lattice with spacing `step`, or
	-- sample it when any coarser neighbour is within `far` of the road.
	-- (Tunnel voids only exist right next to the road, so "far" implies
	-- "no void".)
	local function fillNode(i, j, step, far)
		local idx = j * G + i + 1
		local i0, j0 = i - i % step, j - j % step
		local i1 = i % step == 0 and i0 or i0 + step
		local j1 = j % step == 0 and j0 or j0 + step
		local a, b, c, d = j0 * G + i0 + 1, j0 * G + i1 + 1, j1 * G + i0 + 1, j1 * G + i1 + 1
		if abs(D[a]) > far and abs(D[b]) > far and abs(D[c]) > far and abs(D[d]) > far then
			H[idx] = (H[a] + H[b] + H[c] + H[d]) * 0.25
			WL[idx] = max(WL[a], WL[b], WL[c], WL[d])
			VB[idx], VT[idx] = 0, 0
			S[idx], D[idx], YS[idx] = (S[a] + S[d]) * 0.5, (D[a] + D[d]) * 0.5, (YS[a] + YS[d]) * 0.5
			TY[idx], HI[idx], FL[idx] = TY[a], HI[a], FL[a]
		else
			sampleAt(idx, i, j)
		end
	end

	local L = N + 4
	for j = 0, L, 4 do
		for i = 0, L, 4 do
			sampleAt(j * G + i + 1, i, j)
		end
	end
	yieldFn()
	for j = 0, L, 2 do
		for i = 0, L, 2 do
			if i % 4 ~= 0 or j % 4 ~= 0 then
				fillNode(i, j, 4, FAR_8)
			end
		end
	end
	yieldFn()
	for j = 0, N + 1 do
		for i = 0, N + 1 do
			if i % 2 ~= 0 or j % 2 ~= 0 then
				fillNode(i, j, 2, FAR_4)
			end
		end
		if j % 6 == 5 then
			yieldFn()
		end
	end

	sampler:endArea()

	-- slopes and shell bottoms
	local SL = table.create(count, 0)
	local BOT = table.create(count, 0)
	for j = 1, N do
		for i = 1, N do
			local idx = j * G + i + 1
			local h = H[idx]
			local hE, hW, hN, hS = H[idx + 1], H[idx - 1], H[idx + G], H[idx - G]
			local gx, gz = (hE - hW) * 0.125, (hN - hS) * 0.125
			SL[idx] = sqrt(gx * gx + gz * gz)
			local bottom = min(h, hE, hW, hN, hS) - SHELL
			if VT[idx] > VB[idx] then
				bottom = min(bottom, VB[idx] - 6)
			end
			BOT[idx] = bottom
		end
	end

	-- voxels, one piece per quadrant so each write is small and tight
	local season = self.season
	local frozen = season.frozen
	local surface = self._surface
	local sea = self.sea
	local matPool, occPool = self._matRows, self._occRows
	local pieces = {}
	local vyMinAll, vyMaxAll = math.huge, -math.huge
	for pj = 0, N / PIECE - 1 do
		for pi = 0, N / PIECE - 1 do
			local yLo, yHi = math.huge, -math.huge
			for j = pj * PIECE + 1, pj * PIECE + PIECE do
				for i = pi * PIECE + 1, pi * PIECE + PIECE do
					local idx = j * G + i + 1
					local b, top = BOT[idx], max(H[idx], WL[idx])
					if b < yLo then
						yLo = b
					end
					if top > yHi then
						yHi = top
					end
				end
			end
			local vyMin = floor(yLo / 4)
			local vyMax = ceil(yHi / 4) + 1
			local NY = vyMax - vyMin
			vyMinAll, vyMaxAll = min(vyMinAll, vyMin), max(vyMaxAll, vyMax)

			local mats, occs = table.create(PIECE), table.create(PIECE)
			for ix = 1, PIECE do
				local mx, ox = table.create(NY), table.create(NY)
				for iy = 1, NY do
					mx[iy] = takeRow(matPool, AIR)
					ox[iy] = takeRow(occPool, 0)
				end
				mats[ix], occs[ix] = mx, ox
			end

			for lz = 1, PIECE do
				local j = pj * PIECE + lz
				for lx = 1, PIECE do
					local i = pi * PIECE + lx
					local idx = j * G + i + 1
					local h, bottom, water = H[idx], BOT[idx], WL[idx]
					local vb, vt = VB[idx], VT[idx]
					local hasVoid = vt > vb
					local ty, hint, flags, slope = TY[idx], HI[idx], FL[idx], SL[idx]
					local v = mnoise((x0 + (i - 0.5) * 4) / 38, (z0 + (j - 0.5) * 4) / 38, noiseZ) * 1.6
					local surf = surface(self, ty, hint, flags, slope, h, water, v)
					local sub = (surf == GRASS or surf == LEAFY or surf == SNOW) and GROUND or surf
					local deepFixed = ty ~= T.Canyon and ty ~= T.Coast
					local liquid = (frozen and water > sea + 0.5) and ICE or WATER
					local mx, ox = mats[lx], occs[lx]

					local top = max(h, water)
					local iyA = floor(bottom / 4) - vyMin + 1
					local iyB = ceil(top / 4) - vyMin
					if iyA < 1 then
						iyA = 1
					end
					if iyB > NY then
						iyB = NY
					end
					local solidTop = hasVoid and (h < vb and h or vb) or h
					for iy = iyA, iyB do
						local y0 = (iy - 1 + vyMin) * 4
						local y1 = y0 + 4
						-- solid overlap with [bottom, h], minus the tunnel void
						local a = bottom > y0 and bottom or y0
						local b = solidTop < y1 and solidTop or y1
						local solid = b > a and (b - a) or 0
						if hasVoid then
							a = vt > y0 and vt or y0
							b = h < y1 and h or y1
							if b > a then
								solid += b - a
							end
						end
						solid *= 0.25

						local wet = 0
						if water > y0 and not hasVoid then
							a = h > y0 and h or y0
							b = water < y1 and water or y1
							if b > a then
								wet = (b - a) * 0.25
							end
						end

						if solid >= 0.5 or (solid > 0 and wet <= 0) then
							local depth = h - (y0 + 2)
							local mat
							if depth < 4.5 then
								mat = surf
							elseif depth < 9 and sub == GROUND then
								mat = GROUND
							elseif deepFixed then
								mat = ROCK
							else
								mat = self:_deep(ty, hint, y0, v)
							end
							mx[iy][lz] = mat
							ox[iy][lz] = solid
						elseif wet > 0 then
							mx[iy][lz] = liquid
							ox[iy][lz] = min(1, wet + solid)
						end
					end
				end
			end

			local rmin = Vector3.new(x0 + pi * PIECE * 4 - origin.X, vyMin * 4, z0 + pj * PIECE * 4 - origin.Z)
			table.insert(pieces, {
				region = Region3.new(rmin, rmin + Vector3.new(PIECE * 4, NY * 4, PIECE * 4)),
				mats = mats,
				occs = occs,
			})
			yieldFn()
		end
	end

	return {
		pieces = pieces,
		data = {
			cx = cx,
			cz = cz,
			x0 = x0,
			z0 = z0,
			G = G,
			H = H,
			WL = WL,
			S = S,
			D = D,
			TY = TY,
			HI = HI,
			FL = FL,
			YS = YS,
			SL = SL,
			vyMin = vyMinAll,
			vyMax = vyMaxAll,
		},
	}
end

-- Writes a computed job's voxels. Engine call: serial phase only.
function TerrainBuilder:write(job, yieldFn)
	for _, piece in job.pieces do
		self.terrain:WriteVoxels(piece.region, 4, piece.mats, piece.occs)
		if yieldFn then
			yieldFn()
		end
	end
end

-- Hands a written job's voxel rows back to the pool.
function TerrainBuilder:release(job)
	local matPool, occPool = self._matRows, self._occRows
	for _, piece in job.pieces do
		for ix = 1, PIECE do
			local mx, ox = piece.mats[ix], piece.occs[ix]
			for iy = 1, #mx do
				table.insert(matPool, mx[iy])
				table.insert(occPool, ox[iy])
			end
		end
	end
	job.pieces = nil
end

--[[
	Builds the voxels for chunk (cx, cz) on this thread and returns the
	chunk's column data.
]]
function TerrainBuilder:build(cx: number, cz: number, origin: Vector3, yieldFn)
	local job = self:compute(cx, cz, origin, yieldFn)
	self:write(job, yieldFn)
	self:release(job)
	return job.data
end

-- Clears the voxels a chunk wrote. `origin` must be the origin that was
-- current when it was written (or the rebased equivalent).
function TerrainBuilder:clear(chunk, origin: Vector3)
	local size = self.size
	local rmin = Vector3.new(chunk.x0 - origin.X, chunk.vyMin * 4, chunk.z0 - origin.Z)
	local region = Region3.new(rmin, rmin + Vector3.new(size, (chunk.vyMax - chunk.vyMin) * 4, size))
	self.terrain:FillRegion(region, 4, AIR)
end

-- Voxel-space region of a chunk (for CopyRegion during rebasing).
function TerrainBuilder:voxelRegion(chunk, origin: Vector3): Region3int16
	local vx = (chunk.x0 - origin.X) // 4
	local vz = (chunk.z0 - origin.Z) // 4
	local n = self.n
	return Region3int16.new(
		Vector3int16.new(vx, chunk.vyMin, vz),
		Vector3int16.new(vx + n - 1, chunk.vyMax - 1, vz + n - 1)
	)
end

return TerrainBuilder
