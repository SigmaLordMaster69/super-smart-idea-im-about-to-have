--[[
	Dumps a top-down terrain map for tools/render_map.py.
	  lune run tools/render_map <seed> <x0> <x1> <zHalf> <step> <out.bin>
	The map is centred on the road's z at each x column band.
]]

local process = require("@lune/process")
local fs = require("@lune/fs")
local env = require("./env")

local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")

local seed = tonumber(process.args[1]) or 12345
local x0 = tonumber(process.args[2]) or 0
local x1 = tonumber(process.args[3]) or 8000
local zHalf = tonumber(process.args[4]) or 1200
local step = tonumber(process.args[5]) or 8
local out = process.args[6] or "map.bin"

local world = World.new(Config, seed)
local road = world.road
local sampler = world.sampler
world:prepareForX(x0, x1, zHalf)

-- centre the image on the average road z within the range
road:ensureX(x1)
local kA, kB = road:indexAtX(x0), road:indexAtX(x1)
local zc = 0
for k = kA, kB do
	zc += road.pz[k]
end
zc /= (kB - kA + 1)

local W = math.floor((x1 - x0) / step)
local H = math.floor(2 * zHalf / step)
local parts = { string.pack("<iiiff", W, H, step, x0, zc - zHalf) }
local t0 = os.clock()
for j = 0, H - 1 do
	local z = zc - zHalf + (j + 0.5) * step
	local row = table.create(W)
	for i = 0, W - 1 do
		local x = x0 + (i + 0.5) * step
		local h, vb, vt, water, s, d, typeIdx, hint, flags = sampler:column(x, z)
		local k = math.clamp(math.floor(s / road.step + 1.5), 1, road.nFeat)
		local special = 0
		if math.abs(d) <= Config.Road.HalfWidth then
			special = 1
			if road:isTunnel(k) then
				special = 2
			elseif road:isBridge(k) then
				special = 3
			end
		elseif math.abs(d) <= Config.Road.HalfWidth + 3 then
			if road:hasRail(k, d < 0 and -1 or 1) then
				special = 4
			end
		end
		row[i + 1] = string.pack("<ffBBBB", h, water > -1e9 and water or -9999, typeIdx, hint, flags % 256, special)
	end
	parts[#parts + 1] = table.concat(row)
end
print(string.format("%dx%d columns in %.1fs (%.1f us/column)", W, H, os.clock() - t0, (os.clock() - t0) / (W * H) * 1e6))
fs.writeFile(out, table.concat(parts))
