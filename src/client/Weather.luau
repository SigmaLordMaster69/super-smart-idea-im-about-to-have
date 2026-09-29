--[[
	Weather
	-------
	Clear, Cloudy, Rain, Storm, Fog and Snow, blended smoothly over about
	half a minute. Every frame it sets clouds, atmosphere, light, sun rays
	and colour grading from the blended weather and the time of day (warm
	sunrises and sunsets, cool nights).

	Effects:
	  * rain streaks / snowflakes from an emitter that follows the camera,
	    switched off under roofs (tunnels, bridges)
	  * lightning bolts with a screen flash and delayed thunder in storms
	  * road wetness that builds up in rain and dries afterwards; asphalt
	    parts tagged "IR_Asphalt" get darker and reflective
	  * floating autumn leaves or spring petals, if the season asks for it
]]

local CollectionService = game:GetService("CollectionService")

local Weather = {}
Weather.__index = Weather

local rgb = Color3.fromRGB
local exp, sin, clamp, max, min, abs = math.exp, math.sin, math.clamp, math.max, math.min, math.abs

Weather.Types = { "Clear", "Cloudy", "Rain", "Storm", "Fog", "Snow" }

-- cover/cdens: clouds, atmo/haze/glare: atmosphere, rays: sun rays,
-- bright/exposure: light, sat/contrast: grading, rain/snow/storm: effects
local PRESETS = {
	Clear = { cover = 0.45, cdens = 0.55, atmo = 0.3, haze = 1.4, glare = 0.5, rays = 0.13, bright = 1, exposure = 0.1, sat = 0.1, contrast = 0.06, rain = 0, snow = 0, storm = 0, fog = rgb(198, 212, 228) },
	Cloudy = { cover = 0.8, cdens = 0.72, atmo = 0.36, haze = 2.0, glare = 0.15, rays = 0.05, bright = 0.82, exposure = 0.05, sat = 0.0, contrast = 0.04, rain = 0, snow = 0, storm = 0, fog = rgb(188, 196, 206) },
	Rain = { cover = 0.92, cdens = 0.86, atmo = 0.45, haze = 2.6, glare = 0, rays = 0, bright = 0.6, exposure = -0.05, sat = -0.1, contrast = 0.03, rain = 0.7, snow = 0, storm = 0, fog = rgb(158, 168, 180) },
	Storm = { cover = 0.98, cdens = 0.96, atmo = 0.5, haze = 3.0, glare = 0, rays = 0, bright = 0.42, exposure = -0.15, sat = -0.16, contrast = 0.08, rain = 1, snow = 0, storm = 1, fog = rgb(118, 126, 138) },
	Fog = { cover = 0.7, cdens = 0.5, atmo = 0.68, haze = 3.4, glare = 0, rays = 0.02, bright = 0.78, exposure = 0, sat = -0.06, contrast = 0.0, rain = 0, snow = 0, storm = 0, fog = rgb(202, 206, 212) },
	Snow = { cover = 0.9, cdens = 0.8, atmo = 0.46, haze = 2.4, glare = 0.1, rays = 0, bright = 0.9, exposure = 0.05, sat = -0.12, contrast = 0.02, rain = 0, snow = 0.85, storm = 0, fog = rgb(214, 220, 230) },
}
Weather.Presets = PRESETS

local APPLY_INTERVAL = 0.1

local FIELDS = { "cover", "cdens", "atmo", "haze", "glare", "rays", "bright", "exposure", "sat", "contrast", "rain", "snow", "storm" }

local function ensure(className: string, parent: Instance, name: string)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local function emitterPart(name: string, size: Vector3, parent: Instance)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = parent
	return p
end

local function seq(a: number, b: number?)
	if b == nil then
		return NumberSequence.new(a)
	end
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

