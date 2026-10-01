--[[
	Scenic systems test: seasons (terrain snow and ice, seasonal trees,
	decoration rules), weather and environment stepping, the motorcycle, and
	the parallel worker path of ChunkManager (driven by a fake pool that
	answers asynchronously, like the GenWorker actors do).
	  lune run tools/test_scenic [seed]
]]

local process = require("@lune/process")
local env = require("./env")
local roblox = env.roblox
local Instance, Vector3, CFrame, Color3, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum

local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")
local Seasons = env.require("src/client/Seasons")
local Weather = env.require("src/client/Weather")
local Environment = env.require("src/client/Environment")
local TerrainBuilder = env.require("src/client/TerrainBuilder")
local Props = env.require("src/client/Props")
local ChunkManager = env.require("src/client/ChunkManager")
local Car = env.require("src/client/Car")
local Quality = env.require("src/client/Quality")

local seed = tonumber(process.args[1]) or 12345
local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local terrain = env.terrain
local function materialCounts()
	local counts = {}
	for _, w in terrain.writes do
		for _, plane in w.materials do
			for _, row in plane do
				for _, m in row do
					if m ~= Enum.Material.Air then
						counts[m.Name] = (counts[m.Name] or 0) + 1
					end
				end
			end
		end
	end
	return counts
end

---------------------------------------------------------------------------
-- 1. seasonal terrain: winter snow on flat ground, frozen river
---------------------------------------------------------------------------
local world = World.new(Config, seed)
local road = world.road
road:ensureFlags(4000)
local river
for _, c in world.sections.crossings do
	if c.kind == "river" then
		river = c
		break
	end
end
check(river ~= nil, "a river crossing exists in the first 16 km")

local size = Config.World.ChunkSize
local function buildArea(builder, centre)
	terrain.writes = {}
	local cx0, cz0 = math.floor(centre.X / size), math.floor(centre.Z / size)
	for cz = cz0 - 1, cz0 + 1 do
		for cx = cx0 - 1, cx0 + 1 do
			builder:build(cx, cz, Vector3.zero)
		end
	end
	return materialCounts()
end

if river then
	local centre = road:frameAt(river.s)
	local builder = TerrainBuilder.new(world, Config, terrain)
	local summer = buildArea(builder, centre)
	builder:setSeason(Seasons.Presets.Winter.terrain)
	local winter = buildArea(builder, centre)
	print(string.format("river at s=%d: summer Water=%d Snow=%d Grass=%d | winter Water=%d Ice=%d Snow=%d Grass=%d", river.s, summer.Water or 0, summer.Snow or 0, summer.Grass or 0, winter.Water or 0, winter.Ice or 0, winter.Snow or 0, winter.Grass or 0))
	check((summer.Water or 0) > 0 and (summer.Ice or 0) == 0, "summer river is water")
	check((winter.Ice or 0) > 0, "winter river is frozen")
	check((winter.Snow or 0) > (summer.Snow or 0) * 2 + 50, "winter covers flat ground in snow")
	check((winter.Grass or 0) < (summer.Grass or 0) * 0.5, "winter hides most grass")
	check((winter.Asphalt or 0) == (summer.Asphalt or 0), "the road bed stays asphalt in winter")
	builder:setSeason(Seasons.Presets.Summer.terrain)
	local back = buildArea(builder, centre)
	check((back.Ice or 0) == 0 and (back.Snow or 0) == (summer.Snow or 0), "summer again matches the first build")
end

-- every preset is complete
for _, name in Seasons.Order do
	local p = Seasons.Presets[name]
	check(p.terrain and p.grip and p.weather and p.materials, name .. " preset complete")
	for w in p.weather do
		check(Weather.Presets[w] ~= nil, name .. " weather weight names a real weather: " .. w)
	end
end
check(Seasons.next("Winter") == "Spring", "seasons wrap around")

---------------------------------------------------------------------------
-- 2. seasonal trees
---------------------------------------------------------------------------
local props = Props.new(nil)
local function signature(model)
	local parts, colors = 0, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			local c = d.Color
			table.insert(colors, string.format("%d,%d,%d", c.R * 255, c.G * 255, c.B * 255))
		end
	end
	table.sort(colors)
	return parts .. ":" .. table.concat(colors, ";")
