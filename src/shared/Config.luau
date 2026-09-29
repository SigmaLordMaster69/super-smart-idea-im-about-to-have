--[[
	Config
	------
	Every tunable number for the Infinite Scenic Road lives here.

	Units are studs. Roblox's default gravity treats 1 stud as ~5 cm, but the
	world is scaled so a car and a lane look right, which puts 1 stud at
	roughly 0.28 m. That makes 1 stud/s almost exactly 1 km/h, and the HUD
	relies on that.
]]

local Config = {}

-- 0 picks a random seed for each server. Every player on the same server
-- drives the same road, but each player's world is generated on their own
-- client.
Config.Seed = 0

Config.SeaLevel = 0

---------------------------------------------------------------------------
-- Road
---------------------------------------------------------------------------
Config.Road = {
	SampleSpacing = 4, -- studs between road samples (XZ arc length)
	LaneWidth = 12,
	Lanes = 2,
	ShoulderWidth = 4, -- paved shoulder outside each edge line
	Thickness = 2, -- road slab thickness (parts)

	MinRadius = 150, -- tightest allowed curve radius
	MaxHeadingDrift = math.rad(74), -- |heading| cap, keeps the road moving +X forever
	MaxGrade = 0.075, -- 7.5 % max slope
	ElevationSmoothing = 190, -- gaussian sigma (studs) applied to the elevation target
	MinElevation = 14, -- road never dips closer than this to sea level

	BankPerCurvature = 18, -- bank angle (rad) per unit curvature
	MaxBank = math.rad(4.5),

	SpawnDistance = 520, -- arc length where players start

	-- Driving on the right. The car spawns in the right-hand lane.
	DriveSide = 1,

	CenterLineColor = Color3.fromRGB(236, 196, 58),
	EdgeLineColor = Color3.fromRGB(240, 240, 235),
	AsphaltColor = Color3.fromRGB(58, 60, 64),
	DashLength = 14,
	DashGap = 22,
}

-- Derived road constants (do not edit)
Config.Road.HalfWidth = Config.Road.LaneWidth * Config.Road.Lanes / 2 + Config.Road.ShoulderWidth

---------------------------------------------------------------------------
-- Structures
---------------------------------------------------------------------------
Config.Tunnel = {
	CoverThreshold = 34, -- rock above the road needed to bore a tunnel instead of a cut
	MinLength = 28, -- samples (x SampleSpacing studs)
	MergeGap = 22, -- samples; shorter daylight gaps between tunnels get merged
	WallHeight = 15,
	CeilingHeight = 25,
	LightSpacing = 12, -- samples between tunnel lights
}

Config.Bridge = {
	GapThreshold = 20, -- road this far above the ground becomes a bridge
	MinLength = 7, -- samples
	MergeGap = 14,
	Pad = 2, -- extra samples at each end for abutments
	PierSpacing = 16, -- samples between piers
	Clearance = 7, -- terrain under a deck is kept at least this far below it
}

Config.GuardRail = {
	DropThreshold = 9, -- a drop this far below the road edge gets a rail
	MinLength = 12,
	MergeGap = 8,
	Pad = 4,
	PostSpacing = 2, -- samples between posts
}

---------------------------------------------------------------------------
-- Regions (biomes). Weight = how often they show up; Length in studs.
---------------------------------------------------------------------------
Config.Regions = {
	Meadow = { Weight = 0.8, Length = { 2200, 3600 }, Twist = 0.75 },
	Forest = { Weight = 1.3, Length = { 2600, 4600 }, Twist = 0.9 },
	Mountains = { Weight = 1.5, Length = { 3200, 6000 }, Twist = 1.15 },
	Coast = { Weight = 1.4, Length = { 3200, 6000 }, Twist = 1.35 },
	Canyon = { Weight = 1.0, Length = { 2800, 5200 }, Twist = 0.85 },
	Lake = { Weight = 1.0, Length = { 2200, 3800 }, Twist = 0.8 },
	RiverValley = { Weight = 1.0, Length = { 3000, 5200 }, Twist = 0.9 },
}
Config.FirstRegion = "Meadow"
Config.RegionTransition = 900 -- blend length between regions (studs)

Config.Terrain = {
	BaseElevation = 95,
	ElevationRange = 55,
	SnowLine = 285,
	TreeLine = 300,
	ProjectionRadius = 1500, -- nearest-road search radius (must exceed World.TerrainRadius + a chunk)
}

---------------------------------------------------------------------------
-- Streaming / generation (client side)
---------------------------------------------------------------------------
Config.World = {
	ChunkSize = 128, -- studs, must be a multiple of 4
	TerrainRadius = 900, -- chunks inside this radius of the car get terrain + road
	UnloadMargin = 260, -- extra distance before a chunk is thrown away
	NearDecorRadius = 460, -- full detail trees/props
	FarDecorRadius = 1000, -- single-part impostor trees
	LookAhead = 1.4, -- seconds of velocity added to the focus point
	FrameBudget = 0.007, -- seconds of generation work per frame while driving
	LoadingFrameBudget = 0.05, -- seconds per frame while the loading screen is up
	RebaseDistance = 16384, -- recentre the world once the car is this far from the Roblox origin
}

---------------------------------------------------------------------------
-- Vegetation densities (0..1 per 16x16 stud cell)
---------------------------------------------------------------------------
Config.Decor = {
	CellSize = 16,
	Density = {
		Meadow = 0.07,
		Forest = 0.62,
		Mountains = 0.34,
		Coast = 0.22,
		Canyon = 0.07,
		Lake = 0.36,
		RiverValley = 0.4,
	},
	RoadClearance = 9, -- no trees within this distance of the road edge
}

---------------------------------------------------------------------------
-- Car
---------------------------------------------------------------------------
Config.Car = {
	TopSpeed = 150, -- studs/s (~150 km/h)
	ReverseSpeed = 30,
	Acceleration = 42, -- studs/s^2 at low speed
	BrakeDeceleration = 110,
	CoastDeceleration = 5,
	MaxSteerLow = math.rad(34),
	MaxSteerHigh = math.rad(6.5),
	SteerSpeed = 3.2, -- how fast the wheels turn (per second, 0..1 of max)

	SuspensionLength = 2.6,
	SuspensionFrequency = 2.3, -- Hz (sets the sag: g / (2 pi f)^2 ~ 0.9 studs)
	SuspensionDamping = 0.55, -- damping ratio
	WheelRadius = 1.6,
	Grip = 1.35, -- friction coefficient
	HandbrakeGrip = 0.45,

	Colors = {
		Color3.fromRGB(200, 58, 48),
		Color3.fromRGB(236, 236, 230),
		Color3.fromRGB(46, 104, 180),
		Color3.fromRGB(242, 178, 52),
		Color3.fromRGB(58, 130, 96),
		Color3.fromRGB(34, 36, 40),
		Color3.fromRGB(150, 196, 214),
	},

	AutoDriveSpeed = 95, -- cruise speed on straights
	AutoDriveLateralAccel = 70, -- studs/s^2 it is willing to pull in corners
}

---------------------------------------------------------------------------
-- Atmosphere
---------------------------------------------------------------------------
Config.Sky = {
	StartClockTime = 15.2,
	DayLengthMinutes = 24, -- real minutes per in-game day, 0 freezes time
}

-- Hide other players' avatars. Each player drives in their own
-- client-generated world, so other avatars would float in odd places.
Config.HideOtherPlayers = true

return Config
