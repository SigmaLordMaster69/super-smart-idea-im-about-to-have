--[[
	Seasons
	-------
	What each season changes:
	  materials  terrain material colours (grass tones, snowy ground)
	  terrain    flags for TerrainBuilder: snow on flat ground, frozen lakes
	             and rivers, lower snow line
	  grip       tyre grip multiplier
	  weather    weights for picking weather in Auto mode
	  ambient    floating particles (autumn leaves, spring petals)
	Tree colours (blossom, autumn leaves, bare branches) are in Props.
]]

local Seasons = {}

local rgb = Color3.fromRGB

Seasons.Order = { "Spring", "Summer", "Autumn", "Winter" }

-- base terrain colours (summer)
Seasons.BaseColors = {
	[Enum.Material.Grass] = rgb(104, 142, 66),
	[Enum.Material.LeafyGrass] = rgb(78, 118, 52),
	[Enum.Material.Ground] = rgb(122, 98, 72),
	[Enum.Material.Mud] = rgb(86, 72, 58),
	[Enum.Material.Rock] = rgb(122, 118, 112),
	[Enum.Material.Slate] = rgb(96, 96, 100),
	[Enum.Material.Basalt] = rgb(56, 54, 56),
	[Enum.Material.Sand] = rgb(218, 200, 152),
	[Enum.Material.Sandstone] = rgb(178, 94, 58),
	[Enum.Material.Limestone] = rgb(208, 150, 98),
	[Enum.Material.Salt] = rgb(226, 196, 158),
	[Enum.Material.Snow] = rgb(240, 244, 250),
	[Enum.Material.Ice] = rgb(176, 208, 226),
	[Enum.Material.Asphalt] = rgb(60, 62, 66),
}

local NO_SNOW = { snowGround = false, frozen = false, snowLine = 0 }

Seasons.Presets = {
	Spring = {
		materials = {
			[Enum.Material.Grass] = rgb(112, 166, 68),
			[Enum.Material.LeafyGrass] = rgb(88, 148, 56),
		},
		terrain = NO_SNOW,
		grip = 1,
		weather = { Clear = 3, Cloudy = 3, Rain = 3, Storm = 0.8, Fog = 1.2 },
		ambient = "petals",
	},
	Summer = {
		materials = {},
		terrain = NO_SNOW,
		grip = 1,
		weather = { Clear = 5, Cloudy = 2, Rain = 1, Storm = 1.5, Fog = 0.4 },
	},
	Autumn = {
		materials = {
			[Enum.Material.Grass] = rgb(150, 142, 72),
			[Enum.Material.LeafyGrass] = rgb(142, 108, 54),
			[Enum.Material.Ground] = rgb(112, 86, 60),
		},
		terrain = NO_SNOW,
		grip = 0.96,
		weather = { Clear = 2, Cloudy = 3, Rain = 2.5, Storm = 0.6, Fog = 2.5 },
		ambient = "leaves",
	},
	Winter = {
		materials = {
			[Enum.Material.Grass] = rgb(214, 222, 228),
			[Enum.Material.LeafyGrass] = rgb(200, 210, 218),
			[Enum.Material.Ground] = rgb(118, 108, 100),
			[Enum.Material.Snow] = rgb(246, 248, 252),
		},
		terrain = { snowGround = true, frozen = true, snowLine = -150 },
		grip = 0.8,
		weather = { Clear = 2, Cloudy = 3, Snow = 3.5, Fog = 2 },
	},
}

function Seasons.get(name: string)
	return Seasons.Presets[name] or Seasons.Presets.Summer
end

-- Set the terrain material colours for a season.
function Seasons.applyColors(name: string, terrain)
	if not terrain then
		return
	end
	local overrides = Seasons.get(name).materials
	for material, color in Seasons.BaseColors do
		pcall(function()
			terrain:SetMaterialColor(material, overrides[material] or color)
		end)
	end
end

function Seasons.next(name: string): string
	for i, n in Seasons.Order do
		if n == name then
			return Seasons.Order[i % #Seasons.Order + 1]
		end
	end
	return Seasons.Order[1]
end

return Seasons
