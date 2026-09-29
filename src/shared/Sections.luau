--[[
	Sections
	--------
	The road is split into consecutive "sections", one region type each
	(Meadow, Forest, Mountains, Coast, Canyon, Lake, RiverValley). Sections are
	generated lazily from the seed, so the sequence is the same every time.

	Neighbouring sections cross-fade over Config.RegionTransition studs, so at
	most two regions are active at any arc length.

	Each section also gets a list of "crossings": landforms that cross the
	road at an angle.
	  ridge : a mountain spur the road has to tunnel through
	  river : a river valley the road bridges over
	  gorge : a deep, narrow canyon (big bridge)
]]

local MathUtil = require(script.Parent.MathUtil)

local smoothstep = MathUtil.smoothstep
local clamp = MathUtil.clamp

local Sections = {}
Sections.__index = Sections

local TYPES = { "Meadow", "Forest", "Mountains", "Coast", "Canyon", "Lake", "RiverValley" }
Sections.Types = TYPES

-- No crossing reaches farther than this from where it meets the road.
Sections.MaxCrossingLength = 2800

local NAME_PARTS = {
	Coast = {
		{ "Seagull", "Driftwood", "Coral", "Pelican", "Saltspray", "Whitecap", "Mariner's", "Lighthouse", "Sandpiper", "Tidewater", "Sunset", "Kelp" },
		{ "Bay", "Cove", "Point", "Coast", "Bluffs", "Cliffs", "Head", "Shores" },
	},
	Canyon = {
		{ "Redrock", "Copper", "Rattlesnake", "Vermilion", "Coyote", "Painted", "Echo", "Dusty", "Sandstone", "Ember", "Mesa", "Sunburnt" },
		{ "Canyon", "Gorge", "Gulch", "Narrows", "Canyonlands" },
	},
	Mountains = {
		{ "Granite", "Eagle", "Thunder", "Frost", "Summit", "Iron", "Wolf", "Silver", "Glacier", "Stormy", "Hawk", "Cloudy" },
		{ "Pass", "Ridge", "Peaks", "Divide", "Heights", "Range" },
	},
	Forest = {
		{ "Pinecrest", "Mossy", "Elderwood", "Fernhollow", "Cedar", "Whispering", "Owl", "Maple", "Deepwood", "Timber", "Hollow", "Bramble" },
		{ "Forest", "Woods", "Grove", "Timberland", "Wilds" },
	},
	Meadow = {
		{ "Clover", "Buttercup", "Sunny", "Windmill", "Lark", "Golden", "Honey", "Bluebell", "Poppy", "Harvest" },
		{ "Meadows", "Fields", "Downs", "Prairie", "Flats", "Hills" },
	},
	Lake = {
		{ "Serene", "Crystal", "Mirror", "Loon", "Willow", "Heron", "Emerald", "Stillwater", "Moonlit", "Silverfish" },
		{ "Lake" },
	},
	RiverValley = {
		{ "Trout", "Otter", "Willow", "Stone", "Rapid", "Kingfisher", "Alder", "Bear", "Salmon", "Heron" },
		{ "River Valley", "River", "Creek", "Falls" },
	},
}

