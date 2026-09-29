--[[
	Curve statistics for tuning the heading model.
	  lune run tools/curve_stats [seed] [lengthStuds]
]]
local process = require("@lune/process")
local env = require("./env")
local Config = env.require("src/shared/Config")
local Noise = env.require("src/shared/Noise")
local Sections = env.require("src/shared/Sections")
local RoadPath = env.require("src/shared/RoadPath")

local seed = tonumber(process.args[1]) or 12345
local length = tonumber(process.args[2]) or 100000
local noise = Noise.new(seed)
local sections = Sections.new(Config, seed, noise)
local road = RoadPath.new(Config, noise, sections)
local n = math.floor(length / road.step)
road:_ensureXZ(n)

local buckets = { 200, 300, 450, 700, 1000, 2000, math.huge }
local counts = table.create(#buckets, 0)
local maxH = 0
for k = 9, n - 8 do
	local c = math.abs(road.hd[k + 8] - road.hd[k - 8]) / (16 * road.step)
	local r = 1 / math.max(c, 1e-9)
	for i, b in buckets do
		if r < b then
			counts[i] += 1
			break
		end
	end
	maxH = math.max(maxH, math.abs(road.hd[k]))
end
local total = n - 16
local prev = 0
for i, b in buckets do
	print(string.format("radius %5s..%-5s %5.1f%%", tostring(prev), tostring(b), counts[i] / total * 100))
	prev = b
end
print(string.format("max |heading| %.1f deg", math.deg(maxH)))
