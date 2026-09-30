--[[
	End-to-end chunk pipeline test (terrain voxels, road, decoration, rebase)
	using real Roblox instance classes from @lune/roblox and a terrain mock.
	  lune run tools/test_chunks [seed]
]]

local process = require("@lune/process")
local env = require("./env")

local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")
local ChunkManager = env.require("src/client/ChunkManager")

local Vector3, CFrame = env.roblox.Vector3, env.roblox.CFrame
local seed = tonumber(process.args[1]) or 12345
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local world = World.new(Config, seed)
local terrain = env.terrain
local manager = ChunkManager.new(world, Config, terrain)
local road = world.road

local function buildAround(worldPos, radius)
	manager:setFocus(worldPos)
	manager.wantedFocus = nil
	local t0 = os.clock()
	local before = manager.stats.built
	for _ = 1, 20000 do
		manager:update(0.05) -- the loading-screen budget
		if manager:progress(radius) >= 1 then
			break
		end
	end
	local built = manager.stats.built - before
	return built, os.clock() - t0
end

local function countParts()
	local counts, total = {}, 0
	for _, d in manager.container:GetDescendants() do
		if d:IsA("BasePart") then
			counts[d.Name] = (counts[d.Name] or 0) + 1
			total += 1
		elseif d:IsA("Model") then
			counts[d.Name] = (counts[d.Name] or 0) + 1
		end
	end
	return counts, total
end

