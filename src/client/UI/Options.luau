--[[
	Options
	-------
	What the menus offer, with labels and icons: seasons, weather, times of
	day, camera modes, quality presets and speed units, plus the keyboard
	and gamepad shortcut list. Icons are emoji, so no image assets are
	needed.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("InfiniteRoad").Config)
local Seasons = require(script.Parent.Parent.Seasons)
local Weather = require(script.Parent.Parent.Weather)
local Vehicles = require(script.Parent.Parent.Vehicles)
local CameraController = require(script.Parent.Parent.CameraController)

local Options = {}

Options.SeasonIcons = { Spring = "🌸", Summer = "🌻", Autumn = "🍁", Winter = "❄️" }
Options.WeatherIcons = { Clear = "☀️", Cloudy = "☁️", Rain = "🌧️", Storm = "⛈️", Fog = "🌫️", Snow = "🌨️" }
Options.CameraIcons = { Chase = "🎥", Hood = "👀", Cinematic = "🎬" }
Options.VehicleIcons = { Sedan = "🚗", SportsCar = "🏎️", Pickup = "🚙", Semi = "🚚" }
Options.CategoryIcons = { Car = "🚗", Bike = "🏍️" }
Options.CategoryNames = { Car = "Cars", Bike = "Motorcycles" }

-- times of day (Lighting.ClockTime)
Options.Times = {
	{ name = "Dawn", clock = 6.6, icon = "🌅" },
	{ name = "Morning", clock = 9.2, icon = "🌄" },
	{ name = "Noon", clock = 12.3, icon = "🌞" },
	{ name = "Afternoon", clock = 15.2, icon = "🌤️" },
	{ name = "Sunset", clock = 17.9, icon = "🌇" },
	{ name = "Night", clock = 22, icon = "🌙" },
}

Options.Units = { "km/h", "mph" }

-- keys shown in toolbar tooltips
Options.Keys = {
	autodrive = "F",
	camera = "C",
	vehicle = "V",
	season = "N",
	weather = "G",
	time = "T",
	reset = "R",
	photo = "H",
	settings = "M",
}

-- { action, keyboard, gamepad } for the shortcuts popover
Options.Shortcuts = {
	{ "Drive / brake", "W  S", "RT  LT" },
	{ "Steer", "A  D", "Left stick" },
	{ "Handbrake", "Space", "A" },
	{ "Autodrive", "F", "X" },
	{ "Camera", "C", "Y" },
	{ "Look around", "Right-drag", "Right stick" },
	{ "Reset car", "R", "B" },
	{ "Time of day", "T", "D-pad up" },
	{ "Photo mode", "H", "D-pad down" },
	{ "Next vehicle", "V", "D-pad left" },
	{ "Weather", "G", "D-pad right" },
	{ "Season", "N", "" },
	{ "Settings", "M", "Select" },
	{ "Stats overlay", "F3", "" },
}

local function withIcon(icon: string?, text: string): string
	if icon and icon ~= "" then
		return icon .. " " .. text
	end
	return text
end

-- chip lists: { { value, text }, ... }
function Options.seasons()
	local list = { { value = "Auto", text = "Auto" } }
	for _, name in Seasons.Order do
		table.insert(list, { value = name, text = withIcon(Options.SeasonIcons[name], name) })
	end
	return list
end

function Options.weathers()
	local list = { { value = "Auto", text = "Auto" } }
	for _, name in Weather.Types do
		table.insert(list, { value = name, text = withIcon(Options.WeatherIcons[name], name) })
	end
	return list
end

function Options.times()
	local list = {}
	for _, t in Options.Times do
		table.insert(list, { value = t.name, text = withIcon(t.icon, t.name) })
	end
	return list
end

function Options.cameras()
	local list = {}
	for _, name in CameraController.Modes do
		table.insert(list, { value = name, text = withIcon(Options.CameraIcons[name], name) })
	end
	return list
end

function Options.qualities()
	local list = { { value = "Auto", text = "Auto" } }
	for _, name in Config.Quality.Order do
		table.insert(list, { value = name, text = name })
	end
	return list
end

function Options.units()
	local list = {}
	for _, name in Options.Units do
		table.insert(list, { value = name, text = name })
	end
	return list
end

function Options.timeClock(name: string): number?
	for _, t in Options.Times do
		if t.name == name then
			return t.clock
		end
	end
	return nil
end

-- The time preset closest to `clock` (hours, wrapping at midnight), or nil
-- when none is within `within` hours.
function Options.nearestTime(clock: number, within: number?)
	local best, bestDist = nil, math.huge
	for _, t in Options.Times do
		local d = math.abs(clock - t.clock) % 24
		d = math.min(d, 24 - d)
		if d < bestDist then
			best, bestDist = t, d
		end
	end
	if within and bestDist > within then
		return nil
	end
	return best
end

function Options.clockText(clock: number): string
	return string.format("%02d:%02d", math.floor(clock), math.floor((clock % 1) * 60))
end

function Options.vehicleIcon(id: string): string
	return Options.VehicleIcons[id] or Options.CategoryIcons[Vehicles.get(id).category] or "🚗"
end

return Options
