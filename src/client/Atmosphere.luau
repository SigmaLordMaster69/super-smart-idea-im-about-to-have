--[[
	Atmosphere
	----------
	One-time lighting, sky and water setup, plus the day/night clock. Runs
	on the client, so every player can have their own time of day. The
	per-frame look (clouds, fog, grading, sun rays) is driven by Weather,
	terrain colours by Seasons.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Atmosphere = {}

local rgb = Color3.fromRGB

-- time of day presets cycled with T
Atmosphere.Presets = { 7.2, 11.5, 15.2, 18.1, 21.5 }

local function ensure(className: string, parent: Instance, name: string?)
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local inst = Instance.new(className)
	if name then
		inst.Name = name
	end
	inst.Parent = parent
	return inst
end

function Atmosphere.apply(config)
	Lighting.ClockTime = config.Sky.StartClockTime
	Lighting.GeographicLatitude = 38
	Lighting.Brightness = 2.6
	Lighting.Ambient = rgb(70, 74, 82)
	Lighting.OutdoorAmbient = rgb(128, 132, 140)
	Lighting.EnvironmentDiffuseScale = 0.8
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.1

	local atmo = ensure("Atmosphere", Lighting)
	atmo.Density = 0.34
	atmo.Offset = 0.12
	atmo.Color = rgb(198, 212, 228)
	atmo.Decay = rgb(104, 118, 140)
	atmo.Glare = 0.35
	atmo.Haze = 1.6

	local sky = ensure("Sky", Lighting)
	sky.SunAngularSize = 13
	sky.MoonAngularSize = 9
	sky.StarCount = 3000

	local bloom = ensure("BloomEffect", Lighting)
	bloom.Intensity = 0.55
	bloom.Size = 28
	bloom.Threshold = 1.4

	local rays = ensure("SunRaysEffect", Lighting)
	rays.Intensity = 0.05
	rays.Spread = 0.8

	local grade = ensure("ColorCorrectionEffect", Lighting)
	grade.Saturation = 0.08
	grade.Contrast = 0.05
	grade.TintColor = rgb(255, 250, 244)

	local terrain = Workspace.Terrain
	terrain.WaterColor = rgb(22, 96, 112)
	terrain.WaterReflectance = 0.85
	terrain.WaterTransparency = 0.45
	terrain.WaterWaveSize = 0.18
	terrain.WaterWaveSpeed = 10
	pcall(function()
		terrain.Decoration = true -- animated grass blades
	end)
	local clouds = ensure("Clouds", terrain)
	clouds.Cover = 0.58
	clouds.Density = 0.6
	clouds.Color = rgb(250, 250, 252)
end

Atmosphere.clockRunning = true

-- Advance the clock (call every frame).
function Atmosphere.step(dt: number, config)
	local minutes = config.Sky.DayLengthMinutes
	if Atmosphere.clockRunning and minutes and minutes > 0 then
		Lighting.ClockTime = (Lighting.ClockTime + dt * 24 / (minutes * 60)) % 24
	end
end

-- Jump to the next preset time of day.
function Atmosphere.nextPreset()
	local now = Lighting.ClockTime
	for _, t in Atmosphere.Presets do
		if t > now + 0.1 then
			Lighting.ClockTime = t
			return t
		end
	end
	Lighting.ClockTime = Atmosphere.Presets[1]
	return Atmosphere.Presets[1]
end

return Atmosphere