end
local sigs = {}
for _, season in Seasons.Order do
	props:setSeason(season)
	sigs[season] = {}
	for _, kind in { "oak", "birch", "pine", "bush" } do
		local ok, model = pcall(props.tree, props, kind, 2, 1, false)
		check(ok, string.format("%s %s builds: %s", season, kind, tostring(model)))
		if ok then
			sigs[season][kind] = signature(model)
		end
	end
	local okFar = pcall(props.tree, props, "oak", 3, 2, true)
	check(okFar, season .. " far oak builds")
end
for _, season in { "Spring", "Autumn", "Winter" } do
	check(sigs[season].oak ~= sigs.Summer.oak, season .. " oaks look different from summer")
end
check(sigs.Winter.birch ~= sigs.Summer.birch, "winter birches look different")
props:setShadows(false)
props:setSeason("Summer")
local noShadow = props:tree("oak", 2, 1, false)
for _, d in noShadow:GetDescendants() do
	if d:IsA("BasePart") then
		check(d.CastShadow == false, "tree shadows off on low quality")
		break
	end
end

---------------------------------------------------------------------------
-- 3. weather and environment
---------------------------------------------------------------------------
local lighting = Instance.new("Folder")
lighting.Name = "Lighting"
-- Lighting-like properties live on the real service; use a DataModel one
local dataModel = Instance.new("DataModel")
local realLighting = dataModel:GetService("Lighting")
local effects = Instance.new("Folder")
local clouds = Instance.new("Folder") -- clouds go under this "terrain"
local rayCalls = 0
local weather = Weather.new(Config, {
	lighting = realLighting,
	terrain = clouds,
	parent = effects,
	raycast = function()
		rayCalls += 1
		return nil
	end,
})
check(realLighting:FindFirstChildOfClass("Atmosphere") ~= nil, "atmosphere created")
check(realLighting:FindFirstChildOfClass("SunRaysEffect") ~= nil, "sun rays created")
check(clouds:FindFirstChildOfClass("Clouds") ~= nil, "clouds created")

local camCF = CFrame.lookAt(Vector3.new(0, 60, 0), Vector3.new(100, 50, 0))
local vel = Vector3.new(80, 0, 0)
local function run(seconds, clock, ambient)
	local dt = 1 / 30
	for _ = 1, math.floor(seconds / dt) do
		weather:step(dt, camCF, vel, clock, ambient, 1)
	end
end
for _, name in Weather.Types do
	weather:set(name)
	run(4, 12)
