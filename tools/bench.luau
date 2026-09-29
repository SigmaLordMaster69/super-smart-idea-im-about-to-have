--[[
	Terrain build benchmark: a square of chunks around a road point, like a
	fresh load. Reports compute (sampling + voxel fill) time per chunk.
	  lune run tools/bench [seed] [sampleIndex] [builderModulePath]
]]
local process = require("@lune/process")
local env = require("./env")
local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")
local seed = tonumber(process.args[1]) or 12345
local k = tonumber(process.args[2]) or 1500
local builderPath = process.args[3] or "src/client/TerrainBuilder"
local Builder = env.require(builderPath)
local Vector3 = env.roblox.Vector3

local world = World.new(Config, seed)
local p = world.road:frameAtIndex(k)
local size = Config.World.ChunkSize
local ccx, ccz = math.floor(p.X / size), math.floor(p.Z / size)
-- warm the road caches so they are not part of the measurement
world:prepareForX((ccx - 8) * size, (ccx + 8) * size, 0)
local tb = Builder.new(world, Config, env.terrain)
env.terrain.WriteVoxels = function() end -- measure our code, not the mock
local nearT, nearN, farT, farN = 0, 0, 0, 0
for dz = -7, 7 do
	for dx = -7, 7 do
		local t0 = os.clock()
		tb:build(ccx + dx, ccz + dz, Vector3.new(0, 0, 0), function() end)
		local t = os.clock() - t0
		if math.abs(dx) <= 2 and math.abs(dz) <= 2 then
			nearT += t
			nearN += 1
		else
			farT += t
			farN += 1
		end
	end
end
print(string.format("%s: near road %.1f ms/chunk, far %.1f ms/chunk, overall %.1f ms/chunk (%d chunks)",
	builderPath, nearT / nearN * 1000, farT / farN * 1000, (nearT + farT) / (nearN + farN) * 1000, nearN + farN))
