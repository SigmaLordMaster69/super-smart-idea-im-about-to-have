--[[
	Controls
	--------
	The chip groups and switches for each game setting, shared by the start
	screen, the toolbar popovers and the settings panel so they look and
	behave the same everywhere.

	`state` is { get = function(key) -> value, set = function(key, value) }
	(see App.luau for the keys). Each function returns a widget with
	:refresh() and .height.
]]

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Options = require(script.Parent.Options)

local Controls = {}

local function chips(parent, state, key: string, options, columns: number, order: number?)
	return Kit.chips(parent, options, {
		name = key,
		columns = columns,
		order = order or 1,
		get = function()
			return state.get(key)
		end,
		set = function(value)
			state.set(key, value)
		end,
	})
end

local function toggle(parent, state, key: string, text: string, detail: string?, order: number?)
	local widget = Kit.toggle(parent, {
		name = key,
		text = text,
		detail = detail,
		order = order or 1,
		get = function()
			return state.get(key)
		end,
		set = function(value)
			state.set(key, value)
		end,
	})
	widget.height = Theme.ToggleHeight
	return widget
end

function Controls.season(parent: Instance, state, order: number?)
	return chips(parent, state, "season", Options.seasons(), 5, order)
end

function Controls.weather(parent: Instance, state, order: number?)
	return chips(parent, state, "weather", Options.weathers(), 4, order)
end

function Controls.camera(parent: Instance, state, order: number?)
	return chips(parent, state, "camera", Options.cameras(), 3, order)
end

function Controls.quality(parent: Instance, state, order: number?)
	return chips(parent, state, "quality", Options.qualities(), 5, order)
end

function Controls.units(parent: Instance, state, order: number?)
	return chips(parent, state, "units", Options.units(), 2, order)
end

-- Time of day: the chip nearest the clock (within an hour) is lit, so it
-- follows the day/night cycle.
function Controls.time(parent: Instance, state, order: number?)
	return Kit.chips(parent, Options.times(), {
		name = "time",
		columns = 3,
		order = order or 1,
		get = function()
			local t = Options.nearestTime(state.get("clock"), 1)
			return t and t.name
		end,
		set = function(name)
			state.set("clock", Options.timeClock(name))
		end,
	})
end

function Controls.dayCycle(parent: Instance, state, order: number?)
	return toggle(parent, state, "dayCycle", "Day/night cycle", "Time passes while you drive", order)
end

function Controls.speedometer(parent: Instance, state, order: number?)
	return toggle(parent, state, "speedometer", "Speedometer", nil, order)
end

function Controls.stats(parent: Instance, state, order: number?)
	return toggle(parent, state, "stats", "Stats overlay", "FPS, chunks and workers", order)
end

return Controls
