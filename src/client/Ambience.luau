--[[
	Ambience
	--------
	Background loops that follow the landscape: birds in forests, meadows
	and river valleys, surf along the coast and the ocean, a breeze in the
	mountains and canyons. They cross-fade as the region changes, quieten
	at night and in the rain, and are muffled in tunnels.

	Uses Config.Sounds.Birds / Surf / Breeze. The older single
	Config.Sounds.Ambience loop, if set, plays everywhere instead.
]]

local SoundUtil = require(script.Parent.SoundUtil)

local Ambience = {}
Ambience.__index = Ambience

-- how much of each loop a region wants
local MIX = {
	Meadow = { Birds = 1, Breeze = 0.3 },
	Forest = { Birds = 1 },
	RiverValley = { Birds = 0.9, Breeze = 0.2 },
	Lake = { Birds = 0.8, Breeze = 0.3 },
	Mountains = { Breeze = 1, Birds = 0.25 },
	Canyon = { Breeze = 1 },
	Coast = { Surf = 1, Breeze = 0.3 },
	Ocean = { Surf = 0.8, Breeze = 0.5 },
}
local LOOPS = { Birds = 0.45, Surf = 0.5, Breeze = 0.4 } -- full volume of each

function Ambience.new(config, parent: Instance)
	local self = setmetatable({}, Ambience)
	local sounds = config.Sounds or {}
	self.sounds = {}
	self.levels = {}
	if SoundUtil.id(sounds.Ambience) then
		self.sounds.Ambience = SoundUtil.make(sounds.Ambience, parent, 0, true)
		self.levels.Ambience = 0
		self.single = true
	else
		for name in LOOPS do
			local s = SoundUtil.make(sounds[name], parent, 0, true)
			if s then
				self.sounds[name] = s
				self.levels[name] = 0
			end
		end
	end
	return self
end

--[[
	regionType  Sections type at the car
	rain        0..1 rain strength
	night       0..1 (1 = night)
	covered     true in tunnels
]]
function Ambience:step(dt: number, regionType: string?, rain: number, night: number, covered: boolean)
	local k = 1 - math.exp(-dt / 2.5)
	local mix = MIX[regionType or ""] or MIX.Meadow
	local muffle = covered and 0.3 or 1
	for name, s in self.sounds do
		local want
		if self.single then
			want = 0.3
		else
			want = (mix[name] or 0) * LOOPS[name]
			if name == "Birds" then
				want *= (1 - 0.75 * night) * (1 - 0.8 * rain)
			end
		end
		want *= muffle
		local level = self.levels[name] + (want - self.levels[name]) * k
		self.levels[name] = level
		SoundUtil.setVolume(s, level)
	end
end

return Ambience
