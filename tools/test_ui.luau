--[[
	Interface test: builds the HUD, start screen, toolbar, popovers,
	settings panel, photo mode and touch controls against a fake PlayerGui
	(a Folder) with stub game callbacks, then clicks through them by firing
	their event handlers. Every instance is real, so wrong class names,
	property names or value types fail here. Also checks layout rules:
	popovers and panels stay on screen, touch pedals never cover the
	toolbar, and no object field hides a method.
	  lune run tools/test_ui
]]

local process = require("@lune/process")
local task = require("@lune/task")
local env = require("./env")
local roblox = env.roblox
local Instance, Vector2, Enum = roblox.Instance, roblox.Vector2, roblox.Enum

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

---------------------------------------------------------------------------
-- Engine pieces Lune leaves out: events, tweens, TweenInfo, input queries
---------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

local function newSignal()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local handlers = self.handlers
	table.insert(handlers, fn)
	return {
		Disconnect = function()
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal:Once(fn)
	local connection
	connection = self:Connect(function(...)
		connection.Disconnect()
		fn(...)
	end)
	return connection
end

function Signal:Fire(...)
	for _, fn in table.clone(self.handlers) do
		fn(...)
	end
end

-- strong keys: an instance nobody references from Lua would otherwise get
-- a new userdata (and lose its handlers) after a garbage collection
local signals = {}
local function signalOf(inst, name)
	local byName = signals[inst]
	if not byName then
		byName = {}
		signals[inst] = byName
	end
	local s = byName[name]
	if not s then
		s = newSignal()
		byName[name] = s
	end
	return s
end

local EVENTS = {
	GuiButton = { "Activated", "MouseButton1Click" },
	GuiObject = { "MouseEnter", "MouseLeave", "InputBegan", "InputEnded", "InputChanged" },
	UserInputService = { "InputBegan", "InputChanged", "InputEnded", "TouchEnded" },
	GuiService = { "MenuOpened" },
}
for className, names in EVENTS do
	for _, name in names do
		roblox.implementProperty(className, name, function(inst)
			return signalOf(inst, name)
		end)
	end
end
roblox.implementMethod("Instance", "GetPropertyChangedSignal", function(inst, prop)
	return signalOf(inst, "Changed:" .. prop)
end)

local tweens = 0
roblox.implementMethod("TweenService", "Create", function(_, inst, info, goal)
	assert(type(info) == "table" and info.time ~= nil, "TweenService:Create needs a TweenInfo")
	-- validate property names and types now, apply them on Play
	for k, v in goal do
		inst[k] = inst[k]
		assert(typeof(inst[k]) == typeof(v), "tween " .. k .. " type " .. typeof(v) .. " vs " .. typeof(inst[k]))
	end
	tweens += 1
	local completed = newSignal()
	return {
		Completed = completed,
		Play = function()
			for k, v in goal do
				inst[k] = v
			end
			task.defer(function()
				completed:Fire(Enum.PlaybackState.Completed)
			end)
		end,
		Cancel = function() end,
	}
end)
env.baseEnv.TweenInfo = {
	new = function(time, style, direction)
		return { time = time, style = style, direction = direction }
	end,
}
env.baseEnv.utf8 = utf8

local keysDown = {}
roblox.implementMethod("UserInputService", "GetFocusedTextBox", function()
	return nil
end)
roblox.implementMethod("UserInputService", "IsKeyDown", function(_, key)
	return keysDown[key] == true
end)
roblox.implementMethod("UserInputService", "IsGamepadButtonDown", function()
	return false
end)

local UIS = env.game:GetService("UserInputService")
local GuiService = env.game:GetService("GuiService")
local Lighting = env.game:GetService("Lighting")
local function setDevice(touch, keyboard, gamepad)
	UIS.TouchEnabled = touch
	UIS.KeyboardEnabled = keyboard
	UIS.GamepadEnabled = gamepad
end
setDevice(false, true, false)

local function fire(inst, event, ...)
	assert(inst ~= nil, "fire " .. event .. " on nil")
	signalOf(inst, event):Fire(...)
end
local function click(inst)
	fire(inst, "Activated")
end

local function find(root, path)
	local node = root
	for name in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function need(root, path)
	local node = find(root, path)
	check(node ~= nil, "missing " .. path)
	return node
end

---------------------------------------------------------------------------
-- Modules
---------------------------------------------------------------------------
local Theme = env.require("src/client/UI/Theme")
local Options = env.require("src/client/UI/Options")
local Vehicles = env.require("src/client/Vehicles")
local Hud = env.require("src/client/Hud")
local Input = env.require("src/client/Input")
local App = env.require("src/client/UI/App")
local Seasons = env.require("src/client/Seasons")
local Weather = env.require("src/client/Weather")

-- A field with the same name as a method hides the method (a Hud field
-- called "toast" once broke every Hud:toast call).
local function checkNoShadow(obj, name)
	local mt = getmetatable(obj)
	local methods = mt and mt.__index
	if type(methods) ~= "table" then
		return
	end
	for k in pairs(obj) do
		if type(methods[k]) == "function" then
			check(false, name .. "." .. tostring(k) .. " hides the method of the same name")
		end
	end
end

-- Style rules: text is set in the theme fonts and colours, visible
-- backgrounds get a theme colour, and no button still says "Button".
local DEFAULT_BG = Instance.new("Frame").BackgroundColor3
local DEFAULT_TEXT = Instance.new("TextLabel").TextColor3
-- (EnumItems are compared by name: Lune hands out a new value each time)
local FONTS = { [Theme.FontBold.Name] = true, [Theme.Font.Name] = true, [Theme.FontLight.Name] = true, [Theme.FontMono.Name] = true }
local function sameColor(a, b)
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.002
end
local function checkStyle(root, name)
	local count = 0
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			count += 1
			if d.BackgroundTransparency < 1 then
				check(not sameColor(d.BackgroundColor3, DEFAULT_BG), name .. ": " .. d:GetFullName() .. " has the default grey background")
			end
		end
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			check(d.Text ~= "Button" and d.Text ~= "Label", name .. ": " .. d:GetFullName() .. " still has placeholder text")
			if d.Text ~= "" then
				local ok, font = pcall(function()
					return d.Font
				end)
				check(ok and FONTS[font.Name], name .. ": " .. d:GetFullName() .. " uses a font outside the theme")
				check(not sameColor(d.TextColor3, DEFAULT_TEXT), name .. ": " .. d:GetFullName() .. " has the default text colour")
			end
		end
	end
	return count
end

-- Rect of a GuiObject in its parent's space, for a parent of size (w, h).
local function rect(obj, w, h)
	local size, pos, anchor = obj.Size, obj.Position, obj.AnchorPoint
	local sw, sh = size.X.Scale * w + size.X.Offset, size.Y.Scale * h + size.Y.Offset
	local x = pos.X.Scale * w + pos.X.Offset - anchor.X * sw
	local y = pos.Y.Scale * h + pos.Y.Offset - anchor.Y * sh
	return { x = x, y = y, w = sw, h = sh }
end
local function overlaps(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end
local function inside(a, w, h)
	return a.x >= -0.5 and a.y >= -0.5 and a.x + a.w <= w + 0.5 and a.y + a.h <= h + 0.5
end

---------------------------------------------------------------------------
-- A stub game
---------------------------------------------------------------------------
local function newGame()
	local g = {
		state = {
			vehicle = "Sedan",
			color = Vehicles.get("Sedan").colors[1],
			season = "Auto",
			seasonNow = "Summer",
			weather = "Auto",
			weatherNow = "Clear",
			clock = 15.2,
			dayCycle = true,
			camera = "Chase",
			autodrive = false,
			quality = "Auto",
			qualityNow = "High",
			units = "km/h",
			speedometer = true,
			stats = false,
		},
		resets = 0,
		started = nil,
		sets = {},
	}
	local READ_ONLY = { vehicle = true, color = true, seasonNow = true, weatherNow = true, qualityNow = true }
	g.app = {
		get = function(key)
			assert(g.state[key] ~= nil, "app.get: unknown key " .. tostring(key))
			return g.state[key]
		end,
		set = function(key, value)
			assert(g.state[key] ~= nil and not READ_ONLY[key], "app.set: bad key " .. tostring(key))
			assert(type(value) == type(g.state[key]), "app.set " .. key .. ": wrong type " .. type(value))
			g.state[key] = value
			if key == "season" and value ~= "Auto" then
				g.state.seasonNow = value
			elseif key == "weather" and value ~= "Auto" then
				g.state.weatherNow = value
			elseif key == "units" and g.hud then
				g.hud:setUnits(value)
			end
			table.insert(g.sets, key)
		end,
		setVehicle = function(id, color)
			assert(table.find(Vehicles.Order, id), "setVehicle: unknown vehicle " .. tostring(id))
			g.state.vehicle = id
			g.state.color = color or Vehicles.get(id).colors[1]
		end,
		reset = function()
			g.resets += 1
		end,
		start = function(autodrive)
			g.started = autodrive
			g.state.autodrive = autodrive
			if g.hud then
				g.hud:setVisible(true)
			end
		end,
	}
	return g
end

---------------------------------------------------------------------------
-- 1. Desktop: HUD, loading, start screen
---------------------------------------------------------------------------
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"
local game1 = newGame()
local hud = Hud.new(12345, playerGui)
game1.hud = hud
checkNoShadow(hud, "Hud")
local loadingGui = need(playerGui, "InfiniteRoadLoading")
hud:setProgress(0.42)
check(math.abs(hud.bar.Size.X.Scale - 0.42) < 1e-6 and hud.percentText.Text == "42%", "loading bar shows progress")

local input = Input.new()
checkNoShadow(input, "Input")
local fired = {}
for _, name in { "autodrive", "camera", "reset", "time", "photo", "stats", "vehicle", "season", "weather", "menu", "confirm", "back" } do
	input:on(name, function()
		table.insert(fired, name)
	end)
end

local ui = App.new(playerGui, game1.app, { hud = hud, input = input, seed = 12345 })
checkNoShadow(ui, "App")
checkNoShadow(ui.toolbar, "Toolbar")
checkNoShadow(ui.settingsMenu, "SettingsMenu")
for i, widget in ui.widgets do
	checkNoShadow(widget, "widget " .. i)
end
local startScreen = ui.startScreen
checkNoShadow(startScreen, "StartScreen")
for i, widget in startScreen.widgets do
	checkNoShadow(widget, "start widget " .. i)
end

for _, name in { "InfiniteRoadHud", "InfiniteRoadUI", "InfiniteRoadStart", "InfiniteRoadPhoto" } do
	local gui = need(playerGui, name)
	if gui then
		check(gui.ClassName == "ScreenGui" and gui.ResetOnSpawn == false, name .. " is a ScreenGui that survives respawns")
		print(string.format("%-20s %4d gui objects", name, checkStyle(gui, name)))
	end
end
checkStyle(loadingGui, "InfiniteRoadLoading")
check(ui.gui.Enabled == false, "toolbar hidden behind the start screen")
check(Lighting:FindFirstChild("IR_StartBlur") ~= nil and Lighting.IR_StartBlur.Size > 0, "start screen blurs the world")
check(hud.root.Visible == false, "driving HUD hidden until the drive starts")

hud:finishLoading()
task.wait(1.1)
check(loadingGui.Parent == nil, "loading screen removed after fading out")

-- start screen chips apply at once
local startGui = playerGui:FindFirstChild("InfiniteRoadStart")
local card = need(startGui, "Root/Card")
local body = need(card, "Body")
click(need(body, "World/Season/season/Winter"))
check(game1.state.season == "Winter", "start screen: season chip")
local winter = find(body, "World/Season/season/Winter")
check(winter and sameColor(winter.BackgroundColor3, Theme.Accent), "selected season chip is filled with the accent colour")
check(sameColor(find(body, "World/Season/season/Auto").BackgroundColor3, Theme.Surface), "other season chips are plain")
click(need(body, "World/Weather/weather/Storm"))
check(game1.state.weather == "Storm", "start screen: weather chip")
click(need(body, "World/Time of day/time/Night"))
check(game1.state.clock == 22, "start screen: time chip sets the clock")
check(sameColor(find(body, "World/Time of day/time/Night").BackgroundColor3, Theme.Accent), "time chip lit")
click(need(body, "World/Time of day/dayCycle"))
check(game1.state.dayCycle == false, "start screen: day cycle switch")
check(find(body, "World/Time of day/dayCycle/Switch/Knob").Position.X.Offset == 3, "switch knob moves off")

-- vehicle picker: a bike keeps the nearest colour, swatches change palette
local picker = need(body, "Vehicle/VehiclePicker")
for _, id in Vehicles.Order do
	local spec = Vehicles.get(id)
	local cardButton = find(picker, (spec.category or "Car") .. "/" .. id)
	check(cardButton ~= nil, "picker has a card for " .. id)
	if cardButton then
		check(cardButton.Title.Text == spec.name and cardButton.Description.Text == spec.description, id .. " card shows name and description")
		check(#cardButton.Colors:GetChildren() - 1 == #spec.colors, id .. " card shows its colours")
	end
end
local red = Vehicles.get("Sedan").colors[1]
game1.state.color = red
startScreen:refresh()
local bikeId
for _, id in Vehicles.Order do
	if Vehicles.get(id).category == "Bike" then
		bikeId = id
		break
	end
end
click(need(picker, "Bike/" .. bikeId))
check(game1.state.vehicle == bikeId, "picker selects a bike")
local bikeColors = Vehicles.get(bikeId).colors
check(table.find(bikeColors, game1.state.color) ~= nil, "bike keeps a colour from its own palette")
check(game1.state.color.R > game1.state.color.B, "switching to the bike keeps the paint reddish")
check(#need(picker, "Paint"):GetChildren() - 2 == #bikeColors, "paint row shows the bike's colours")
click(need(picker, "Paint/Swatch3"))
check(game1.state.color == bikeColors[3], "paint swatch picks the colour")
check(find(picker, "Paint/Swatch3/UIStroke").Thickness == 3, "picked swatch is ringed")
check(find(picker, "Bike/" .. bikeId .. "/UIStroke").Color == Theme.Accent, "selected card outlined in the accent colour")
click(need(picker, "Car/Sedan"))
check(game1.state.vehicle == "Sedan", "back to the sedan")

-- layout: the card fits, and stacks its columns on a narrow screen
local view = { width = Theme.RefWidth, height = Theme.RefHeight }
local cardRect = rect(card, view.width, view.height)
check(inside(cardRect, view.width, view.height), "start card fits the reference screen")
check(startScreen.stacked == false, "columns side by side on a wide screen")
startGui.AbsoluteSize = Vector2.new(640, 800)
fire(startGui, "Changed:AbsoluteSize")
local rootScale = startGui.Root.UIScale.Scale
check(math.abs(rootScale - Theme.MinScale) < 1e-6, "tall narrow screen uses the smallest scale")
check(startScreen.stacked == true, "columns stack on a narrow screen")
local w, h = 640 / rootScale, 800 / rootScale
check(inside(rect(card, w, h), w, h), "start card fits a narrow screen")
startGui.AbsoluteSize = Vector2.new(Theme.RefWidth, Theme.RefHeight)
fire(startGui, "Changed:AbsoluteSize")

-- shortcuts wait for the start screen, except Enter
fire(UIS, "InputBegan", { KeyCode = Enum.KeyCode.F }, false)
fire(UIS, "InputBegan", { KeyCode = Enum.KeyCode.G }, true)
fire(UIS, "InputBegan", { KeyCode = Enum.KeyCode.Return }, false)
fire(UIS, "InputBegan", { KeyCode = Enum.KeyCode.Escape }, false)
check(fired[1] == "autodrive" and fired[2] == "confirm" and fired[3] == "back" and #fired == 3, "shortcuts fire their actions (and skip keys the game used)")

-- Drive
click(need(card, "Footer/Drive"))
check(game1.started == false, "Drive starts without autodrive")
check(ui.started and ui.gui.Enabled, "toolbar shown after Drive")
check(hud.root.Visible, "driving HUD shown after Drive")
click(need(card, "Footer/Autodrive"))
check(game1.started == false, "a second click does nothing")
task.wait(Theme.Slow + 0.2)
check(Lighting:FindFirstChild("IR_StartBlur") == nil, "blur removed after the start screen")
check(startGui.Parent == nil, "start screen destroyed")

---------------------------------------------------------------------------
-- 2. Desktop: toolbar, popovers, settings, photo mode
---------------------------------------------------------------------------
local uiRoot = ui.root
local toolbar = need(uiRoot, "Toolbar")
for _, id in { "autodrive", "camera", "vehicle", "season", "weather", "time", "reset", "photo", "settings" } do
	local b = need(toolbar, id)
	if b then
		check(b.Label.Text ~= "" and b.Icon.Text ~= "", id .. " has an icon and a label")
		check(b:FindFirstChild("Tooltip") ~= nil, id .. " has a tooltip")
	end
end
check(find(playerGui, "InfiniteRoadHud/Root/Hints") == nil, "no key hint bar")

-- autodrive toggles, the button lights up
click(toolbar.autodrive)
check(game1.state.autodrive == true, "toolbar autodrive on")
check(sameColor(toolbar.autodrive.BackgroundColor3, Theme.Accent) and toolbar.autodrive.BackgroundTransparency == 0, "autodrive button active")
click(toolbar.autodrive)
check(game1.state.autodrive == false and toolbar.autodrive.BackgroundTransparency == 1, "toolbar autodrive off")

-- tooltip on hover (with the shortcut key)
fire(toolbar.settings, "MouseEnter")
check(toolbar.settings.Tooltip.Visible and string.find(toolbar.settings.Tooltip.Text, "M", 1, true) ~= nil, "settings tooltip shows its key")
fire(toolbar.settings, "MouseLeave")
check(not toolbar.settings.Tooltip.Visible, "tooltip hides")
fire(toolbar.season, "MouseEnter")
check(toolbar.season.Tooltip.Text == "Season: Winter   N", "season tooltip names the season, got " .. toolbar.season.Tooltip.Text)
fire(toolbar.season, "MouseLeave")

-- popovers open above their button, show chips, and close
local function popover(id)
	return uiRoot:FindFirstChild("Popover" .. id)
end
local function checkOnScreen(obj, name, vw, vh)
	check(inside(rect(obj, vw, vh), vw, vh), name .. " is on screen")
end
for _, id in { "camera", "vehicle", "season", "weather", "time" } do
	click(toolbar[id])
	local pop = popover(id)
	check(pop and pop.Visible and ui.openId == id, id .. " popover opens")
	check(ui.scrim.Visible, id .. " popover shows the scrim")
	check(toolbar[id].UIStroke.Transparency == 0, id .. " button outlined while open")
	if pop then
		local r = rect(pop, ui.view.width, ui.view.height)
		check(r.x >= 0 and r.x + r.w <= ui.view.width, id .. " popover stays inside the screen")
		check(r.y + r.h <= ui.view.height - Theme.ToolbarReserve + 0.5, id .. " popover sits above the toolbar")
		checkNoShadow(ui.popovers[id], "popover " .. id)
	end
end
check(popover("vehicle").Visible == false and popover("camera").Visible == false, "only one popover open at a time")
click(toolbar.time)
check(ui.openId == nil and not popover("time").Visible and not ui.scrim.Visible, "clicking the open button closes its popover")
check(toolbar.time.UIStroke.Transparency == 1, "outline goes when closed")

click(toolbar.camera)
click(need(popover("camera"), "camera/Cinematic"))
check(game1.state.camera == "Cinematic", "camera chip")
click(ui.scrim)
check(ui.openId == nil, "clicking outside closes the popover")

click(toolbar.season)
check(popover("season").Header.Status.Text == "Now: Winter", "season popover shows the current season")
click(need(popover("season"), "season/Auto"))
check(game1.state.season == "Auto", "season back to Auto")
game1.state.seasonNow = "Spring"
ui:refresh()
check(popover("season").Header.Status.Text == "Now: Spring", "status follows auto seasons")
check(toolbar.season.Icon.Text == Options.SeasonIcons.Spring, "season button icon follows the season")

click(toolbar.weather)
for _, name in Weather.Types do
	click(need(popover("weather"), "weather/" .. name))
	check(game1.state.weather == name, "weather chip " .. name)
	check(toolbar.weather.Icon.Text == Options.WeatherIcons[name], "weather icon for " .. name)
end
click(need(popover("weather"), "weather/Auto"))

click(toolbar.time)
for _, t in Options.Times do
	click(need(popover("time"), "time/" .. t.name))
	check(game1.state.clock == t.clock, "time chip " .. t.name)
	check(toolbar.time.Icon.Text == t.icon, "time icon for " .. t.name)
end
click(need(popover("time"), "dayCycle"))
check(game1.state.dayCycle == true, "day cycle switch in the time popover")
game1.state.clock = 3
ui:refresh()
for _, t in Options.Times do
	local chip = find(popover("time"), "time/" .. t.name)
	check(not sameColor(chip.BackgroundColor3, Theme.Accent), "no time chip lit far from every preset")
end

click(toolbar.vehicle)
click(need(popover("vehicle"), "Scroll/VehiclePicker/Car/SportsCar"))
check(game1.state.vehicle == "SportsCar", "vehicle popover switches vehicle")
check(popover("vehicle").Header.Status.Text == Vehicles.get("SportsCar").name, "vehicle popover names the vehicle")
check(ui.openId == "vehicle", "vehicle popover stays open to pick paint")
click(ui.scrim)

-- settings panel: click the option you want
click(toolbar.settings)
local settings = need(uiRoot, "Settings")
check(settings.Visible and ui.settingsMenu.visible and ui.scrim.Visible, "settings panel opens")
local settingsBody = need(settings, "Body")
check(need(settingsBody, "Graphics quality/Hint").Text == "Auto picked High for this device", "quality hint names the automatic preset")
for _, q in { "Low", "Medium", "High", "Ultra", "Auto" } do
	click(need(settingsBody, "Graphics quality/quality/" .. q))
	check(game1.state.quality == q, "quality chip " .. q)
end
click(need(settingsBody, "Camera/camera/Hood"))
check(game1.state.camera == "Hood", "settings camera chip")
click(need(settingsBody, "Speed units/units/mph"))
check(game1.state.units == "mph", "speed units chip")
click(need(settingsBody, "Switches/speedometer"))
check(game1.state.speedometer == false, "speedometer switch")
click(need(settingsBody, "Switches/stats"))
check(game1.state.stats == true, "stats overlay switch")
click(need(settingsBody, "Switches/dayCycle"))
check(game1.state.dayCycle == false, "day cycle switch in settings")
check(sameColor(find(settingsBody, "Switches/stats/Switch").BackgroundColor3, Theme.Accent), "switch on shows the accent colour")
click(need(settingsBody, "Shortcuts"))
check(not ui.settingsMenu.visible and ui.openId == "help" and popover("help").Visible, "shortcuts button opens the shortcuts popover")
check(#need(popover("help"), "Scroll"):GetChildren() - 1 == #Options.Shortcuts + 1, "shortcuts popover lists every shortcut")
click(need(toolbar, "Help"))
check(ui.openId == nil, "? button closes the shortcuts popover")
click(toolbar.settings)
click(need(settings, "Close"))
check(not settings.Visible and ui.openId == nil and not ui.scrim.Visible, "settings close button")
click(toolbar.settings)
check(ui:back() == true and not settings.Visible, "Esc closes the settings panel")
check(ui:back() == false, "Esc with nothing open does nothing")

click(toolbar.reset)
check(game1.resets == 1, "reset button")

-- photo mode
local photoGui = need(playerGui, "InfiniteRoadPhoto")
click(toolbar.photo)
check(ui.photoOn and not ui.gui.Enabled and not hud.root.Visible and photoGui.Enabled, "photo mode hides the interface")
check(photoGui.Root.Hint.Visible, "photo mode shows how to get back")
click(need(photoGui, "Root/Exit"))
check(not ui.photoOn and ui.gui.Enabled and hud.root.Visible and not photoGui.Enabled, "a click leaves photo mode")
ui:togglePhoto()
check(ui:back() == true and not ui.photoOn, "Esc leaves photo mode")
ui:togglePhoto()
fire(GuiService, "MenuOpened")
check(not ui.photoOn and ui.gui.Enabled, "opening the Roblox menu leaves photo mode")
ui:togglePhoto()
task.wait(2.6 + Theme.Slow + 0.1)
check(not photoGui.Root.Hint.Visible, "photo hint fades away")
ui:setPhoto(false)

-- HUD pieces
hud:setUnits("km/h")
hud:update(100, 10000)
check(hud.speedText.Text == "101" and hud.distanceText.Text == "2.8 km", "speed and distance in km")
hud:setUnits("mph")
hud:update(100, 10000)
check(hud.speedText.Text == "63" and hud.distanceText.Text == "1.7 mi" and hud.unitText.Text == "mph", "speed and distance in miles")
hud:setBadge("AUTODRIVE")
check(hud.badgeFrame.Visible and hud.badgeText.Text == "AUTODRIVE", "autodrive badge")
hud:setBadge("")
check(not hud.badgeFrame.Visible, "badge hides")
hud:setInfo("Summer  ·  Clear  ·  12:00")
check(hud.infoText.Text == "Summer  ·  Clear  ·  12:00", "info line")
hud:setStats("60 fps")
check(hud.statsPanel.Visible and hud.statsText.Text == "60 fps", "stats overlay")
hud:setStats(nil)
check(not hud.statsPanel.Visible, "stats overlay hides")
hud:setSpeedometer(false)
check(not hud.speedPanel.Visible, "speedometer hides")
hud:setSpeedometer(true)
hud:showRegion("Lake Serene", "lakeside road")
check(hud.regionFrame.Visible and hud.regionText.Text == "Lake Serene" and hud.regionSubText.Text == "LAKESIDE ROAD", "region banner")
check(hud.regionText.TextTransparency == 0, "region banner fades in")
hud:toast("Hello")
hud:toast("Back on the road")
check(hud.toastFrame.Visible and hud.toastText.Text == "Back on the road" and hud.toastText.TextTransparency == 0, "toast shows")
task.wait(2.5)
check(not hud.toastFrame.Visible, "toast fades away")
checkNoShadow(hud, "Hud (after use)")
checkNoShadow(ui, "App (after use)")

-- small screen: everything scales down and stays reachable
local uiGui = ui.gui
uiGui.AbsoluteSize = Vector2.new(844, 390)
fire(uiGui, "Changed:AbsoluteSize")
local s = uiGui.Root.UIScale.Scale
check(math.abs(s - Theme.MinScale) < 1e-6, "phone screen uses the smallest scale")
check(math.abs(uiGui.Root.Size.X.Scale - 1 / s) < 1e-6, "scaled root still covers the screen")
local vw, vh = ui.view.width, ui.view.height
checkOnScreen(toolbar, "toolbar on a phone", vw, vh)
click(toolbar.settings)
checkOnScreen(settings, "settings panel on a phone", vw, vh)
check(rect(settings, vw, vh).y >= 0, "settings panel fits under the top")
click(toolbar.vehicle)
local vehiclePop = popover("vehicle")
check(vehiclePop.Scroll.Size.Y.Offset <= vh - Theme.ToolbarReserve - 60, "vehicle popover scrolls on a short screen")
click(ui.scrim)

---------------------------------------------------------------------------
-- 3. Touch: pedals above the toolbar, no tooltips, no "?" button
---------------------------------------------------------------------------
setDevice(true, false, false)
local touchGui = Instance.new("Folder")
local game2 = newGame()
local touchHud = Hud.new(1, touchGui)
game2.hud = touchHud
local touchInput = Input.new()
local touchUi = App.new(touchGui, game2.app, { hud = touchHud, input = touchInput })
local touchStart = need(touchGui, "InfiniteRoadStart")
touchStart.AbsoluteSize = Vector2.new(667, 375)
fire(touchStart, "Changed:AbsoluteSize")
local ts = touchStart.Root.UIScale.Scale
check(inside(rect(touchStart.Root.Card, 667 / ts, 375 / ts), 667 / ts, 375 / ts), "start card fits a small phone")
click(need(touchStart, "Root/Card/Footer/Autodrive"))
check(game2.started == true, "Autodrive button starts with autodrive on")
local touchRoot = touchUi.root
local pad = need(touchRoot, "TouchControls")
check(find(touchRoot, "Toolbar/settings/Tooltip") == nil, "no hover tooltips on touch screens")
check(find(touchRoot, "Toolbar/Help") == nil, "no shortcuts button without a keyboard")
check(touchHud.speedPanel.AnchorPoint.Y == 0, "speedometer moves to the top on touch screens")
checkStyle(touchGui:FindFirstChild("InfiniteRoadUI"), "touch UI")
-- (the last one is a phone held upright: everything must still fit, even
-- though it is smaller than the touch-size rules below)
for i, size in { Vector2.new(667, 375), Vector2.new(844, 390), Vector2.new(1024, 768), Vector2.new(1366, 1024), Vector2.new(390, 844) } do
	local upright = i == 5
	touchUi.gui.AbsoluteSize = size
	fire(touchUi.gui, "Changed:AbsoluteSize")
	local tw, th = touchUi.view.width, touchUi.view.height
	check(upright or touchUi.view.scale >= Theme.TouchMinScale - 1e-6, "touch screens keep a finger-sized scale on " .. tostring(size))
	local bar = rect(touchRoot.Toolbar, tw, th)
	check(inside(bar, tw, th), "toolbar fits a " .. tostring(size) .. " screen")
	for _, b in pad:GetChildren() do
		if b:IsA("GuiObject") then
			local r = rect(b, tw, th)
			check(not overlaps(r, bar), b.Name .. " clear of the toolbar on " .. tostring(size))
			check(inside(r, tw, th), b.Name .. " on screen on " .. tostring(size))
			check(upright or (r.w * touchUi.view.scale >= 44 and r.h * touchUi.view.scale >= 44), b.Name .. " is a big enough touch target on " .. tostring(size))
		end
	end
	for _, id in { "autodrive", "settings", "photo" } do
		local r = rect(touchRoot.Toolbar[id], 1, 1)
		check(upright or (r.w * touchUi.view.scale >= 44 and r.h * touchUi.view.scale >= 44), id .. " toolbar button big enough to tap on " .. tostring(size))
	end
end
touchUi.gui.AbsoluteSize = Vector2.new(667, 375)
fire(touchUi.gui, "Changed:AbsoluteSize")
click(touchRoot.Toolbar.settings)
checkOnScreen(touchRoot.Settings, "settings panel on a small phone", touchUi.view.width, touchUi.view.height)
for _, id in { "camera", "vehicle", "season", "weather", "time" } do
	click(touchRoot.Toolbar[id])
	checkOnScreen(touchRoot:FindFirstChild("Popover" .. id), id .. " popover on a small phone", touchUi.view.width, touchUi.view.height)
end
click(touchUi.scrim)

local touchObj = { UserInputType = Enum.UserInputType.Touch }
fire(pad.Gas, "InputBegan", touchObj)
local throttle, steer = touchInput:read()
check(throttle == 1 and steer == 0, "GAS pedal drives")
check(sameColor(pad.Gas.BackgroundColor3, Theme.Accent), "held pedal lights up")
local steerTouch = { UserInputType = Enum.UserInputType.Touch }
fire(pad.Left, "InputBegan", steerTouch)
throttle, steer = touchInput:read()
check(throttle == 1 and steer == -1, "two fingers: gas and steer together")
fire(UIS, "TouchEnded", touchObj, false)
fire(pad.Left, "InputEnded", steerTouch)
throttle, steer = touchInput:read()
check(throttle == 0 and steer == 0, "lifting fingers lets go (even off the button)")
checkNoShadow(touchInput, "Input (touch)")

---------------------------------------------------------------------------
-- 4. Gamepad: "Drive" is selected so A starts
---------------------------------------------------------------------------
setDevice(false, false, true)
local padGui = Instance.new("Folder")
local game3 = newGame()
local padUi = App.new(padGui, game3.app, { input = Input.new() })
check(GuiService.SelectedObject == need(padGui, "InfiniteRoadStart/Root/Card/Footer/Drive"), "gamepad selects the Drive button")
check(find(padUi.root, "Toolbar/Help") ~= nil, "shortcuts button shown for gamepads")
padUi:confirm()
check(game3.started == false and padUi.started, "Enter / confirm starts driving")

---------------------------------------------------------------------------
-- 5. Options cover every season, weather and camera mode
---------------------------------------------------------------------------
for _, name in Seasons.Order do
	check(Options.SeasonIcons[name] ~= nil, "icon for season " .. name)
end
for _, name in Weather.Types do
	check(Options.WeatherIcons[name] ~= nil, "icon for weather " .. name)
end
check(Options.nearestTime(23.9).name == "Night" and Options.nearestTime(0.5, 1) == nil, "nearest time wraps at midnight")
check(Options.clockText(6.5) == "06:30", "clock text")

task.wait(0.1)
print(string.format("%d tweens played", tweens))
if failures > 0 then
	print(failures .. " FAILURES")
	process.exit(1)
end
print("UI TEST PASSED")
