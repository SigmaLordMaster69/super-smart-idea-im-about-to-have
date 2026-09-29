--[[
	Lists sections with the world X range they cover.
	  lune run tools/list_sections [seed] [count]
]]
local process = require("@lune/process")
local env = require("./env")
local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")
local seed = tonumber(process.args[1]) or 12345
local count = tonumber(process.args[2]) or 14
local world = World.new(Config, seed)
local road = world.road
world.sections:ensure(0)
while #world.sections.list < count do
	world.sections:_append()
end
for i = 1, count do
	local sec = world.sections.list[i]
	local a = math.max(0, sec.startS)
	local xa = road:xzAt(a)
	local xb = road:xzAt(sec.endS)
	print(string.format("%2d %-12s %-22s s %6.0f..%6.0f  x %6.0f..%6.0f side %2d crossings %d", i, sec.type, sec.name, a, sec.endS, xa, xb, sec.side, #sec.crossings))
end
