--[[
	TerrainBuilder
	--------------
	Turns one chunk of the height model into smooth-terrain voxels.

	Every voxel column gets a solid shell from a little below its lowest
	neighbour up to its surface, so cliffs are closed without filling whole
	mountains. Tunnel voids are cut out of the shell, and water fills from
	the ground up to the water level.

	The per-column data is kept on the chunk so the decorator can place
	trees without sampling the terrain again.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("InfiniteRoad")
local TerrainSampler = require(Shared.TerrainSampler)

local HINT = TerrainSampler.Hint
local FLAG = TerrainSampler.Flag
local T = TerrainSampler.TypeIndex

local M = Enum.Material
local AIR = M.Air
local WATER = M.Water

local floor, ceil, min, max, sqrt = math.floor, math.ceil, math.min, math.max, math.sqrt
local btest = bit32.btest

local TerrainBuilder = {}
TerrainBuilder.__index = TerrainBuilder

-- canyon rock layers, bottom to top, repeating every #STRATA * 11 studs
local STRATA = { M.Sandstone, M.Limestone, M.Sandstone, M.Salt, M.Sandstone, M.Limestone }
local STRATA_HEIGHT = 11

-- columns farther than this from the road are interpolated from a coarser grid
local FAR_FROM_ROAD = 300

function TerrainBuilder.new(world, config, terrain)
	local self = setmetatable({}, TerrainBuilder)
	self.world = world
	self.config = config
	self.terrain = terrain
	self.size = config.World.ChunkSize
	self.n = self.size // 4
	self.snowLine = config.Terrain.SnowLine
	self.sea = config.SeaLevel
	return self
end

local function strata(y: number, jitter: number)
	local band = floor((y + jitter + 4000) / STRATA_HEIGHT) % #STRATA
	return STRATA[band + 1]
end

-- surface material for one column
function TerrainBuilder:_surface(ty, hint, flags, slope, h, water, v)
	if btest(flags, FLAG.RoadBed) then
		return M.Asphalt
	end
	if btest(flags, FLAG.Shoulder) then
		return M.Ground
	end
	if water > h + 0.3 then
		if hint == HINT.Riverbed then
			return v > 0 and M.Mud or M.Ground
		elseif hint == HINT.Seabed or hint == HINT.Beach then
			return water - h > 30 and M.Rock or M.Sand
		elseif hint == HINT.Lakebed then
			return water - h > 8 and M.Mud or M.Sand
		end
		return M.Mud
	end
	if hint == HINT.Beach and slope < 0.7 then
		return M.Sand
	end
	if hint == HINT.Cliff then
		if slope > 0.75 then
			return h < self.sea + 14 and M.Basalt or M.Slate
		end
		return h < self.sea + 5 and M.Sand or M.Grass
	end
	if ty == T.Canyon then
		if hint == HINT.CanyonFloor and slope < 0.6 then
			return v > 0.35 and M.Sand or M.Ground
		end
		if slope > 0.55 then
			return strata(h, v * 5)
		end
		return v > 0.3 and M.Sandstone or M.Ground
	end
	if btest(flags, FLAG.Cut) and slope > 0.55 then
		return (ty == T.Coast and M.Slate) or M.Rock
	end
	if btest(flags, FLAG.Fill) then
		return slope > 0.55 and M.Ground or M.Grass
	end
	local snow = self.snowLine + v * 30
	if h > snow then
		return slope < 1.1 and M.Snow or M.Rock
	end
	if slope > 1.0 then
		return (ty == T.Coast and M.Slate) or M.Rock
	end
	if slope > 0.62 then
		if ty == T.Mountains or h > snow - 60 then
			return v > 0 and M.Rock or M.Ground
		end
		return M.Ground
	end
	if ty == T.Forest then
		return v > -0.25 and M.LeafyGrass or M.Grass
	elseif ty == T.Mountains and h > snow - 70 then
		return v > 0.1 and M.Ground or M.Grass
	elseif ty == T.Meadow then
		return v > 0.45 and M.LeafyGrass or M.Grass
	end
	return v > 0.3 and M.LeafyGrass or M.Grass
end

-- material deep inside the shell (exposed on cliff faces and cuts)
function TerrainBuilder:_deep(ty, hint, y, v)
	if ty == T.Canyon then
		return strata(y, v * 5)
	elseif ty == T.Coast then
		return y < self.sea + 12 and M.Basalt or M.Slate
	end
	return M.Rock
end

--[[
	Builds the voxels for chunk (cx, cz). `origin` is the floating-origin
	offset (world minus Roblox coordinates). `yieldFn` is called regularly
	so the caller can spread the work across frames.
	Returns the chunk's column data.
]]
function TerrainBuilder:build(cx: number, cz: number, origin: Vector3, yieldFn)
	local world = self.world
	local sampler = world.sampler
	local size, N = self.size, self.n
	local G = N + 2
	local x0, z0 = cx * size, cz * size
	local noise = world.noise

	world:prepareForX(x0 - 8, x0 + size + 8, 0)

	local count = G * G
	local H, VB, VT, WL = table.create(count), table.create(count), table.create(count), table.create(count)
	local S, D, TY, HI, FL, YS = table.create(count), table.create(count), table.create(count), table.create(count), table.create(count), table.create(count)

	--[[
		Columns sit every 4 studs. First sample a coarse lattice every 8
		studs (the even columns, plus one extra row/column). Columns far from
		the road, where the terrain is smooth, are interpolated from it;
		everything near the road is sampled exactly. The lattice is aligned
		to the world, so neighbouring chunks agree on their shared border.
	]]
	local C = N // 2 + 2 -- coarse nodes per side (i = 0, 2, ..., N + 2)
	local cH, cWL, cS, cD, cTY, cHI, cFL, cYS = {}, {}, {}, {}, {}, {}, {}, {}
	local cFar = {}
	for b = 0, C - 1 do
		local z = z0 + (2 * b - 0.5) * 4
		for a = 0, C - 1 do
			local x = x0 + (2 * a - 0.5) * 4
			local h, vb, vt, water, s, d, ty, hint, flags, ys = sampler:column(x, z)
			local c = b * C + a + 1
			cH[c], cWL[c], cS[c], cD[c], cTY[c], cHI[c], cFL[c], cYS[c] = h, water, s, d, ty, hint, flags, ys
			cFar[c] = math.abs(d) > FAR_FROM_ROAD and vt <= vb
			if b * 2 <= N + 1 and a * 2 <= N + 1 then
				local idx = (2 * b) * G + 2 * a + 1
				H[idx], VB[idx], VT[idx], WL[idx] = h, vb, vt, water
				S[idx], D[idx], TY[idx], HI[idx], FL[idx], YS[idx] = s, d, ty, hint, flags, ys
			end
		end
		yieldFn()
	end

	for j = 0, N + 1 do
		local z = z0 + (j - 0.5) * 4
		local row = j * G
		local oddJ = j % 2 == 1
		local b0 = j // 2
		for i = 0, N + 1 do
			local oddI = i % 2 == 1
			if not oddI and not oddJ then
				continue -- lattice node, already filled
			end
			local a0 = i // 2
			local c00 = b0 * C + a0 + 1
			local c10 = oddI and c00 + 1 or c00
			local c01 = oddJ and c00 + C or c00
			local c11 = oddJ and c10 + C or c10
			local idx = row + i + 1
			if cFar[c00] and cFar[c10] and cFar[c01] and cFar[c11] then
				H[idx] = (cH[c00] + cH[c10] + cH[c01] + cH[c11]) * 0.25
				WL[idx] = max(cWL[c00], cWL[c10], cWL[c01], cWL[c11])
				VB[idx], VT[idx] = 0, 0
				S[idx] = (cS[c00] + cS[c11]) * 0.5
				D[idx] = (cD[c00] + cD[c11]) * 0.5
				YS[idx] = (cYS[c00] + cYS[c11]) * 0.5
				TY[idx], HI[idx], FL[idx] = cTY[c00], cHI[c00], cFL[c00]
			else
				local x = x0 + (i - 0.5) * 4
				local h, vb, vt, water, s, d, ty, hint, flags, ys = sampler:column(x, z)
				H[idx], VB[idx], VT[idx], WL[idx] = h, vb, vt, water
				S[idx], D[idx], TY[idx], HI[idx], FL[idx], YS[idx] = s, d, ty, hint, flags, ys
			end
		end
		if j % 4 == 3 then
			yieldFn()
		end
	end

	-- slopes and vertical extent
	local SL = table.create(count, 0)
	local BOT = table.create(count, 0)
	local yLo, yHi = math.huge, -math.huge
	for j = 1, N do
		for i = 1, N do
			local idx = j * G + i + 1
			local h = H[idx]
			local hE, hW, hN, hS = H[idx + 1], H[idx - 1], H[idx + G], H[idx - G]
			local gx, gz = (hE - hW) * 0.125, (hN - hS) * 0.125
			SL[idx] = sqrt(gx * gx + gz * gz)
			local bottom = min(h, hE, hW, hN, hS) - 7
			if VT[idx] > VB[idx] then
				bottom = min(bottom, VB[idx] - 6)
			end
			BOT[idx] = bottom
			local top = max(h, WL[idx])
			if bottom < yLo then
				yLo = bottom
			end
			if top > yHi then
				yHi = top
			end
		end
	end

	local vyMin = floor(yLo / 4)
	local vyMax = ceil(yHi / 4) + 1
	local NY = vyMax - vyMin

	-- voxel arrays [x][y][z]
	local mats, occs = table.create(N), table.create(N)
	for ix = 1, N do
		local mx, ox = table.create(NY), table.create(NY)
		for iy = 1, NY do
			mx[iy] = table.create(N, AIR)
			ox[iy] = table.create(N, 0)
		end
		mats[ix], occs[ix] = mx, ox
	end
	yieldFn()

	for j = 1, N do
		local iz = j
		for i = 1, N do
			local idx = j * G + i + 1
			local ix = i
			local h, bottom, water = H[idx], BOT[idx], WL[idx]
			local vb, vt = VB[idx], VT[idx]
			local hasVoid = vt > vb
			local ty, hint, flags, slope = TY[idx], HI[idx], FL[idx], SL[idx]
			local x, z = x0 + (i - 0.5) * 4, z0 + (j - 0.5) * 4
			local v = noise:n2(x / 38, z / 38, 101) * 1.6
			local surf = self:_surface(ty, hint, flags, slope, h, water, v)
			local sub = (surf == M.Grass or surf == M.LeafyGrass) and M.Ground or surf
			local mx, ox = mats[ix], occs[ix]

			local top = max(h, water)
			local iyA = floor(bottom / 4) - vyMin + 1
			local iyB = ceil(top / 4) - vyMin
			if iyA < 1 then
				iyA = 1
			end
			if iyB > NY then
				iyB = NY
			end
			for iy = iyA, iyB do
				local y0 = (iy - 1 + vyMin) * 4
				local y1 = y0 + 4
				-- solid overlap with [bottom, h] minus the tunnel void
				local solid
				if hasVoid then
					local a = max(bottom, y0)
					local b = min(min(h, vb), y1)
					solid = b > a and (b - a) or 0
					a = max(vt, y0)
					b = min(h, y1)
					if b > a then
						solid += b - a
					end
				else
					local a = max(bottom, y0)
					local b = min(h, y1)
					solid = b > a and (b - a) or 0
				end
				solid *= 0.25

				local wet = 0
				if water > y0 and not hasVoid then
					local a = max(h, y0)
					local b = min(water, y1)
					if b > a then
						wet = (b - a) * 0.25
					end
				end

				local mat, occ
				if solid >= 0.5 or (solid > 0 and wet <= 0) then
					local depth = h - (y0 + 2)
					if depth < 4.5 then
						mat = surf
					elseif depth < 9 then
						mat = sub == M.Ground and M.Ground or self:_deep(ty, hint, y0, v)
					else
						mat = self:_deep(ty, hint, y0, v)
					end
					occ = solid
				elseif wet > 0 then
					mat = WATER
					occ = min(1, wet + solid)
				end
				if mat then
					mx[iy][iz] = mat
					ox[iy][iz] = occ
				end
			end
		end
		yieldFn()
	end

	local rmin = Vector3.new(x0 - origin.X, vyMin * 4, z0 - origin.Z)
	local region = Region3.new(rmin, rmin + Vector3.new(size, NY * 4, size))
	self.terrain:WriteVoxels(region, 4, mats, occs)

	return {
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
		vyMin = vyMin,
		vyMax = vyMax,
	}
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
