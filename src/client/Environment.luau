--[[
	Environment
	-----------
	Owns the season and the weather, including the Auto modes: seasons roll
	every Config.Seasons.CycleMinutes, and weather changes every few minutes,
	picked with weights that suit the season (winter precipitation is snow).

	Other systems listen through `onSeason(name, preset)` and read
	`gripScale()` / `wetness()` every frame.
]]

local Lighting = game:GetService("Lighting")

local Seasons = require(script.Parent.Seasons)
local Weather = require(script.Parent.Weather)

local Environment = {}
Environment.__index = Environment

-- deps: as Weather.new, plus `seed`
function Environment.new(config, deps)
	local self = setmetatable({}, Environment)
	self.config = config
	self.terrain = deps.terrain
	self.rng = Random.new(deps.seed or os.time())
	self.weather = Weather.new(config, deps)
	self.onSeason = nil
	self.qualityScale = 1

	local startSeason = config.Seasons.Start
	self.seasonAuto = startSeason == "Auto" or Seasons.Presets[startSeason] == nil
	self.season = self.seasonAuto and Seasons.Order[self.rng:NextInteger(1, #Seasons.Order)] or startSeason
	self.seasonTimer = config.Seasons.CycleMinutes * 60

	local startWeather = config.Weather.Start
	self.weatherAuto = startWeather == "Auto" or Weather.Presets[startWeather] == nil
	self.weatherTimer = 0
	self.weather:set(self.weatherAuto and self:_pickWeather() or startWeather, true)
	if self.weatherAuto then
		self.weatherTimer = self.rng:NextNumber(config.Weather.MinDuration, config.Weather.MaxDuration)
	end
	Seasons.applyColors(self.season, self.terrain)
	return self
end

function Environment:seasonPreset()
	return Seasons.get(self.season)
end

function Environment:_pickWeather(): string
	local weights = self:seasonPreset().weather
	local total = 0
	for _, w in weights do
		total += w
	end
	local roll = self.rng:NextNumber() * total
	for name, w in weights do
		roll -= w
		if roll <= 0 then
			return name
		end
	end
	return "Clear"
end

function Environment:_setSeason(name: string)
	if name == self.season then
		return
	end
	self.season = name
	Seasons.applyColors(name, self.terrain)
	-- rain in winter falls as snow, snow melts to rain outside it
	local w = self.weather.name
	if name == "Winter" and (w == "Rain" or w == "Storm") then
		self.weather:set("Snow")
	elseif name ~= "Winter" and w == "Snow" and self.weatherAuto then
		self.weather:set("Rain")
	end
	if self.onSeason then
		self.onSeason(name, Seasons.get(name))
	end
end

-- "Auto" or a season name.
function Environment:setSeason(mode: string)
	if mode == "Auto" then
		self.seasonAuto = true
		self.seasonTimer = self.config.Seasons.CycleMinutes * 60
		return
	end
	self.seasonAuto = false
	self:_setSeason(mode)
end

-- "Auto" or a weather name.
function Environment:setWeather(mode: string)
	if mode == "Auto" then
		self.weatherAuto = true
		self.weatherTimer = 0
		return
	end
	self.weatherAuto = false
	self.weather:set(mode)
end

-- Menu helpers: Auto -> each option -> Auto.
function Environment:cycleSeason(): string
	local order = { "Auto", table.unpack(Seasons.Order) }
	local current = self.seasonAuto and "Auto" or self.season
	for i, n in order do
		if n == current then
			local nextMode = order[i % #order + 1]
			self:setSeason(nextMode)
			return nextMode
		end
	end
	self:setSeason("Auto")
	return "Auto"
end

function Environment:cycleWeather(): string
	local order = { "Auto", table.unpack(Weather.Types) }
	local current = self.weatherAuto and "Auto" or self.weather.name
	for i, n in order do
		if n == current then
			local nextMode = order[i % #order + 1]
			self:setWeather(nextMode)
			return nextMode
		end
	end
	self:setWeather("Auto")
	return "Auto"
end

function Environment:wetness(): number
	return self.weather.wetness
end

-- Tyre grip multiplier from season and wet roads.
function Environment:gripScale(): number
	return self:seasonPreset().grip * (1 - 0.22 * self.weather.wetness)
end

function Environment:label(): string
	return string.format("%s%s  -  %s%s", self.season, self.seasonAuto and "" or " (locked)", self.weather.name, self.weatherAuto and "" or " (locked)")
end

function Environment:step(dt: number, camCF: CFrame, velocity: Vector3)
	local cfg = self.config
	if self.seasonAuto and cfg.Seasons.CycleMinutes > 0 then
		self.seasonTimer -= dt
		if self.seasonTimer <= 0 then
			self.seasonTimer = cfg.Seasons.CycleMinutes * 60
			self:_setSeason(Seasons.next(self.season))
		end
	end
	if self.weatherAuto then
		self.weatherTimer -= dt
		if self.weatherTimer <= 0 then
			self.weatherTimer = self.rng:NextNumber(cfg.Weather.MinDuration, cfg.Weather.MaxDuration)
			self.weather:set(self:_pickWeather())
		end
	end
	self.weather:step(dt, camCF, velocity, Lighting.ClockTime, self:seasonPreset().ambient, self.qualityScale)
end

return Environment
