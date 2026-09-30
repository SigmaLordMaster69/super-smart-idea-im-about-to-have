--[[
	SoundUtil
	---------
	Config.Sounds entries can be:
	  ""                                  silence
	  "rbxassetid://123"                  a sound that loops (or plays) as is
	  { Id = "rbxassetid://123",          a recording where only part loops
	    Loop = { 19.36, 34.54 },          (seconds), and/or
	    Gain = 2 }                        a loudness correction (volume factor)
	  { entry, entry, ... }               several; one is picked at random
]]

local SoundUtil = {}

local MAX_VOLUME = 10

-- The entry to use (picks one from a list).
function SoundUtil.pick(entry, rng)
	if type(entry) == "table" and entry.Id == nil then
		if #entry == 0 then
			return nil
		end
		local i = rng and rng:NextInteger(1, #entry) or math.random(1, #entry)
		return entry[i]
	end
	return entry
end

function SoundUtil.id(entry): string?
	entry = SoundUtil.pick(entry)
	local id = type(entry) == "table" and entry.Id or entry
	if type(id) ~= "string" or id == "" then
		return nil
	end
	return id
end

-- Volume with the entry's loudness correction (use for later changes).
function SoundUtil.setVolume(sound: Sound, volume: number)
	sound.Volume = math.min(MAX_VOLUME, volume * (sound:GetAttribute("Gain") or 1))
end

--[[
	Makes a Sound for `entry` under `parent`, or returns nil for silence.
	The sound starts playing once it is in the world.
]]
function SoundUtil.make(entry, parent: Instance?, volume: number, looped: boolean, rng): Sound?
	entry = SoundUtil.pick(entry, rng)
	local id = SoundUtil.id(entry)
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = looped
	if type(entry) == "table" then
		if entry.Gain then
			s:SetAttribute("Gain", entry.Gain)
		end
		if entry.Loop then
			local a, b = entry.Loop[1], entry.Loop[2]
			s.PlaybackRegionsEnabled = true
			s.PlaybackRegion = NumberRange.new(a, b)
			s.LoopRegion = NumberRange.new(a, b)
		end
	end
	SoundUtil.setVolume(s, volume)
	s.Playing = true
	s.Parent = parent
	return s
end

return SoundUtil
