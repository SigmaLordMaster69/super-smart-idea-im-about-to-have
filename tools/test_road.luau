--[[
	Road generation checks.
	  lune run tools/test_road [seed] [lengthStuds]
]]

local process = require("@lune/process")
local env = require("./env")

local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")

local seed = tonumber(process.args[1]) or 12345
local length = tonumber(process.args[2]) or 60000

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local t0 = os.clock()
local world = World.new(Config, seed)
local road = world.road
local n = math.floor(length / road.step)
road:ensureFlags(n)
local elapsed = os.clock() - t0
print(string.format("seed %d: %d samples (%.0f studs) in %.2fs (%.1f us/sample)", seed, n, n * road.step, elapsed, elapsed / road.nFeat * 1e6))

-- X must be strictly increasing
local px, pz, y = road.px, road.pz, road.y
local monotonic = true
for k = 2, road.nXZ do
	if px[k] <= px[k - 1] then
		monotonic = false
		print("non-monotonic at", k)
		break
	end
end
check(monotonic, "road X must increase monotonically")

-- curvature / grade limits
local maxCurv, maxGrade, minY, maxY = 0, 0, math.huge, -math.huge
for k = 2, n do
	local dh = math.abs(road.hd[k] - road.hd[k - 1]) / road.step
	maxCurv = math.max(maxCurv, dh)
	local g = math.abs(y[k] - y[k - 1]) / road.step
	maxGrade = math.max(maxGrade, g)
	minY = math.min(minY, y[k])
	maxY = math.max(maxY, y[k])
end
print(string.format("min radius %.0f studs, max grade %.2f%%, elevation %.0f..%.0f", 1 / maxCurv, maxGrade * 100, minY, maxY))
check(1 / maxCurv >= Config.Road.MinRadius - 0.5, "radius below MinRadius")
check(maxGrade <= Config.Road.MaxGrade + 1e-6, "grade above MaxGrade")
check(minY >= Config.SeaLevel + Config.Road.MinElevation - 1e-6, "road below MinElevation")

-- runs of flags
local function runs(flags, from, to)
	local list, start = {}, nil
	for k = from, to + 1 do
		local v = k <= to and flags(k)
		if v and not start then
			start = k
		elseif not v and start then
			table.insert(list, { start, k - 1 })
			start = nil
		end
	end
	return list
end

local tunnels = runs(function(k)
	return road:isTunnel(k)
end, 1, n)
local bridges = runs(function(k)
	return road:isBridge(k)
end, 1, n)
local railsL = runs(function(k)
	return road:hasRail(k, -1)
end, 1, n)
local railsR = runs(function(k)
	return road:hasRail(k, 1)
end, 1, n)

local function describe(name, list)
	local total = 0
	local longest = 0
	for _, r in list do
		local len = (r[2] - r[1] + 1) * road.step
		total += len
		longest = math.max(longest, len)
	end
	print(string.format("%-8s %3d runs, total %6.0f studs (%.1f%%), longest %.0f", name, #list, total, total / (n * road.step) * 100, longest))
end
describe("tunnels", tunnels)
describe("bridges", bridges)
describe("railsL", railsL)
describe("railsR", railsR)

for _, r in tunnels do
	check(r[2] - r[1] + 1 >= Config.Tunnel.MinLength, "tunnel shorter than MinLength at " .. r[1])
end
for k = 1, n do
	if road:isTunnel(k) and road:isBridge(k) then
		check(false, "tunnel and bridge overlap at " .. k)
		break
	end
end

-- regions
local counts = {}
for _, sec in world.sections.list do
	if sec.startS < n * road.step then
		counts[sec.type] = (counts[sec.type] or 0) + 1
	end
end
local parts = {}
for name, c in counts do
	table.insert(parts, name .. "=" .. c)
end
table.sort(parts)
print("regions: " .. table.concat(parts, " "))
local seq = {}
for i, sec in world.sections.list do
	if sec.startS > n * road.step then
		break
	end
	table.insert(seq, string.format("%s(%s)", sec.type, sec.name))
end
print("sequence: " .. table.concat(seq, " > "))

local crossingKinds = {}
for _, c in world.sections.crossings do
	if c.s < n * road.step then
		crossingKinds[c.kind] = (crossingKinds[c.kind] or 0) + 1
	end
end
for kind, c in crossingKinds do
	print("crossing", kind, c)
end

-- determinism: a second world with the same seed must match exactly
local world2 = World.new(Config, seed)
world2.road:ensureFlags(2000)
local same = true
for k = 1, 2000 do
	if world2.road.px[k] ~= px[k] or world2.road.y[k] ~= y[k] or world2.road:isTunnel(k) ~= road:isTunnel(k) then
		same = false
		break
	end
end
check(same, "same seed must produce identical road")

-- projection sanity: points offset from the road project back
local maxErr = 0
for k = 200, math.min(n - 400, 6000), 37 do
	local p = road:frameAtIndex(k)
	local h = road.hd[k]
	local rx, rz = -math.sin(h), math.cos(h)
	for _, off in { -60, -10, 0, 25, 150 } do
		local x, z = p.X + rx * off, p.Z + rz * off
		local s, d = road:project(x, z)
		local errS = math.abs(s - road:indexToS(k))
		local errD = math.abs(d - off)
		maxErr = math.max(maxErr, errD)
		-- Inside tight curves several road points can be almost equally
		-- close, so a different s is fine as long as it is not farther away.
		if errD > 1 or (errS > 2 and math.abs(d) > math.abs(off) + 0.05) then
			check(false, string.format("projection off at k=%d off=%d: ds=%.2f dd=%.2f", k, off, errS, errD))
		end
	end
end
print(string.format("projection max lateral error %.3f", maxErr))

if failures == 0 then
	print("ALL ROAD CHECKS PASSED")
else
	print(failures .. " FAILURES")
	process.exit(1)
end
