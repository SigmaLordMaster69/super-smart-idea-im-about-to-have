--[[
	InfiniteRoadClient
	------------------
	Entry point. Every player generates and drives their own copy of the
	world locally (same seed for everyone on the server), which keeps the
	server idle and lets each client move its floating origin on its own.

	Flow: wait for the seed, pick a quality preset, start the parallel
	terrain workers, build the area around the spawn behind a loading
	screen, drop the vehicle on the road and show the start screen, then
	keep streaming chunks around it every frame while the Environment runs
	seasons and weather. The interface (UI/App.luau) reads and changes the
	game through the `app` table below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("InfiniteRoad")
local Config = require(Shared.Config)
local World = require(Shared.World)

local ChunkManager = require(script.ChunkManager)
local Car = require(script.Car)
local CameraController = require(script.CameraController)
local AutoDrive = require(script.AutoDrive)
local Input = require(script.Input)
local Hud = require(script.Hud)
local Atmosphere = require(script.Atmosphere)
local AssetLibrary = require(script.AssetLibrary)
local Quality = require(script.Quality)
local WorkerPool = require(script.WorkerPool)
local Vehicles = require(script.Vehicles)
local Environment = require(script.Environment)
local Ambience = require(script.Ambience)
local App = require(script.UI.App)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local rc = Config.Road

local SUBTITLES = {
	Meadow = "rolling meadows",
	Forest = "into the woods",
	Mountains = "mountain pass",
	Coast = "coastal cliffs",
	Canyon = "red rock canyon",
	Lake = "lakeside road",
	RiverValley = "river valley",
	Ocean = "island hopping",
}

---------------------------------------------------------------------------
-- Seed, quality and world
---------------------------------------------------------------------------
local seed = Shared:GetAttribute("Seed")
while seed == nil do
	Shared:GetAttributeChangedSignal("Seed"):Wait()
	seed = Shared:GetAttribute("Seed")
end

local hud = Hud.new(seed, playerGui)
Atmosphere.apply(Config)

local qualityMode = Config.Quality.Default
local quality, qualityName = Quality.get(Config, qualityMode)

local world = World.new(Config, seed)

-- premade models from ReplicatedStorage.InfiniteRoadAssets (optional)
local assets = AssetLibrary.new(ReplicatedStorage:FindFirstChild("InfiniteRoadAssets"))
if #assets.summary > 0 then
	print("[InfiniteRoad] using asset pack models: " .. table.concat(assets.summary, ", "))
else
	print("[InfiniteRoad] no asset pack models found, using built-in props")
end

-- season and weather (needs the effect folder in the workspace)
local effects = Instance.new("Folder")
effects.Name = "InfiniteRoadEffects"
effects.Parent = Workspace
local roofParams = RaycastParams.new()
roofParams.FilterType = Enum.RaycastFilterType.Exclude
roofParams.IgnoreWater = true
local environment = Environment.new(Config, {
	lighting = Lighting,
	terrain = Workspace.Terrain,
	parent = effects,
	seed = seed,
	raycast = function(origin, direction)
		return Workspace:Raycast(origin, direction, roofParams)
	end,
})

-- parallel terrain workers (optional, fall back to the main thread)
local pool
local template = script:FindFirstChild("GenWorker")
local workers = quality.Workers or 0
if workers > 0 and template and template:IsA("Actor") then
	local ok, result = pcall(WorkerPool.new, template, workers, seed, script.TerrainBuilder, environment:seasonPreset().terrain, script)
	if ok then
		pool = result
	else
		warn("[InfiniteRoad] could not start terrain workers: " .. tostring(result))
	end
end

local manager = ChunkManager.new(world, Config, Workspace.Terrain, assets, pool)

local function applyQuality()
	quality, qualityName = Quality.get(Config, qualityMode)
	manager:setQuality(quality)
	manager.decorator:setQuality(quality)
	manager.props:setShadows(quality.TreeShadows)
	environment.qualityScale = qualityName == "Low" and 0.45 or (qualityName == "Medium" and 0.7 or 1)
end
applyQuality()

local function applySeason(name, preset)
	manager.props:setSeason(name)
	manager.decorator:setSeason(name)
	manager:setSeason(preset.terrain)
	manager:redecorate()
end
applySeason(environment.season, environment:seasonPreset())
environment.onSeason = function(name, preset)
	applySeason(name, preset)
	hud:toast(name)
end

-- the car replaces the default character controls
task.spawn(function()
	local ok, controls = pcall(function()
		local module = require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		return module:GetControls()
	end)
	if ok and controls then
		controls:Disable()
	end
end)

---------------------------------------------------------------------------
-- Characters: each player drives in their own generated world, so avatars
-- are parked out of sight. (The motorcycle rider is a posed copy of the
-- local avatar, so its original look is remembered.)
---------------------------------------------------------------------------
local function hide(model: Model, anchor: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			if d:GetAttribute("IR_Transparency") == nil then
				d:SetAttribute("IR_Transparency", d.Transparency)
			end
			d.Transparency = 1
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				if anchor then
					d.Anchored = true
				end
			end
		end
	end
end

local function onCharacter(plr: Player, character: Model)
	local isLocal = plr == player
	if not isLocal and not Config.HideOtherPlayers then
		return
	end
	character:WaitForChild("HumanoidRootPart", 10)
	hide(character, isLocal)
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") or d:IsA("Decal") then
			task.defer(hide, character, isLocal)
		end
	end)
end

local function watchPlayer(plr: Player)
	if plr.Character then
		task.spawn(onCharacter, plr, plr.Character)
	end
	plr.CharacterAdded:Connect(function(c)
		onCharacter(plr, c)
	end)
end
for _, plr in Players:GetPlayers() do
	watchPlayer(plr)
end
Players.PlayerAdded:Connect(watchPlayer)

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------
local spawnPos = world.road:frameAt(rc.SpawnDistance)
manager:setOrigin(spawnPos)
manager:setFocus(spawnPos)

local cam = Workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable

local loadRadius = math.min(440, quality.TerrainRadius * 0.6)
while true do
	manager:update(Config.World.LoadingFrameBudget)
	local progress = manager:progress(loadRadius)
	hud:setProgress(progress)
	local p = manager:toRoblox(spawnPos)
	cam.CFrame = CFrame.lookAt(p + Vector3.new(-90, 70, 60), p)
	if progress >= 1 then
		break
	end
	RunService.RenderStepped:Wait()
end

---------------------------------------------------------------------------
-- Vehicle
---------------------------------------------------------------------------
local colorRng = Random.new(player.UserId + seed)
local vehicleId = Vehicles.Default
local function pickColor(id)
	local colors = Vehicles.get(id).colors
	return colors[colorRng:NextInteger(1, #colors)]
end

local vehicleColor = pickColor(vehicleId)
local car = Car.new(Config, vehicleColor, assets, vehicleId)
car.model.Parent = Workspace

-- Roblox-space CFrame in the driving lane at arc length s
local function laneCFrame(s: number): CFrame
	local p, f, r, u = world.road:frameAt(s)
	local pos = manager:toRoblox(p + r * (rc.LaneWidth * 0.5 * rc.DriveSide)) + u * 3.6
	return CFrame.lookAt(pos, pos + f, u)
end

car:teleport(laneCFrame(rc.SpawnDistance))
roofParams.FilterDescendantsInstances = { car.model, effects }

local autodrive = AutoDrive.new(world, Config)
local camera = CameraController.new(Config, world, manager)
local input = Input.new()

local function carS(): number
	local wp = manager:toWorld(car:getCFrame().Position)
	return (world.road:project(wp.X, wp.Z))
end

local function resetCar()
	car:teleport(laneCFrame(math.max(carS(), 40)))
end

-- Swap to vehicle `id` (default: the next one in the list), keeping the
-- position and speed.
local function switchVehicle(id: string?, color: Color3?)
	vehicleId = Vehicles.resolve(id or Vehicles.next(vehicleId))
	vehicleColor = color or pickColor(vehicleId)
	local cf, vel = car:getCFrame(), car:getVelocity()
	local nextCar = Car.new(Config, vehicleColor, assets, vehicleId)
	nextCar.model.Parent = Workspace
	nextCar:teleport(cf + cf.UpVector * 0.5)
	nextCar.chassis.AssemblyLinearVelocity = vel
	car:destroy()
	car = nextCar
	roofParams.FilterDescendantsInstances = { car.model, effects }
	hud:toast(Vehicles.get(vehicleId).name)
end

manager.onRebase = function(delta: Vector3)
	car:shift(delta)
	camera:shift(delta)
end

local function timeLabel()
	local t = Lighting.ClockTime
	return string.format("%02d:%02d", math.floor(t), math.floor((t % 1) * 60))
end

---------------------------------------------------------------------------
-- Interface: `app` is how the start screen, toolbar and settings read and
-- change the game (keys are listed in UI/App.luau)
---------------------------------------------------------------------------
local started = false -- false while the start screen is up
local statsVisible = false
local speedometerOn = true
local units = "km/h"
local currentSection = nil

local getters = {
	vehicle = function()
		return vehicleId
	end,
	color = function()
		return vehicleColor
	end,
	season = function()
		return environment.seasonAuto and "Auto" or environment.season
	end,
	seasonNow = function()
		return environment.season
	end,
	weather = function()
		return environment.weatherAuto and "Auto" or environment.weather.name
	end,
	weatherNow = function()
		return environment.weather.name
	end,
	clock = function()
		return Lighting.ClockTime
	end,
	dayCycle = function()
		return Atmosphere.clockRunning
	end,
	camera = function()
		return camera:mode()
	end,
	autodrive = function()
		return autodrive.enabled
	end,
	quality = function()
		return qualityMode
	end,
	qualityNow = function()
		return qualityName
	end,
	units = function()
		return units
	end,
	speedometer = function()
		return speedometerOn
	end,
	stats = function()
		return statsVisible
	end,
}

local setters = {
	season = function(mode: string)
		environment:setSeason(mode)
	end,
	weather = function(mode: string)
		environment:setWeather(mode)
	end,
	clock = function(t: number)
		Lighting.ClockTime = t
	end,
	dayCycle = function(on: boolean)
		Atmosphere.clockRunning = on
	end,
	camera = function(name: string)
		for _ = 1, #CameraController.Modes do
			if camera:mode() == name then
				break
			end
			camera:cycle()
		end
	end,
	autodrive = function(on: boolean)
		autodrive:setEnabled(on)
	end,
	quality = function(mode: string)
		if mode ~= qualityMode then
			qualityMode = mode
			applyQuality()
			manager:redecorate()
		end
	end,
	units = function(name: string)
		units = name
		hud:setUnits(name)
	end,
	speedometer = function(on: boolean)
		speedometerOn = on
		hud:setSpeedometer(on)
	end,
	stats = function(on: boolean)
		statsVisible = on
		hud:setStats(on and "" or nil)
	end,
}

local app = {
	get = function(key: string)
		return getters[key]()
	end,
	set = function(key: string, value)
		setters[key](value)
	end,
	setVehicle = function(id: string, color: Color3?)
		if id ~= vehicleId or color ~= vehicleColor then
			switchVehicle(id, color)
		end
	end,
	reset = function()
		resetCar()
		hud:toast("Back on the road")
	end,
	start = function(withAutodrive: boolean)
		started = true
		autodrive:setEnabled(withAutodrive)
		hud:setVisible(true)
		currentSection = nil -- show the region banner now
	end,
}

local ui = App.new(playerGui, app, { hud = hud, input = input, seed = seed })

-- keyboard and gamepad shortcuts (optional; everything is also clickable)
local actions = {
	autodrive = function()
		setters.autodrive(not autodrive.enabled)
		hud:toast(autodrive.enabled and "Autodrive on" or "Autodrive off")
	end,
	camera = function()
		hud:toast("Camera: " .. camera:cycle())
	end,
	reset = app.reset,
	time = function()
		Atmosphere.nextPreset()
		hud:toast("Time " .. timeLabel())
	end,
	photo = function()
		ui:togglePhoto()
	end,
	stats = function()
		setters.stats(not statsVisible)
	end,
	vehicle = function()
		switchVehicle()
	end,
	season = function()
		hud:toast("Season: " .. environment:cycleSeason())
	end,
	weather = function()
		hud:toast("Weather: " .. environment:cycleWeather())
	end,
	menu = function()
		ui:toggleSettings()
	end,
	back = function()
		ui:back()
	end,
	confirm = function()
		ui:confirm()
	end,
}
for name, fn in actions do
	input:on(name, function()
		-- on the start screen only Enter does anything
		if started or name == "confirm" then
			fn()
			ui:refresh()
		end
	end)
end

-- birds, surf or a breeze depending on the landscape
local ambience = Ambience.new(Config, Workspace.CurrentCamera)

---------------------------------------------------------------------------
-- Per-frame
---------------------------------------------------------------------------
local function physicsStep(dt: number)
	local throttle, steer, handbrake = input:read()
	if not started then
		-- parked behind the start screen
		throttle, steer, handbrake = 0, 0, true
	elseif autodrive.enabled then
		if math.abs(throttle) > 0.2 or math.abs(steer) > 0.2 then
			autodrive:setEnabled(false)
			hud:toast("Autodrive off")
			ui:refresh()
		else
			local cf = car:getCFrame()
			throttle, steer = autodrive:compute(manager:toWorld(cf.Position), cf.LookVector, cf.RightVector, car.speed, car:maxSteer())
			handbrake = false
		end
	end
	car:step(dt, throttle, steer, handbrake)
end

local ok = pcall(function()
	RunService.PreSimulation:Connect(physicsStep)
end)
if not ok then
	RunService.Stepped:Connect(function(_, dt)
		physicsStep(dt)
	end)
end

RunService:BindToRenderStep("InfiniteRoadCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
	car:render(dt)
	camera:update(dt, car)
end)

local report = Shared:WaitForChild("ReportDistance", 5)
local traveled = 0
local lastS = rc.SpawnDistance
local lastReport = os.clock()
local upsideDown = 0
local frames, lastStats = 0, os.clock()
local infoTimer = 0
local uiTimer = 0

RunService.Heartbeat:Connect(function(dt)
	local cf = car:getCFrame()
	local vel = car:getVelocity()
	local worldPos = manager:toWorld(cf.Position)
	manager:setFocus(worldPos + vel * Config.World.LookAhead, cf.LookVector)
	manager:step(dt)

	local p = cf.Position
	if Vector2.new(p.X, p.Z).Magnitude > Config.World.RebaseDistance then
		manager:requestRebase(p)
	end

	local s = world.road:project(worldPos.X, worldPos.Z)
	local ds = s - lastS
	if ds > 0 and ds < 60 then
		traveled += ds
	end
	lastS = s
	hud:update(car.speed, traveled)
	hud:setBadge(autodrive.enabled and "AUTODRIVE" or "")

	local sec = world.sections:get(s)
	if sec ~= currentSection then
		currentSection = sec
		local sub = SUBTITLES[sec.type] or ""
		if sec.type == "Forest" and sec.autumn then
			sub = "autumn woods"
		end
		hud:showRegion(sec.name, sub)
	end

	-- flipped over or fell into the water: put the vehicle back
	if cf.UpVector.Y < 0.2 or p.Y < Config.SeaLevel - 25 then
		upsideDown += dt
		if upsideDown > 2.5 then
			upsideDown = 0
			resetCar()
		end
	else
		upsideDown = 0
	end

	-- season and weather
	Atmosphere.step(dt, Config)
	environment:step(dt, Workspace.CurrentCamera.CFrame, vel)
	car:setSurface(environment:gripScale(), environment:wetness())
	local clock = Lighting.ClockTime
	local night = 1 - math.clamp((math.sin((clock - 6) / 12 * math.pi) + 0.12) / 0.4, 0, 1)
	ambience:step(dt, sec.type, environment.weather.cur.rain, night, environment.weather.covered)
	manager.roadBuilder.wetness = environment:wetness()
	infoTimer -= dt
	if infoTimer <= 0 then
		infoTimer = 1
		hud:setInfo(string.format("%s  ·  %s  ·  %s", environment.season, environment.weather.name, timeLabel()))
	end
	-- keep the toolbar and menus in step with auto seasons, weather and time
	uiTimer -= dt
	if uiTimer <= 0 then
		uiTimer = 0.5
		ui:refresh()
	end

	frames += 1
	if statsVisible and os.clock() - lastStats > 0.5 then
		local fps = frames / (os.clock() - lastStats)
		frames, lastStats = 0, os.clock()
		local st = manager.stats
		local k = math.floor(s / rc.SampleSpacing) + 1
		hud:setStats(string.format(
			"%d fps   generation %.1f ms (budget %.1f)   quality %s\n"
				.. "chunks %d loaded, %d waiting   built %d   refreshed %d   rebases %d\n"
				.. "workers %s   parallel jobs %d\n"
				.. "s = %.0f   world (%.0f, %.0f)   %s (%s)   %s%s\n"
				.. "%s   wetness %.2f   grip x%.2f   wheels on ground %d",
			fps, manager.lastWork * 1000, manager.budget * 1000, qualityName,
			manager:loadedCount(), manager:pendingCount(), st.built, st.refreshed, st.rebases,
			pool and (pool.broken and "off (fell back)" or tostring(pool.readyCount) .. " ready") or "none", st.parallel,
			s, worldPos.X, worldPos.Z, sec.name, sec.type,
			world.road:isTunnel(k) and "tunnel " or "", world.road:isBridge(k) and "bridge " or "",
			environment:label(), environment:wetness(), environment:gripScale(), car.grounded
		))
	elseif not statsVisible then
		frames, lastStats = 0, os.clock()
	end

	if report and os.clock() - lastReport > 5 then
		lastReport = os.clock()
		report:FireServer(traveled * 0.00028)
	end
end)

hud:finishLoading()
