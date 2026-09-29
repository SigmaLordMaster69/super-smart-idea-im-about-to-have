--[[
	InfiniteRoadClient
	------------------
	Entry point. Every player generates and drives their own copy of the
	world locally (same seed for everyone on the server), which keeps the
	server idle and lets each client move its floating origin on its own.

	Flow: wait for the seed, build the area around the spawn behind a
	loading screen, drop the car on the road, then keep streaming chunks
	around the car every frame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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

local player = Players.LocalPlayer
local rc = Config.Road

local SUBTITLES = {
	Meadow = "rolling meadows",
	Forest = "into the woods",
	Mountains = "mountain pass",
	Coast = "coastal cliffs",
	Canyon = "red rock canyon",
	Lake = "lakeside road",
	RiverValley = "river valley",
}

---------------------------------------------------------------------------
-- Seed and world
---------------------------------------------------------------------------
local seed = Shared:GetAttribute("Seed")
while seed == nil do
	Shared:GetAttributeChangedSignal("Seed"):Wait()
	seed = Shared:GetAttribute("Seed")
end

local hud = Hud.new(seed)
Atmosphere.apply(Config)

local world = World.new(Config, seed)

-- premade models from ReplicatedStorage.InfiniteRoadAssets (optional)
local assets = AssetLibrary.new(ReplicatedStorage:FindFirstChild("InfiniteRoadAssets"))
if #assets.summary > 0 then
	print("[InfiniteRoad] using asset pack models: " .. table.concat(assets.summary, ", "))
else
	print("[InfiniteRoad] no asset pack models found, using built-in props")
end

local manager = ChunkManager.new(world, Config, Workspace.Terrain, assets)

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
-- are parked out of sight.
---------------------------------------------------------------------------
local function hide(model: Model, anchor: boolean)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
			if anchor then
				d.Anchored = true
			end
		elseif d:IsA("Decal") then
			d.Transparency = 1
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

local LOAD_RADIUS = 440
while true do
	manager:update(Config.World.LoadingFrameBudget)
	local progress = manager:progress(LOAD_RADIUS)
	hud:setProgress(progress)
	local p = manager:toRoblox(spawnPos)
	cam.CFrame = CFrame.lookAt(p + Vector3.new(-90, 70, 60), p)
	if progress >= 1 then
		break
	end
	RunService.RenderStepped:Wait()
end

---------------------------------------------------------------------------
-- Car
---------------------------------------------------------------------------
local colorRng = Random.new(player.UserId + seed)
local car = Car.new(Config, Config.Car.Colors[colorRng:NextInteger(1, #Config.Car.Colors)], assets)
car.model.Parent = Workspace

-- Roblox-space CFrame in the driving lane at arc length s
local function laneCFrame(s: number): CFrame
	local p, f, r, u = world.road:frameAt(s)
	local pos = manager:toRoblox(p + r * (rc.LaneWidth * 0.5 * rc.DriveSide)) + u * 3.6
	return CFrame.lookAt(pos, pos + f, u)
end

car:teleport(laneCFrame(rc.SpawnDistance))

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

manager.onRebase = function(delta: Vector3)
	car:shift(delta)
	camera:shift(delta)
end

local hudVisible = true
input:on("autodrive", function()
	autodrive:setEnabled(not autodrive.enabled)
	hud:toast(autodrive.enabled and "Autodrive on" or "Autodrive off")
end)
input:on("camera", function()
	hud:toast("Camera: " .. camera:cycle())
end)
input:on("reset", function()
	resetCar()
	hud:toast("Back on the road")
end)
input:on("time", function()
	local t = Atmosphere.nextPreset()
	hud:toast(string.format("Time %02d:%02d", math.floor(t), math.floor((t % 1) * 60)))
end)
input:on("hud", function()
	hudVisible = not hudVisible
	hud:setVisible(hudVisible)
end)
local statsVisible = false
input:on("stats", function()
	statsVisible = not statsVisible
	hud:setStats(statsVisible and "" or nil)
end)

if Config.Sounds.Ambience ~= "" then
	local ambience = Instance.new("Sound")
	ambience.SoundId = Config.Sounds.Ambience
	ambience.Looped = true
	ambience.Volume = 0.3
	ambience.Parent = Workspace.CurrentCamera
	ambience:Play()
end

---------------------------------------------------------------------------
-- Per-frame
---------------------------------------------------------------------------
local function physicsStep(dt: number)
	local throttle, steer, handbrake = input:read()
	if autodrive.enabled then
		if math.abs(throttle) > 0.2 or math.abs(steer) > 0.2 then
			autodrive:setEnabled(false)
			hud:toast("Autodrive off")
		else
			local cf = car:getCFrame()
			local cc = Config.Car
			local t = math.clamp(math.abs(car.speed) / cc.TopSpeed, 0, 1)
			local maxSteer = cc.MaxSteerLow + (cc.MaxSteerHigh - cc.MaxSteerLow) * math.sqrt(t)
			throttle, steer = autodrive:compute(manager:toWorld(cf.Position), cf.LookVector, cf.RightVector, car.speed, maxSteer)
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
	car:render()
	camera:update(dt, car)
end)

local report = Shared:WaitForChild("ReportDistance", 5)
local traveled = 0
local lastS = rc.SpawnDistance
local lastReport = os.clock()
local currentSection = nil
local upsideDown = 0
local frames, lastStats = 0, os.clock()

RunService.Heartbeat:Connect(function(dt)
	local cf = car:getCFrame()
	local worldPos = manager:toWorld(cf.Position)
	manager:setFocus(worldPos + car:getVelocity() * Config.World.LookAhead)
	manager:update(Config.World.FrameBudget)

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

	-- flipped over or fell into the water: put the car back
	if cf.UpVector.Y < 0.2 or p.Y < Config.SeaLevel - 25 then
		upsideDown += dt
		if upsideDown > 2.5 then
			upsideDown = 0
			resetCar()
		end
	else
		upsideDown = 0
	end

	Atmosphere.step(dt, Config)

	frames += 1
	if statsVisible and os.clock() - lastStats > 0.5 then
		local fps = frames / (os.clock() - lastStats)
		frames, lastStats = 0, os.clock()
		local st = manager.stats
		hud:setStats(string.format(
			"%d fps   generation %.1f ms/frame\nchunks %d loaded, %d waiting   built %d   rebases %d\ns = %.0f   world (%.0f, %.0f)   %s (%s)\nroad sample %d   %s%s   wheels on ground %d",
			fps, manager.lastWork * 1000, manager:loadedCount(), manager:pendingCount(), st.built, st.rebases,
			s, worldPos.X, worldPos.Z, sec.name, sec.type,
			math.floor(s / rc.SampleSpacing) + 1,
			world.road:isTunnel(math.floor(s / rc.SampleSpacing) + 1) and "tunnel " or "",
			world.road:isBridge(math.floor(s / rc.SampleSpacing) + 1) and "bridge " or "",
			car.grounded
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
