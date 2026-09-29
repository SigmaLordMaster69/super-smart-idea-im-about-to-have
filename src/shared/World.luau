--[[
	World
	-----
	Wires the deterministic generator pieces together for one seed:
	  noise -> sections -> road path <-> terrain sampler

	Nothing here touches the DataModel, so the same code runs in Roblox and in
	the offline test harness (tools/).
]]

local Noise = require(script.Parent.Noise)
local Sections = require(script.Parent.Sections)
local RoadPath = require(script.Parent.RoadPath)
local TerrainSampler = require(script.Parent.TerrainSampler)

local World = {}
World.__index = World

function World.new(config, seed: number)
	local self = setmetatable({}, World)
	self.config = config
	self.seed = seed
	self.noise = Noise.new(seed)
	self.sections = Sections.new(config, seed, self.noise)
	self.road = RoadPath.new(config, self.noise, self.sections)
	self.sampler = TerrainSampler.new(config, self.noise, self.sections, self.road)
	self.road.sampler = self.sampler
	return self
end

--[[
	Make sure the road data covers everything a chunk spanning world X range
	[x0, x1] could ask for. Chunks may sit up to `lateral` studs to the side
	of the road, which shifts their projected arc length.
]]
function World:prepareForX(x0: number, x1: number, lateral: number)
	local road = self.road
	road:ensureX(x1 + road.projRadius + 16)
	local kHi = road:indexAtX(x1 + road.projRadius)
	local extra = math.ceil((lateral + 1200) / road.step)
	road:ensureFlags(kHi + extra)
end

return World