--[[
	deps:
	  lighting  the Lighting service
	  terrain   Workspace.Terrain (optional; clouds live under it)
	  parent    where effect parts go
	  raycast   function(origin, direction) -> RaycastResult? (optional)
]]
function Weather.new(config, deps)
	local self = setmetatable({}, Weather)
	self.config = config
	self.lighting = deps.lighting
	self.terrain = deps.terrain
	self.parent = deps.parent
	self.raycast = deps.raycast
	self.name = "Clear"
	self.target = PRESETS.Clear
	self.cur = table.clone(PRESETS.Clear)
	self.wetness = 0
	self.appliedWetness = 0
	self.rng = Random.new()
	self.strikeTimer = 6
	self.flash = 0
	self.covered = false
	self.coverCheck = 0
	self.wetQueue = nil
	self.applyTimer = 0

	local lighting = self.lighting
	self.atmosphere = lighting:FindFirstChildOfClass("Atmosphere") or ensure("Atmosphere", lighting, "Atmosphere")
	self.rays = lighting:FindFirstChildOfClass("SunRaysEffect") or ensure("SunRaysEffect", lighting, "SunRays")
	self.grade = ensure("ColorCorrectionEffect", lighting, "WeatherGrade")
	self.flashEffect = ensure("ColorCorrectionEffect", lighting, "LightningFlash")
	self.flashEffect.Brightness = 0
	if self.terrain then
		self.clouds = self.terrain:FindFirstChildOfClass("Clouds") or ensure("Clouds", self.terrain, "Clouds")
	end

	local textures = config.Textures
	local folder = Instance.new("Folder")
	folder.Name = "WeatherEffects"
	folder.Parent = self.parent
	self.folder = folder

	-- rain and snow come from a wide plate above the camera
	local sky = emitterPart("Precipitation", Vector3.new(180, 1, 180), folder)
	self.skyPart = sky
	local rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.Texture = textures.Rain
	rain.Color = ColorSequence.new(rgb(196, 208, 224))
	rain.Transparency = seq(0.35)
	rain.LightEmission = 0.15
	rain.LightInfluence = 1
	rain.Size = seq(0.12)
	rain.Squash = seq(2.4)
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Speed = NumberRange.new(110, 135)
	rain.SpreadAngle = Vector2.new(4, 4)
	rain.Lifetime = NumberRange.new(0.55, 0.75)
	rain.Rate = 0
	rain.Parent = sky
	self.rainEmitter = rain

	local snow = Instance.new("ParticleEmitter")
	snow.Name = "Snow"
	snow.Texture = textures.Snow
	snow.Color = ColorSequence.new(rgb(250, 252, 255))
	snow.Transparency = seq(0.1, 0.4)
	snow.LightEmission = 0.3
	snow.LightInfluence = 1
	snow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3, 0.12), NumberSequenceKeypoint.new(1, 0.3, 0.12) })
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Speed = NumberRange.new(9, 15)
	snow.SpreadAngle = Vector2.new(35, 35)
	snow.Acceleration = Vector3.new(3, 0, 1.5)
	snow.Drag = 0.4
	snow.Rotation = NumberRange.new(0, 360)
	snow.RotSpeed = NumberRange.new(-60, 60)
	snow.Lifetime = NumberRange.new(4.5, 6)
	snow.Rate = 0
	snow.Parent = sky
	self.snowEmitter = snow

	-- leaves / petals drift down closer to the camera
	local drift = emitterPart("Drift", Vector3.new(110, 1, 110), folder)
	self.driftPart = drift
	local leaves = Instance.new("ParticleEmitter")
	leaves.Name = "Leaves"
	leaves.Texture = textures.Leaf
	leaves.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(222, 128, 42)),
		ColorSequenceKeypoint.new(0.5, rgb(196, 70, 40)),
		ColorSequenceKeypoint.new(1, rgb(230, 184, 64)),
	})
	leaves.Transparency = seq(0.05, 0.5)
	leaves.LightInfluence = 1
	leaves.Size = seq(0.45, 0.35)
	leaves.Squash = seq(-0.6)
	leaves.EmissionDirection = Enum.NormalId.Bottom
	leaves.Speed = NumberRange.new(3, 6)
	leaves.SpreadAngle = Vector2.new(60, 60)
	leaves.Acceleration = Vector3.new(4, -3, 2)
	leaves.Drag = 0.6
	leaves.Rotation = NumberRange.new(0, 360)
	leaves.RotSpeed = NumberRange.new(-120, 120)
	leaves.Lifetime = NumberRange.new(5, 7)
	leaves.Rate = 0
	leaves.Parent = drift
	self.leafEmitter = leaves
	local petals = leaves:Clone()
	petals.Name = "Petals"
	petals.Color = ColorSequence.new(rgb(248, 206, 222), rgb(255, 240, 246))
	petals.Size = seq(0.3, 0.22)
	petals.Parent = drift
	self.petalEmitter = petals

	local sounds = config.Sounds or {}
	if sounds.Rain and sounds.Rain ~= "" then
		local s = Instance.new("Sound")
		s.Name = "RainLoop"
		s.SoundId = sounds.Rain
		s.Looped = true
		s.Volume = 0
		s.Parent = folder
		s:Play()
		self.rainSound = s
	end
	self.thunderId = sounds.Thunder
	return self
end

-- Change weather (blends over Config.Weather.TransitionTime).
function Weather:set(name: string, instant: boolean?)
	local preset = PRESETS[name]
	if not preset then
		return
	end
	self.name = name
	self.target = preset
	if instant then
		self.cur = table.clone(preset)
		self.applyTimer = 0
	end