end
weather:set("Clear", true)
run(1, 12)
local clearCover = weather.clouds.Cover
local clearRays = weather.rays.Intensity
weather:set("Storm")
run(60, 12)
print(string.format("storm after 60s: cover %.2f rain rate %.0f wetness %.2f brightness %.2f rays %.3f", weather.clouds.Cover, weather.rainEmitter.Rate, weather.wetness, realLighting.Brightness, weather.rays.Intensity))
check(weather.clouds.Cover > clearCover + 0.3, "storm clouds cover the sky")
check(weather.rainEmitter.Rate > 400, "it rains in a storm")
check(weather.wetness > 0.5, "roads get wet in a storm")
check(weather.rays.Intensity < clearRays, "sun rays fade under storm clouds")
check(rayCalls > 0, "roof check runs")
-- lightning builds a bolt and cleans it up
weather:strike(camCF)
local bolt = weather.folder:FindFirstChild("Lightning")
check(bolt ~= nil and #bolt:GetChildren() >= 14, "lightning bolt built")
check(weather.flash > 0.9, "lightning flash")

-- under a roof: no rain
weather.raycast = function()
	return { Position = Vector3.zero }
end
run(1, 12)
check(weather.rainEmitter.Rate == 0, "no rain under a roof")
weather.raycast = nil
weather.covered = false

-- drying out
weather:set("Clear")
run(200, 12)
check(weather.wetness < 0.2, "roads dry after the rain")
check(weather.rainEmitter.Rate < 1, "rain stops")

-- sunrise light is warm, night is dark
weather:set("Clear", true)
run(1, 6.6)
local sunriseRays = weather.rays.Intensity
local sunriseTint = weather.grade.TintColor
run(1, 1)
check(realLighting.OutdoorAmbient.B > realLighting.OutdoorAmbient.R, "night ambient is blue")
check(sunriseTint.R > sunriseTint.B, "sunrise grading is warm")
check(weather.rays.Intensity < sunriseRays, "no sun rays at night")
run(1, 12)
check(weather.rays.Intensity > 0, "sun rays at noon")

-- seasonal particles
run(1, 12, "leaves")
check(weather.leafEmitter.Rate > 0 and weather.petalEmitter.Rate == 0, "autumn leaves drift")
run(1, 12, "petals")
check(weather.petalEmitter.Rate > 0 and weather.leafEmitter.Rate == 0, "spring petals drift")

local wet, reflect = Weather.wetLook(Config.Road.AsphaltColor, 1)
check(wet.R < Config.Road.AsphaltColor.R + 0.001 and reflect > 0.2, "wet asphalt is darker and reflective")

-- environment: seasons roll, winter turns rain into snow
local envEffects = Instance.new("Folder")
local environment = Environment.new(Config, { lighting = realLighting, terrain = Instance.new("Folder"), parent = envEffects, seed = seed })
local seen = {}
environment.onSeason = function(name)
	table.insert(seen, name)
end
environment:setSeason("Autumn")
environment:setWeather("Rain")
check(environment.season == "Autumn" and not environment.seasonAuto, "season locked")
environment:setSeason("Winter")
check(environment.weather.name == "Snow", "rain turns to snow in winter")
check(environment:gripScale() < 0.85, "winter grip is lower")
environment:setSeason("Summer")
environment:setWeather("Auto")
environment:setSeason("Auto")
environment.seasonTimer = 0.01
environment:step(0.1, camCF, vel)
check(environment.season == "Autumn", "auto season advanced to autumn, got " .. environment.season)
check(#seen >= 3, "season callbacks fired")
local picks = {}
for _ = 1, 200 do
	picks[environment:_pickWeather()] = true
end
check(not picks.Snow, "no snow outside winter")
local labels = {}
for _ = 1, #Weather.Types + 1 do
	labels[environment:cycleWeather()] = true
end
check(labels.Auto and labels.Storm, "weather menu cycles through the types")
for _ = 1, 30 do
	environment:step(1 / 30, camCF, vel)
end
check(type(environment:label()) == "string", "environment label")

---------------------------------------------------------------------------
-- 4. motorcycle
---------------------------------------------------------------------------
local bike = Car.new(Config, Color3.new(0.8, 0.1, 0.1), nil, "Motorcycle")
check(bike.kind == "Motorcycle", "bike kind")
check(bike.leanRoot ~= nil and bike.leanWeld ~= nil, "bike lean rig")
check(bike.frontWheel ~= nil and bike.rearWheel ~= nil, "bike wheels")
check(#bike.wheels == 4, "bike keeps four physics corners")
local riderParts = 0
for _, d in bike.model:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("IR_Rider") then
		riderParts += 1
	end
end
check(riderParts >= 5, "blocky rider built when there is no avatar")
check(math.abs(bike.chassis.Size.X - Config.Motorcycle.ChassisSize.X) < 0.01, "bike chassis size")
check(bike.config.TopSpeed == Config.Motorcycle.TopSpeed and bike.config.Acceleration == Config.Motorcycle.Acceleration, "bike tuning")
-- render a fake left turn: the bike leans left (its up vector tilts to -X)
bike.speed = 120
bike.chassis.AssemblyAngularVelocity = Vector3.new(0, 0.6, 0)
bike:setSurface(1, 0.8)
for _ = 1, 90 do
	bike:render(1 / 60)
end
local leanCF = bike.leanWeld.C0
print(string.format("bike lean %.1f deg at 120 studs/s, yaw 0.6 rad/s", math.deg(bike.lean)))
check(bike.lean > math.rad(10) and bike.lean <= Config.Motorcycle.LeanMax + 1e-6, "bike leans into the turn")
check(leanCF.UpVector.X < -0.1, "lean tilts the bike's top towards the inside of the turn")
check(bike.sprayEmitters[1].Rate > 0, "wet road spray behind the bike")
bike.speed = 0
bike.chassis.AssemblyAngularVelocity = Vector3.zero
for _ = 1, 120 do
	bike:render(1 / 60)
end
check(math.abs(bike.lean) < math.rad(1), "bike stands up again when stopped")
check(bike:steerLock() == Config.Motorcycle.MaxSteerLow, "bike steering lock at standstill")
-- autodrive gets the lock for its 9.8 stud reference wheelbase
check(math.abs(bike:maxSteer() - Config.Motorcycle.MaxSteerLow) < 1e-9, "bike steering lock at standstill")

local car = Car.new(Config, Color3.new(0, 0, 1), nil, "Car")
check(car.kind == "Car" and car.wheels[1].part ~= nil, "car still builds")
car:render(1 / 60)

---------------------------------------------------------------------------
-- 5. quality presets
---------------------------------------------------------------------------
for _, name in Config.Quality.Order do
	local q = Quality.get(Config, name)
	check(q.TerrainRadius and q.Workers and q.BudgetMin and q.BudgetMax and q.DecorDensity, name .. " preset complete")
end
check(Quality.next(Config, "Ultra") == "Low", "quality cycles")

---------------------------------------------------------------------------
-- 6. parallel path: a fake pool that answers a couple of polls later
---------------------------------------------------------------------------
local FakePool = {}
FakePool.__index = FakePool
function FakePool.new(slots, delayPolls)
	local self = setmetatable({}, FakePool)
	self.slots = slots
	self.delay = delayPolls
	self.jobs = {}
	self.nextId = 0
	self.broken = false
	self.season = nil
	self.dispatched = 0
	self.failNext = 0
	self.builder = TerrainBuilder.new(World.new(Config, seed), Config, terrain) -- the worker's own copy
	return self
end
function FakePool:inflight()
	local n = 0
	for _ in self.jobs do
		n += 1
	end
	return n
end
function FakePool:free()
	return self.slots - self:inflight()
end
function FakePool:dispatch(key, cx, cz, origin)
	self.nextId += 1
	self.dispatched += 1
	self.jobs[self.nextId] = { key = key, cx = cx, cz = cz, origin = origin, wait = self.delay }
	return self.nextId
end
function FakePool:setSeason(season)
	self.season = season
	self.builder:setSeason(season)
end
function FakePool:poll()
	local out = {}
	for id, job in self.jobs do
		job.wait -= 1
		if job.wait <= 0 then
			self.jobs[id] = nil
			if self.failNext > 0 then
				self.failNext -= 1
				table.insert(out, { jobId = id, key = job.key, ok = false })
			else
				local data = self.builder:build(job.cx, job.cz, job.origin)
				table.insert(out, { jobId = id, key = job.key, ok = true, data = data })
			end
		end
	end
	return out
end

terrain.writes = {}
local pool = FakePool.new(3, 2)
local pworld = World.new(Config, seed)
local manager = ChunkManager.new(pworld, Config, terrain, nil, pool)
local spawn = pworld.road:frameAt(Config.Road.SpawnDistance)
manager:setOrigin(spawn)
manager:setFocus(spawn)
local function drive(radius, maxSteps)
	for _ = 1, maxSteps do
		manager:update(0.05)
		if manager:progress(radius) >= 1 and pool:inflight() == 0 and #manager.finished == 0 then
			return true
		end
	end
	return false
end
pool.failNext = 2 -- the first two jobs fail and must be rebuilt locally
local loaded = drive(300, 20000)
print(string.format("parallel: loaded=%s built %d, dispatched %d, parallel %d, writes %d", tostring(loaded), manager.stats.built, pool.dispatched, manager.stats.parallel, #terrain.writes))
check(loaded, "parallel path loads the spawn area")
check(pool.dispatched > 10, "terrain jobs went to the pool")
check(manager.stats.built >= pool.dispatched - 2, "every dispatched chunk finished")
local roads = 0
for _, rec in manager.chunks do
	check(rec.data ~= nil and rec.jobId == nil, "chunk finished with data")
	if rec.road then
		roads += 1
	end
end
check(roads == manager.stats.built, "every built chunk has its road folder")

-- season change: loaded chunks are refreshed through the pool
local before = pool.dispatched
manager:setSeason(Seasons.Presets.Winter.terrain)
check(pool.season == Seasons.Presets.Winter.terrain, "season forwarded to the workers")
drive(300, 20000)
for _ = 1, 4000 do
	manager:update(0.05)
	local stale = false
	for _, rec in manager.chunks do
		stale = stale or rec.stale == true or rec.jobId ~= nil
	end
	if not stale then
		break
	end
end
print(string.format("season refresh: refreshed %d via %d jobs", manager.stats.refreshed, pool.dispatched - before))
check(manager.stats.refreshed > 0 and pool.dispatched > before, "stale chunks rebuilt by the workers")

-- a rebase waits for in-flight jobs
local far = pworld.road:frameAt(Config.Road.SpawnDistance + 600)
manager:setFocus(far)
for _ = 1, 3 do
	manager:update(0.05)
end
manager:requestRebase(manager:toRoblox(far))
local sawInflightWait = pool:inflight() > 0
for _ = 1, 200 do
	manager:update(0.05)
	if manager.stats.rebases > 0 then
		break
	end
	check(pool:inflight() >= 0, "inflight count")
end
check(manager.stats.rebases == 1, "rebase ran once the workers were idle")
check(not sawInflightWait or pool:inflight() == 0, "no jobs in flight across a rebase")

-- a broken pool falls back to the main thread
pool.broken = true
local builtBefore = manager.stats.built
manager:setFocus(pworld.road:frameAt(Config.Road.SpawnDistance + 1200))
for _ = 1, 400 do
	manager:update(0.05)
end
check(manager.stats.built > builtBefore, "main-thread fallback keeps building")

---------------------------------------------------------------------------
-- 7. waterfalls where a river runs off an edge (seed 777 has some near
-- s = 26600..29200)
---------------------------------------------------------------------------
local Waterfalls = env.require("src/client/Waterfalls")
local fworld = World.new(Config, 777)
local ftb = TerrainBuilder.new(fworld, Config, terrain)
local fseen, fallCount, sheetCount, badSheets = {}, 0, 0, 0
local fallFolder = Instance.new("Folder")
for s = 26400, 29400, 96 do
	local p = fworld.road:frameAt(s)
	for _, off in { -1, 0, 1 } do
		local cx, cz = math.floor(p.X / size), math.floor(p.Z / size) + off
		local k = cx .. "," .. cz
		if not fseen[k] then
			fseen[k] = true
			local job = ftb:compute(cx, cz, Vector3.zero)
			ftb:release(job)
			fallCount += Waterfalls.build(job.data, fworld.sampler, Vector3.zero, fallFolder, false, { Waterfall = "rbxassetid://1" })
		end
	end
end
for _, d in fallFolder:GetDescendants() do
	if d:IsA("BasePart") and d.Name == "Sheet" then
		sheetCount += 1
		local c = d.CFrame.Position
		local ground = fworld.sampler:groundAt(c.X, c.Z)
		-- the sheet runs over the ground: never buried, never far above it
		if c.Y < ground - 1.5 or c.Y > ground + 12 then
			badSheets += 1
		end
	end
end
local foams, sprays, sounds = 0, 0, 0
for _, d in fallFolder:GetDescendants() do
	if d:IsA("ParticleEmitter") then
		foams += d.Name == "Foam" and 1 or 0
		sprays += d.Name == "Spray" and 1 or 0
	elseif d:IsA("Sound") then
		sounds += 1
	end
end
print(string.format("waterfalls: %d falls, %d sheet parts (%d off the ground), %d foam, %d spray, %d sounds", fallCount, sheetCount, badSheets, foams, sprays, sounds))
check(fallCount > 0, "waterfalls found where rivers run off edges")
check(badSheets == 0, "waterfall sheets follow the ground")
check(foams == fallCount and sprays == fallCount and sounds == fallCount, "every waterfall has foam, spray and sound")
local iceFolder = Instance.new("Folder")
local icy = 0
for k in fseen do
	local cx, cz = string.match(k, "(-?%d+),(-?%d+)")
	local job = ftb:compute(tonumber(cx), tonumber(cz), Vector3.zero)
	ftb:release(job)
	icy += Waterfalls.build(job.data, fworld.sampler, Vector3.zero, iceFolder, true)
end
local iceEmitters, iceParts = 0, 0
for _, d in iceFolder:GetDescendants() do
	if d:IsA("ParticleEmitter") then
		iceEmitters += 1
	elseif d:IsA("BasePart") and d.Material == Enum.Material.Ice then
		iceParts += 1
	end
end
check(icy == fallCount and iceEmitters == 0 and iceParts > 0, "frozen waterfalls are still icefalls")

---------------------------------------------------------------------------
-- 8. ocean region: bridges and causeways between palm islands
---------------------------------------------------------------------------
local oworld = World.new(Config, 1811976718)
local oroad = oworld.road
local oSec
for i = 1, 12 do
	oworld.sections:ensure(i * 6000)
	local sec = oworld.sections.list[i]
	if sec and sec.type == "Ocean" then
		oSec = sec
		break
	end
end
check(oSec ~= nil, "an ocean region on this seed")
if oSec then
	local k0, k1 = math.floor((oSec.startS + 500) / oroad.step), math.floor((oSec.endS - 500) / oroad.step)
	oroad:ensureFlags(k1 + 2)
	local bridges, dry, wetSides = 0, 0, 0
	for k = k0, k1 do
		if oroad:isBridge(k) then
			bridges += 1
		elseif not oroad:isTunnel(k) then
			dry += 1
			local p, _, r = oroad:frameAtIndex(k)
			local _, wl = oworld.sampler:groundAt(p.X + r.X * 70, p.Z + r.Z * 70)
			local _, wr = oworld.sampler:groundAt(p.X - r.X * 70, p.Z - r.Z * 70)
			if wl > -math.huge and wr > -math.huge then
				wetSides += 1
			end
		end
	end
	local n = k1 - k0 + 1
	print(string.format("ocean %s: %.0f%% bridge, %.0f%% causeway/island (%d samples with sea on both sides)", oSec.name, bridges / n * 100, dry / n * 100, wetSides))
	check(bridges > n * 0.15 and dry > n * 0.1, "ocean road mixes bridges with causeways and islands")
	check(wetSides > 0, "causeways with sea on both sides")
	-- palms on the islands
	local om = ChunkManager.new(oworld, Config, terrain)
	local mid = oroad:frameAt((oSec.startS + oSec.endS) / 2)
	om:setOrigin(mid)
	local palms = 0
	for _, sFrac in { 0.3, 0.5, 0.7, 0.9 } do
		om:setFocus(oroad:frameAt(oSec.startS + (oSec.endS - oSec.startS) * sFrac))
		om.wantedFocus = nil
		for _ = 1, 6000 do
			om:update(0.05)
			if om:progress(200) >= 1 then
				break
			end
		end
	end
	for _, d in om.container:GetDescendants() do
		if d:IsA("Model") and (d.Name == "Palm" or d.Name == "PalmFar") then
			palms += 1
		end
	end
	print("ocean palms placed:", palms)
	check(palms > 10, "palms grow on the ocean islands")
end

---------------------------------------------------------------------------
-- 9. sounds: plain ids, loop regions, lists; region ambience
---------------------------------------------------------------------------
local SoundUtil = env.require("src/client/SoundUtil")
local Ambience = env.require("src/client/Ambience")
local sf = Instance.new("Folder")
check(SoundUtil.make("", sf, 1, true) == nil, "empty sound id is silence")
local plain = SoundUtil.make("rbxassetid://80317022777602", sf, 0.5, true)
check(plain and plain.Looped and plain.Volume == 0.5 and not plain.PlaybackRegionsEnabled, "plain looping sound")
local region = SoundUtil.make({ Id = "rbxassetid://9112952432", Loop = { 19.36, 34.54 }, Gain = 3 }, sf, 0.5, true)
check(region and region.PlaybackRegionsEnabled and math.abs(region.LoopRegion.Min - 19.36) < 1e-6 and region.LoopRegion.Max > 34.5, "loop region set")
check(region and math.abs(region.Volume - 1.5) < 1e-6, "gain applied")
SoundUtil.setVolume(region, 5)
check(region.Volume == 10, "volume capped at 10")
local picks = {}
for _ = 1, 40 do
	local sId = SoundUtil.id(SoundUtil.pick({ "rbxassetid://1", { Id = "rbxassetid://2" } }))
	picks[sId] = true
end
check(picks["rbxassetid://1"] and picks["rbxassetid://2"], "lists pick among their entries")

local ambConfig = { Sounds = { Birds = "rbxassetid://9116970949", Surf = "rbxassetid://9119676058", Breeze = { Id = "rbxassetid://9114057104", Loop = { 3.6, 29.82 }, Gain = 6 } } }
local amb = Ambience.new(ambConfig, sf)
for _ = 1, 300 do
	amb:step(1 / 30, "Forest", 0, 0, false)
end
check(amb.sounds.Birds.Volume > 0.35 and amb.sounds.Surf.Volume < 0.01, "birds in the forest")
for _ = 1, 400 do
	amb:step(1 / 30, "Ocean", 0, 0, false)
end
check(amb.sounds.Surf.Volume > 0.3 and amb.sounds.Birds.Volume < 0.05, "surf on the ocean")
for _ = 1, 400 do
	amb:step(1 / 30, "Canyon", 0, 0, true)
end
check(amb.sounds.Breeze.Volume > 0 and amb.sounds.Breeze.Volume < 0.4 * 6 * 0.35, "breeze in the canyon, muffled in a tunnel")

local wFolder = Instance.new("Folder")
local sw = Weather.new({
	Weather = Config.Weather, Textures = Config.Textures, Road = Config.Road, Sky = Config.Sky,
	Sounds = { Rain = "rbxassetid://1516791621", Thunder = { "rbxassetid://9116282544", { Id = "rbxassetid://9120016241" } } },
}, { lighting = realLighting, parent = wFolder })
check(sw.rainSound ~= nil and sw.thunder ~= nil, "rain loop and thunder list set up")
sw:set("Storm", true)
for _ = 1, 30 do
	sw:step(1 / 30, camCF, vel, 12, nil, 1)
end
check(sw.rainSound.Volume > 0.3, "rain loop audible in a storm")

---------------------------------------------------------------------------
-- 10. rain and snow surround the camera (so driving fast doesn't outrun
-- them), and first person on a bike hides the rider's head
---------------------------------------------------------------------------
local fastCam = CFrame.lookAt(Vector3.new(500, 80, 0), Vector3.new(600, 80, 0))
weather:set("Storm", true)
weather:step(1 / 30, fastCam, Vector3.new(150, 0, 0), 12, nil, 1)
local box = weather.skyPart
local bottom = box.CFrame.Position.Y - box.Size.Y / 2
local top = box.CFrame.Position.Y + box.Size.Y / 2
check(bottom < 80 and top > 120, "rain spawns from below eye level to well above")
local ahead = box.CFrame.Position.X - 500
check(ahead > 0 and ahead - box.Size.X / 2 < 0, "rain box reaches from behind the camera to far ahead at speed")
check(weather.rainEmitter.ShapeStyle == Enum.ParticleEmitterShapeStyle.Volume, "rain spawns throughout the box")
check(weather.snowEmitter.Parent == weather.snowPart and weather.snowPart.CFrame.Position.Y - weather.snowPart.Size.Y / 2 < 80, "snow has its own low box")

local CameraController = env.require("src/client/CameraController")
local fpBike = Car.new(Config, Color3.new(1, 0, 0), nil, "Sportbike")
local camState = {}
-- (Lune has no default for LocalTransparencyModifier until it is set)
local function ltm(d)
	local ok, v = pcall(function()
		return d.LocalTransparencyModifier
	end)
	return ok and v or 0
end
CameraController._hideRider(camState, fpBike, true)
local hiddenNames, shownArms = {}, false
for _, d in fpBike.bikeParts:GetDescendants() do
	if d:IsA("BasePart") and d:GetAttribute("IR_Rider") then
		if ltm(d) == 1 then
			hiddenNames[d.Name] = true
		elseif d.Name == "RiderForearm" then
			shownArms = true
		end
	end
end
check(hiddenNames.RiderHelmet and hiddenNames.RiderVisor and hiddenNames.RiderTorso, "first person hides the rider's helmet and torso")
check(shownArms, "first person keeps the rider's arms")
CameraController._hideRider(camState, fpBike, false)
local still = 0
for _, d in fpBike.bikeParts:GetDescendants() do
	if d:IsA("BasePart") and ltm(d) ~= 0 then
		still += 1
	end
end
check(still == 0, "leaving first person shows the rider again")

if failures == 0 then
	print("ALL SCENIC CHECKS PASSED")
else
	print(failures .. " FAILURES")
	process.exit(1)
end