local function makeName(rng, regionType: string): string
	local parts = NAME_PARTS[regionType]
	local a = parts[1][rng:NextInteger(1, #parts[1])]
	local b = parts[2][rng:NextInteger(1, #parts[2])]
	if regionType == "Lake" and rng:NextNumber() < 0.5 then
		return "Lake " .. a
	end
	return a .. " " .. b
end

function Sections.new(config, seed: number, noise)
	local self = setmetatable({}, Sections)
	self.config = config
	self.seed = seed
	self.noise = noise
	self.list = {}
	self.crossings = {}
	self.transition = config.RegionTransition
	self:_append()
	return self
end

-- Regional base elevation: a very slow wave along the road that everything
-- else is layered on.
function Sections:regionalElevation(s: number): number
	local t = self.config.Terrain
	return t.BaseElevation + t.ElevationRange * clamp(self.noise:fbm1(s / 6500, 3, 41), -1, 1)
end

local function pickType(rng, config, previous: string?, beforePrevious: string?): string
	local total = 0
	for _, name in TYPES do
		if name ~= previous and name ~= beforePrevious then
			total += config.Regions[name].Weight
		end
	end
	local roll = rng:NextNumber() * total
	for _, name in TYPES do
		if name ~= previous and name ~= beforePrevious then
			roll -= config.Regions[name].Weight
			if roll <= 0 then
				return name
			end
		end
	end
	return "Forest"
end

-- Crossing kinds per region: { kind, chance per slot, min spacing, max spacing }
-- Rules are tried in order for each slot; the first that passes its chance
-- wins the slot.
local CROSSING_RULES = {
	Mountains = { { "ridge", 0.65 }, { "gorge", 0.35 }, { "river", 0.4 } },
	Forest = { { "river", 0.65 }, { "ridge", 0.35 } },
	Meadow = { { "river", 0.6 } },
	Coast = { { "ridge", 0.6 }, { "river", 0.55 } },
	Canyon = { { "gorge", 0.7 } },
	Lake = {},
	RiverValley = {},
}

function Sections:_makeCrossings(sec, rng)
	local rules = CROSSING_RULES[sec.type]
	if #rules == 0 then
		return
	end
	local margin = self.transition * 0.5 + 250
	local s = math.max(sec.startS, self.config.Road.SpawnDistance + 500) + margin
	local stop = sec.endS - margin
	while true do
		s += rng:NextNumber(700, 1500)
		if s > stop then
			break
		end
		for _, rule in rules do
			if rng:NextNumber() < rule[2] then
				local c = {
					kind = rule[1],
					s = s,
					section = sec,
					angle = rng:NextNumber(-0.55, 0.55),
					flow = rng:NextNumber() < 0.5 and -1 or 1,
					resolved = false,
				}
				if sec.type == "Coast" then
					c.flow = sec.side -- coastal rivers run down to the sea
				end
				if c.kind == "ridge" then
					c.width = rng:NextNumber(110, 220)
					c.height = rng:NextNumber(75, 170)
					c.length = rng:NextNumber(900, 1800)
				elseif c.kind == "river" then
					c.clearance = rng:NextNumber(16, 34)
					c.depth = rng:NextNumber(4, 7)
					c.channelHalf = rng:NextNumber(9, 17)
					c.valleySlope = rng:NextNumber(0.3, 0.7)
					c.slope = rng:NextNumber(0.006, 0.02)
					c.meander = rng:NextNumber(30, 90)
					c.length = rng:NextNumber(1400, 2600)
				elseif c.kind == "gorge" then
					c.clearance = rng:NextNumber(55, 110)
					c.depth = rng:NextNumber(5, 8)
					c.channelHalf = rng:NextNumber(12, 20)
					c.valleySlope = rng:NextNumber(2.2, 4)
					c.slope = rng:NextNumber(0.004, 0.012)
					c.meander = rng:NextNumber(20, 60)
					c.length = rng:NextNumber(1600, 2800)
				end
				assert(c.length <= Sections.MaxCrossingLength)
				table.insert(sec.crossings, c)
				table.insert(self.crossings, c)
				break
			end
		end
	end
end

function Sections:_append()
	local list = self.list
	local index = #list + 1
	local rng = Random.new(MathUtil.hash(self.seed, index, 7717))
	local prev = list[index - 1]
	local regionType
	if index == 1 then
		regionType = self.config.FirstRegion
	else
		regionType = pickType(rng, self.config, prev.type, list[index - 2] and list[index - 2].type)
	end
	local rules = self.config.Regions[regionType]
	local length = rng:NextNumber(rules.Length[1], rules.Length[2])

	local sec = {
		index = index,
		type = regionType,
		startS = prev and prev.endS or -1e9,
		endS = 0,
		twist = rules.Twist,
		side = rng:NextNumber() < 0.5 and -1 or 1,
		name = makeName(rng, regionType),
		crossings = {},
	}
	if index == 1 then
		sec.endS = self.config.Road.SpawnDistance + length
	else
		sec.endS = sec.startS + length
	end
	local mid = index == 1 and sec.endS * 0.5 or (sec.startS + sec.endS) * 0.5

	if regionType == "Lake" then
		-- lake level is one constant for the whole section
		sec.lakeLevel = math.max(self.config.SeaLevel + 10, self:regionalElevation(mid) - 6)
		sec.lakeWidth = rng:NextNumber(260, 520)
	elseif regionType == "Canyon" then
		sec.depth = rng:NextNumber(95, 175)
		sec.floorHalf = rng:NextNumber(62, 92)
	elseif regionType == "Coast" then
		sec.shelf = rng:NextNumber(48, 92)
	elseif regionType == "Forest" then
		sec.autumn = rng:NextNumber() < 0.3
	elseif regionType == "RiverValley" then
		sec.channelHalf = rng:NextNumber(10, 16)
	end
	if regionType == "Canyon" or regionType == "RiverValley" then
		sec.riverSide = rng:NextNumber() < 0.5 and -1 or 1
	end

	table.insert(list, sec)
	self:_makeCrossings(sec, rng)
	return sec
end

function Sections:ensure(s: number)
	local list = self.list
	while list[#list].endS < s + self.transition do
		self:_append()
	end
end

function Sections:find(s: number): number
	self:ensure(s)
	local list = self.list
	local lo, hi = 1, #list
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if list[mid].startS <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

function Sections:get(s: number)
	return self.list[self:find(s)]
end

-- Returns up to two sections and their weights at arc length s:
--   secA, wA, secB, wB (secB may be nil)
function Sections:weightsAt(s: number)
	local list = self.list
	local i = self:find(s)
	local sec = list[i]
	local half = self.transition * 0.5
	if i > 1 and s < sec.startS + half then
		local t = smoothstep(sec.startS - half, sec.startS + half, s)
		return sec, t, list[i - 1], 1 - t
	elseif s > sec.endS - half then
		local t = smoothstep(sec.endS - half, sec.endS + half, s)
		return sec, 1 - t, list[i + 1], t
	end
	return sec, 1, nil, 0
end

-- Weight of one region type at arc length s.
function Sections:typeWeight(s: number, regionType: string): number
	local a, wa, b, wb = self:weightsAt(s)
	local w = 0
	if a.type == regionType then
		w += wa
	end
	if b and b.type == regionType then
		w += wb
	end
	return w
end

function Sections:twistAt(s: number): number
	local a, wa, b, wb = self:weightsAt(s)
	local t = a.twist * wa
	if b then
		t += b.twist * wb
	end
	return t
end

-- Collects crossings whose arc length lies in [sLo, sHi] into `out`.
-- Returns the count.
function Sections:crossingsBetween(sLo: number, sHi: number, out): number
	self:ensure(sHi)
	local cs = self.crossings
	local n = #cs
	local lo, hi = 1, n + 1
	while lo < hi do
		local mid = (lo + hi) // 2
		if cs[mid].s < sLo then
			lo = mid + 1
		else
			hi = mid
		end
	end
	local count = 0
	for i = lo, n do
		local c = cs[i]
		if c.s > sHi then
			break
		end
		count += 1
		out[count] = c
	end
	return count
end

return Sections
