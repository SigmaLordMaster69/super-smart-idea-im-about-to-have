--[[
	Decorator
	---------
	Places trees, bushes, cacti, rocks and flowers on a chunk using the
	column data TerrainBuilder kept.

	The chunk is split into cells. Every cell has its own seeded RNG, so a
	cell always makes the same decision no matter which detail level is being
	built. That is what lets a chunk swap between near (full trees) and far
	(one-part trees) detail without anything moving.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("InfiniteRoad")
local TerrainSampler = require(Shared.TerrainSampler)
local MathUtil = require(Shared.MathUtil)

local HINT = TerrainSampler.Hint
local FLAG = TerrainSampler.Flag
local smoothstep = MathUtil.smoothstep
local btest = bit32.btest
local abs, floor = math.abs, math.floor

local TYPE_NAMES = {}
for name, index in TerrainSampler.TypeIndex do
	TYPE_NAMES[index] = name
end

local Decorator = {}
Decorator.__index = Decorator

Decorator.Level = { None = 0, Far = 1, Near = 2 }

function Decorator.new(world, config, props)
	local self = setmetatable({}, Decorator)
	self.world = world
	self.config = config
	self.props = props
	self.hw = config.Road.HalfWidth
	self.sea = config.SeaLevel
	return self
end

-- weighted pick from { {kind, weight}, ... } with r in [0, 1)
local function pick(list, r)
	local total = 0
	for _, e in list do
		total += e[2]
	end
	r *= total
	for _, e in list do
		r -= e[2]
		if r <= 0 then
			return e[1]
		end
	end
	return list[#list][1]
end

local TREES = {
	Meadow = { { "oak", 6 }, { "birch", 4 } },
	Forest = { { "pine", 5 }, { "oak", 3.5 }, { "birch", 1.5 } },
	Mountains = { { "pine", 8 }, { "oak", 1.5 }, { "birch", 0.5 } },
	Coast = { { "cypress", 6 }, { "pine", 4 } },
	Canyon = { { "cactus", 1 } },
	Lake = { { "pine", 5 }, { "birch", 3 }, { "oak", 2 } },
	RiverValley = { { "oak", 5 }, { "birch", 2.5 }, { "pine", 2.5 } },
}

--[[
	Builds decorations for `chunk` at `level` (Decorator.Level) into
	`parent`. `origin` is the floating-origin offset.
]]
function Decorator:build(chunk, level: number, origin: Vector3, parent, yieldFn)
	if level == 0 then
		return
	end
	local world = self.world
	local cfg = self.config
	local props = self.props
	local noise = world.noise
	local cell = cfg.Decor.CellSize
	local size = cfg.World.ChunkSize
	local cells = size // cell
	local G = chunk.G
	local H, WL, D, TY, HI, FL, SL, S = chunk.H, chunk.WL, chunk.D, chunk.TY, chunk.HI, chunk.FL, chunk.SL, chunk.S
	local x0, z0 = chunk.x0, chunk.z0
	local near = level == 2
	local clearance = self.hw + cfg.Decor.RoadClearance
	local treeLine = cfg.Terrain.TreeLine
	local densities = cfg.Decor.Density
	local seed = world.seed
	local ox, oz = origin.X, origin.Z

	for cj = 0, cells - 1 do
		for ci = 0, cells - 1 do
			local gx, gz = floor(x0 / cell) + ci, floor(z0 / cell) + cj
			local rng = Random.new(MathUtil.hash(gx, gz, seed, 99))
			local x = x0 + (ci + rng:NextNumber()) * cell
			local z = z0 + (cj + rng:NextNumber()) * cell
			local r1, r2, r3, r4 = rng:NextNumber(), rng:NextNumber(), rng:NextNumber(), rng:NextNumber()

			-- bilinear height, nearest-column data
			local fx, fz = (x - x0) / 4 + 0.5, (z - z0) / 4 + 0.5
			local i, j = floor(fx), floor(fz)
			local tx, tz = fx - i, fz - j
			local idx = j * G + i + 1
			local h = (H[idx] * (1 - tx) + H[idx + 1] * tx) * (1 - tz) + (H[idx + G] * (1 - tx) + H[idx + G + 1] * tx) * tz
			local ni = (tz > 0.5 and idx + G or idx) + (tx > 0.5 and 1 or 0)
			local ad = abs(D[ni])
			local flags, hint, slope, water = FL[ni], HI[ni], SL[ni], WL[ni]
			local typeName = TYPE_NAMES[TY[ni]]

			if ad < clearance or water > h - 0.4 then
				continue
			end
			if btest(flags, FLAG.Bridge) and ad < self.hw + 30 then
				continue
			end

			local density = densities[typeName] or 0.2
			local clump = noise:u2(x / 260, z / 260, 131)
			if typeName == "Meadow" then
				density *= clump > 0.68 and 5 or 0.4
			elseif typeName ~= "Canyon" then
				density *= 0.25 + 1.3 * smoothstep(0.25, 0.7, clump)
			end
			if slope > 0.9 or hint == HINT.Beach or hint == HINT.CanyonWall then
				density = 0
			elseif slope > 0.6 then
				density *= 0.45
			end
			if hint == HINT.Cliff and slope > 0.45 then
				density = 0
			end
			local snowy = h > treeLine - 70
			if h > treeLine + 15 then
				density = 0
			elseif h > treeLine - 30 then
				density *= 0.4
			end

			local base = Vector3.new(x - ox, h - 0.35, z - oz)
			local yaw = CFrame.Angles(0, r4 * math.pi * 2, 0)

			if r1 < density then
				local kind = pick(TREES[typeName] or TREES.Forest, r2)
				if kind == "pine" and snowy then
					kind = "snowpine"
				end
				local autumn = false
				if kind == "oak" or kind == "birch" then
					local sec = world.sections:get(S[ni])
					autumn = sec.autumn == true
				end
				local sizeClass = r3 < 0.3 and 1 or (r3 < 0.8 and 2 or 3)
				local model = props:tree(kind, sizeClass, floor(r3 * 1000), not near, autumn)
				model:PivotTo(CFrame.new(base) * yaw)
				model.Parent = parent
				continue
			end

			if not near then
				continue
			end

			-- small stuff, only up close
			local extra = r1 - density
			local nearWater = h < self.sea + 7 and (hint == HINT.Cliff or hint == HINT.Beach or typeName == "Coast")
			local rockChance = (typeName == "Mountains" and 0.07) or (typeName == "Canyon" and 0.05) or (nearWater and 0.12) or 0.025
			if extra < rockChance and slope < 1.4 then
				local style = (typeName == "Canyon" and "canyon") or ((typeName == "Coast" or nearWater) and "coast") or (snowy and "snow") or "default"
				local rsize = 1.5 + r3 * r3 * 7
				local rock = props:rock(style, rsize, rng)
				rock.CFrame = CFrame.new(base + Vector3.new(0, rsize * 0.15, 0)) * yaw * CFrame.Angles(r2 * 0.6, 0, r3 * 0.5)
				rock.Parent = parent
				continue
			end
			extra -= rockChance
			if typeName == "Canyon" then
				if extra < 0.1 and slope < 0.6 then
					local m = props:tree("drybush", r3 < 0.5 and 1 or 2, floor(r2 * 100), false)
					m:PivotTo(CFrame.new(base) * yaw)
					m.Parent = parent
				end
				continue
			end
			if slope > 0.6 or density == 0 and h > treeLine - 30 then
				continue
			end
			local bushChance = (typeName == "Meadow" and 0.06) or 0.14
			if extra < bushChance then
				local autumn = typeName == "Forest" and world.sections:get(S[ni]).autumn == true
				local m = props:tree("bush", r3 < 0.6 and 1 or 2, floor(r2 * 100), false, autumn)
				m:PivotTo(CFrame.new(base) * yaw)
				m.Parent = parent
				continue
			end
			extra -= bushChance
			if typeName == "Meadow" or typeName == "RiverValley" or typeName == "Lake" then
				if extra < (typeName == "Meadow" and 0.28 or 0.1) and slope < 0.35 then
					local m = props:tree("flowers", 1, floor(r2 * 1000), false)
					m:PivotTo(CFrame.new(base) * yaw)
					m.Parent = parent
				end
			end
		end
		if yieldFn then
			yieldFn()
		end
	end
end

return Decorator