-- 1. spawn area
local spawnPos = road:frameAt(Config.Road.SpawnDistance)
manager:setOrigin(spawnPos)
local built, secs = buildAround(spawnPos, 440)
print(string.format("spawn: built %d chunks in %.2fs (%.1f ms/chunk incl. decor), %d voxel writes", built, secs, secs / math.max(built, 1) * 1000, #terrain.writes))
check(built > 20, "expected the spawn area to build")
-- four quadrant writes per chunk (one more chunk may be half done when the loop stops)
check(#terrain.writes >= built * 4 and #terrain.writes <= (built + 1) * 4, "four WriteVoxels (quadrants) per chunk")

local counts, total = countParts()
print("parts:", total)
local names = {}
for name, c in counts do
	table.insert(names, string.format("%s=%d", name, c))
end
table.sort(names)
print("  " .. table.concat(names, " "))
check((counts.Road or 0) > 0, "road parts built")
check((counts.EdgeLine or 0) > 0, "edge lines built")
check((counts.Dash or 0) + (counts.CenterLine or 0) > 0, "centre line built")

-- voxel statistics of the spawn area
local matCount = {}
local voxels = 0
for _, w in terrain.writes do
	for _, plane in w.materials do
		for _, row in plane do
			for _, m in row do
				if m ~= env.roblox.Enum.Material.Air then
					matCount[m.Name] = (matCount[m.Name] or 0) + 1
					voxels += 1
				end
			end
		end
	end
end
local mats = {}
for name, c in matCount do
	table.insert(mats, string.format("%s %.1f%%", name, c / voxels * 100))
end
table.sort(mats)
print("materials: " .. table.concat(mats, ", "))

-- road surface must sit above the terrain under it
local worst = -math.huge
for _, rec in manager.chunks do
	local data = rec.data
	if data then
		for idx = 1, #data.H do
			if bit32.btest(data.FL[idx], 1) then -- RoadBed
				worst = math.max(worst, data.H[idx] - data.YS[idx])
			end
		end
	end
end
print(string.format("terrain vs road surface under the road: max %.2f (must be < 0)", worst))
check(worst < 0, "terrain pokes through the road")

-- 2. find a tunnel and a bridge and build around them
local function findRun(pred, from)
	road:ensureFlags(from + 8000)
	for k = from, from + 8000 do
		if pred(k) then
			return k
		end
	end
end
local kT = findRun(function(k)
	return road:isTunnel(k)
end, 200)
local kB = findRun(function(k)
	return road:isBridge(k)
end, 200)
print("first tunnel sample", kT, "first bridge sample", kB)
local function report(tag)
	local c = countParts()
	local trees = 0
	for _, name in { "Pine", "SnowPine", "Oak", "Birch", "Cypress", "Cactus", "PineFar", "SnowPineFar", "OakFar", "BirchFar", "CypressFar", "CactusFar" } do
		trees += c[name] or 0
	end
	print(string.format("  %s: tunnel walls %d, bridge decks %d, piers %d, rails %d, signs %d, delineators %d, trees %d, bushes %d, rocks %d",
		tag, c.TunnelWall or 0, c.BridgeDeck or 0, c.Pier or 0, c.GuardRail or 0,
		(c.WarningSign or 0) + (c.Sign or 0) + (c.Chevron or 0), c.Delineator or 0, trees, c.Bush or 0, c.Rock or 0))
	return c
end
report("spawn")
if kT then
	built, secs = buildAround(road:frameAtIndex(kT), 300)
	print(string.format("  built %d chunks near tunnel sample %d in %.2fs", built, kT, secs))
	local c = report("tunnel")
	check((c.TunnelWall or 0) > 0 and (c.TunnelCeiling or 0) > 0, "tunnel parts built")
	check((c.Portal or 0) + (c.PortalLintel or 0) > 0, "tunnel portal built")
	check((c.TunnelLight or 0) > 0, "tunnel lights built")
end
if kB then
	built, secs = buildAround(road:frameAtIndex(kB), 300)
	print(string.format("  built %d chunks near bridge sample %d in %.2fs", built, kB, secs))
	local c = report("bridge")
	check((c.BridgeDeck or 0) > 0 and (c.Parapet or 0) > 0, "bridge parts built")
	check((c.Abutment or 0) > 0, "bridge abutment built")
end

-- voxel shapes smooth terrain can draw cleanly: a partly filled voxel needs
-- a full voxel under it (else it renders as a lumpy blob that can cover the
-- road), and none may hang over air (jagged tunnel roofs)
local AIR, WATER = env.roblox.Enum.Material.Air, env.roblox.Enum.Material.Water
local unsupported, hanging, columns = 0, 0, 0
local latest = {} -- voxel column (world x, z) -> write index, newest wins
for wi, w in terrain.writes do
	local m = w.region.CFrame.Position - w.region.Size / 2
	for ix = 1, #w.materials do
		for iz = 1, #w.materials[1][1] do
			latest[(m.X + ix * 4) .. "," .. (m.Z + iz * 4)] = wi
		end
	end
end
for wi, w in terrain.writes do
	local m = w.region.CFrame.Position - w.region.Size / 2
	local mats, occs = w.materials, w.occupancies
	for ix = 1, #mats do
		for iz = 1, #mats[1][1] do
			if latest[(m.X + ix * 4) .. "," .. (m.Z + iz * 4)] == wi then
				columns += 1
				local topSeen = false
				for iy = #mats[ix], 1, -1 do
					local mat, occ = mats[ix][iy][iz], occs[ix][iy][iz]
					local solid = mat ~= AIR and mat ~= WATER
					if solid and occ < 0.999 then
						local below = iy > 1 and mats[ix][iy - 1][iz] or AIR
						local belowOcc = iy > 1 and occs[ix][iy - 1][iz] or 0
						if below == AIR then
							hanging += 1
						elseif not topSeen and (below == WATER or belowOcc < 0.999) then
							unsupported += 1
						end
					end
					topSeen = topSeen or solid
				end
			end
		end
	end
end
print(string.format("voxel columns %d: unsupported surface voxels %d, hanging partial voxels %d", columns, unsupported, hanging))
check(unsupported == 0, "every partly filled surface voxel sits on a full voxel")
check(hanging == 0, "no partly filled voxel hangs over air")

-- the drawn terrain surface under every road part stays well below its top
local function columnTop(x, z, yMax)
	local key = (math.floor(x / 4) * 4 + 4) .. "," .. (math.floor(z / 4) * 4 + 4)
	local wi = latest[key]
	if not wi then
		return nil
	end
	local w = terrain.writes[wi]
	local m = w.region.CFrame.Position - w.region.Size / 2
	local ix, iz = math.floor((x - m.X) / 4) + 1, math.floor((z - m.Z) / 4) + 1
	for iy = #w.materials[ix], 1, -1 do
		local y0 = m.Y + (iy - 1) * 4
		local mat = w.materials[ix][iy][iz]
		if y0 < yMax and mat ~= AIR and mat ~= WATER and w.occupancies[ix][iy][iz] > 0 then
			return y0 + w.occupancies[ix][iy][iz] * 4
		end
	end
	return nil
end
local worstRoad, roadSamples, worstInfo = -math.huge, 0, ""
for _, d in manager.container:GetDescendants() do
	if d:IsA("BasePart") and d.Name == "Road" then
		for _, f in { -0.5, -0.25, 0, 0.25, 0.5 } do
			for _, t in { -0.45, 0, 0.45 } do
				local p = (d.CFrame * CFrame.new(d.Size.X * f, d.Size.Y / 2, d.Size.Z * t)).Position
				local wp0 = manager:toWorld(p)
				local _, d0 = road:project(wp0.X, wp0.Z)
				-- (strip corners overhang the verge on the outside of bends)
				local top = math.abs(d0) <= Config.Road.HalfWidth + 0.25 and columnTop(p.X, p.Z, p.Y + 6) or nil
				if top then
					roadSamples += 1
					if top - p.Y > worstRoad then
						worstRoad = top - p.Y
						local wp = manager:toWorld(p)
						local s, dd = road:project(wp.X, wp.Z)
						local k = math.floor(s / road.step) + 1
						worstInfo = string.format("s=%.0f d=%.2f tunnel=%s bridge=%s part=%s f=%.2f t=%.2f", s, dd, tostring(road:isTunnel(k)), tostring(road:isBridge(k)), d:GetFullName():sub(-30), f, t)
					end
				end
			end
		end
	end
end
print(string.format("terrain under road parts (%d samples, edges included): max %.2f below the top (%s)", roadSamples, -worstRoad, worstInfo))
check(roadSamples > 100 and worstRoad < -0.6, "terrain stays at least 0.6 below the road top, edges included")

-- 3. rebase: every part moves by exactly -delta
local sample
for _, d in manager.container:GetDescendants() do
	if d:IsA("BasePart") then
		sample = d
		break
	end
end
local before = sample.CFrame.Position
local oldOrigin = manager.origin
manager:requestRebase(Vector3.new(20000, 0, -3000))
for _ = 1, 100 do
	manager:update(10)
	if not manager.rebasing and manager.pendingRebase == nil then
		break
	end
end
local delta = manager.origin - oldOrigin
print("rebase delta", delta, "copies", terrain.copies, "pastes", terrain.pastes)
check(delta.Magnitude > 0, "origin moved")
check((sample.CFrame.Position - (before - delta)).Magnitude < 1e-3, "parts moved with the origin")
check(terrain.copies > 0 and terrain.copies == terrain.pastes, "terrain copied")

if failures == 0 then
	print("ALL CHUNK CHECKS PASSED")
else
	print(failures .. " FAILURES")
	process.exit(1)
end