end

---------------------------------------------------------------------------
-- Lightning
---------------------------------------------------------------------------
function Weather:_segment(folder, a: Vector3, b: Vector3, width: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = rgb(214, 224, 255)
	p.Size = Vector3.new(width, width, (b - a).Magnitude)
	p.CFrame = CFrame.lookAt((a + b) * 0.5, b)
	p.Parent = folder
end

function Weather:strike(camCF: CFrame)
	local rng = self.rng
	local look = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	local dir = CFrame.Angles(0, rng:NextNumber(-1.1, 1.1), 0):VectorToWorldSpace(look.Unit)
	local dist = rng:NextNumber(350, 950)
	local ground = camCF.Position + dir * dist
	local gy = ground.Y - 40
	if self.raycast then
		local hit = self.raycast(Vector3.new(ground.X, ground.Y + 900, ground.Z), Vector3.new(0, -1800, 0))
		if hit then
			gy = hit.Position.Y
		end
	end
	local bottom = Vector3.new(ground.X, gy, ground.Z)
	local top = bottom + Vector3.new(rng:NextNumber(-80, 80), 650, rng:NextNumber(-80, 80))
	local folder = Instance.new("Folder")
	folder.Name = "Lightning"
	local prev = top
	local n = 14
	for i = 1, n do
		local t = i / n
		local p = top:Lerp(bottom, t)
		if i < n then
			p += Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 38 * (1 - t * 0.5)
		end
		self:_segment(folder, prev, p, 1.6 - t * 0.7)
		-- a side branch now and then
		if i > 2 and i < n - 2 and rng:NextNumber() < 0.25 then
			local b = p + Vector3.new(rng:NextNumber(-70, 70), -rng:NextNumber(40, 90), rng:NextNumber(-70, 70))
			self:_segment(folder, p, b, 0.6)
		end
		prev = p
	end
	folder.Parent = self.folder
	self.flash = 1
	task.delay(0.08, function()
		for _, p in folder:GetChildren() do
			p.Transparency = 0.8
		end
	end)
	task.delay(0.15, function()
		self.flash = max(self.flash, 0.7)
		for _, p in folder:GetChildren() do
			p.Transparency = 0
		end
	end)
	task.delay(0.32, function()
		folder:Destroy()
	end)
	if self.thunderId and self.thunderId ~= "" then
		task.delay(dist / 1225, function()
			local s = Instance.new("Sound")
			s.SoundId = self.thunderId
			s.Volume = clamp(1.4 - dist / 1100, 0.3, 1)
			s.PlaybackSpeed = self.rng:NextNumber(0.85, 1.05)
			s.Parent = self.folder
			s:Play()
			task.delay(12, function()
				s:Destroy()
			end)
		end)
	end
end

---------------------------------------------------------------------------
-- Per frame
---------------------------------------------------------------------------
--[[
	camCF    camera CFrame
	velocity car velocity (the precipitation leads it a little)
	clock    Lighting.ClockTime
	ambient  "leaves" / "petals" / nil (from the season)
	quality  0..1 particle amount
]]
function Weather:step(dt: number, camCF: CFrame, velocity: Vector3, clock: number, ambient: string?, quality: number)
	local cur, target = self.cur, self.target
	local k = 1 - exp(-dt / self.config.Weather.TransitionTime)
	for _, f in FIELDS do
		cur[f] += (target[f] - cur[f]) * k
	end
	cur.fog = cur.fog:Lerp(target.fog, k)

	-- lighting, clouds and grading change slowly: 10 updates a second is
	-- plenty and saves setting ~20 properties every frame
	self.applyTimer -= dt
	if self.applyTimer <= 0 then
		self.applyTimer = APPLY_INTERVAL
		self:_applyLook(clock)
	end
	self:_effects(dt, camCF, velocity, ambient, quality)
end

function Weather:_applyLook(clock: number)
	local cur = self.cur
	-- time of day: 1 in daylight, 0 at night; warm near sunrise/sunset
	local day = clamp((sin((clock - 6) / 12 * math.pi) + 0.12) / 0.4, 0, 1)
	local warm = exp(-((clock - 6.6) / 1.1) ^ 2) + exp(-((clock - 17.9) / 1.1) ^ 2)
	local night = 1 - day

	local lighting = self.lighting
	local atmo = self.atmosphere
	atmo.Density = cur.atmo
	atmo.Haze = cur.haze
	atmo.Glare = cur.glare * (0.5 + warm)
	atmo.Color = cur.fog:Lerp(rgb(236, 176, 136), warm * 0.45 * (1 - cur.storm)):Lerp(rgb(30, 36, 54), night * 0.85)
	atmo.Decay = rgb(104, 118, 140):Lerp(rgb(170, 110, 86), warm * 0.4):Lerp(rgb(18, 22, 34), night * 0.8)
	if self.clouds then
		self.clouds.Cover = cur.cover
		self.clouds.Density = cur.cdens
		self.clouds.Color = rgb(252, 252, 254):Lerp(rgb(96, 100, 112), cur.storm * 0.6):Lerp(rgb(255, 190, 150), warm * 0.55):Lerp(rgb(56, 62, 78), night * 0.9)
	end
	lighting.Brightness = 2.6 * cur.bright
	lighting.ExposureCompensation = cur.exposure
	lighting.OutdoorAmbient = rgb(128, 132, 140):Lerp(rgb(70, 78, 98), night)
	self.rays.Intensity = cur.rays * (0.6 + 1.4 * warm) * day
	self.rays.Spread = 0.75
	local grade = self.grade
	grade.Saturation = cur.sat + 0.06 * warm
	grade.Contrast = cur.contrast
	grade.TintColor = Color3.new(1, 1, 1):Lerp(rgb(255, 224, 194), warm * 0.45):Lerp(rgb(206, 218, 255), night * 0.45)
end

function Weather:_effects(dt: number, camCF: CFrame, velocity: Vector3, ambient: string?, quality: number)
	local cur = self.cur
	-- lightning flash
	if self.flash > 0.001 then
		self.flashEffect.Brightness = 0.45 * self.flash
		self.flash *= exp(-dt * 10)
	elseif self.flashEffect.Brightness ~= 0 then
		self.flashEffect.Brightness = 0
	end
	if cur.storm > 0.5 then
		self.strikeTimer -= dt
		if self.strikeTimer <= 0 then
			self.strikeTimer = self.rng:NextNumber(3, 12) / cur.storm
			self:strike(camCF)
		end
	end

	-- precipitation follows the camera, off under a roof
	local pos = camCF.Position
	self.coverCheck -= dt
	if self.coverCheck <= 0 and self.raycast then
		self.coverCheck = 0.25
		self.covered = self.raycast(pos, Vector3.new(0, 70, 0)) ~= nil
	end
	local look = Vector3.new(camCF.LookVector.X, 0, camCF.LookVector.Z)
	local lead = velocity * 0.6
	self.skyPart.CFrame = CFrame.new(pos + look * 30 + lead + Vector3.new(0, 42, 0))
	self.driftPart.CFrame = CFrame.new(pos + look * 20 + lead * 0.5 + Vector3.new(0, 16, 0))
	local open = self.covered and 0 or 1
	self.rainEmitter.Rate = cur.rain * 950 * quality * open
	self.snowEmitter.Rate = cur.snow * 480 * quality * open
	local calm = 1 - clamp(cur.rain + cur.snow, 0, 1)
	self.leafEmitter.Rate = ambient == "leaves" and 34 * quality * calm * open or 0
	self.petalEmitter.Rate = ambient == "petals" and 18 * quality * calm * open or 0
	if self.rainSound then
		self.rainSound.Volume = cur.rain * 0.6 * (self.covered and 0.35 or 1)
	end

	-- wet roads
	if cur.rain > 0.15 then
		self.wetness = min(1, self.wetness + dt / 25 * cur.rain)
	elseif cur.snow > 0.3 then
		self.wetness += (0.35 - self.wetness) * (1 - exp(-dt / 30))
	else
		self.wetness = max(0, self.wetness - dt / 90)
	end
	self:_updateRoads()
end

-- How wet asphalt looks: darker and more reflective.
function Weather.wetLook(base: Color3, wetness: number): (Color3, number)
	return base:Lerp(rgb(32, 34, 38), wetness * 0.75), wetness * 0.28
end

-- Re-colour tagged asphalt in batches whenever wetness has moved enough.
function Weather:_updateRoads()
	local queue = self.wetQueue
	if not queue then
		if abs(self.wetness - self.appliedWetness) < 0.05 then
			return
		end
		self.appliedWetness = self.wetness
		self.wetQueue = { parts = CollectionService:GetTagged("IR_Asphalt"), i = 1 }
		queue = self.wetQueue
	end
	local base = self.config.Road.AsphaltColor
	local color, reflect = Weather.wetLook(base, self.appliedWetness)
	local parts = queue.parts
	local last = min(#parts, queue.i + 499)
	for i = queue.i, last do
		local p = parts[i]
		if p.Parent then
			p.Color = color
			p.Reflectance = reflect
		end
	end
	queue.i = last + 1
	if queue.i > #parts then
		self.wetQueue = nil
	end
end

return Weather
