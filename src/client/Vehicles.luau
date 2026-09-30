--[[
	Vehicles
	--------
	The vehicle catalogue. Every entry is a spec:
	  id           key used everywhere (Car.new, menus, asset slots)
	  name         display name
	  category     "Car" or "Bike" (menu grouping)
	  kind         physics/visual family: "Car" (four wheels) or "Motorcycle"
	  description  one line for the vehicle picker
	  colors       paint choices
	  tuning       overrides on top of Config.Car / Config.Motorcycle
	  sound        key in Config.Sounds for the engine loop (falls back to
	               Engine / MotorcycleEngine)
	  camera       chase distance and height (studs), and `hood`: where the
	               hood camera sits. For cars it is an offset from the
	               chassis centre; for bikes it is an offset from the top of
	               the seat, in the leaning frame (the rider's eyes).
	  body         module in VehicleBodies that draws it (defaults to id)

	Car.new(config, color, assets, id) builds one.

	Sizes follow real vehicles at the game's scale (1 stud is about 0.28 m,
	so 1 m is about 3.6 studs):
	  Sedan       4.8 m long, 2.75 m wheelbase, 0.7 m wheels (mid-size saloon)
	  SportsCar   4.5 m, 2.65 m wheelbase, 1.2 m tall, wide track (GT coupe)
	  Pickup      5.9 m, 3.65 m wheelbase, 2 m tall (full-size crew cab)
	  Semi        sleeper tractor on 5.5 m wheelbase pulling a 12 m box
	              trailer on a fifth wheel (it articulates)
	  Naked       1.40 m wheelbase, 0.8 m seat, 25 deg rake (roadster)
	  Supermoto   1.48 m wheelbase, 0.9 m seat, long-travel fork
	  Sportbike   1.40 m wheelbase, clip-ons, full fairing
	  Cruiser     1.66 m wheelbase, 0.68 m seat, 32 deg rake, 240 rear tyre
]]

local Vehicles = {}

local rgb = Color3.fromRGB
local rad = math.rad

Vehicles.Order = { "Sedan", "SportsCar", "Pickup", "Semi", "Naked", "Supermoto", "Sportbike", "Cruiser" }
Vehicles.Default = "Sedan"

local CAR_COLORS = { rgb(196, 40, 40), rgb(30, 90, 180), rgb(236, 236, 232), rgb(40, 40, 44), rgb(46, 120, 76), rgb(226, 170, 40) }
local SPORT_COLORS = { rgb(214, 30, 30), rgb(250, 190, 20), rgb(24, 110, 220), rgb(240, 240, 240), rgb(30, 30, 34), rgb(60, 200, 90) }
local TRUCK_COLORS = { rgb(236, 236, 232), rgb(40, 40, 44), rgb(150, 24, 28), rgb(28, 60, 120), rgb(120, 124, 128), rgb(70, 88, 60) }
local SEMI_COLORS = { rgb(200, 30, 30), rgb(236, 236, 232), rgb(28, 64, 150), rgb(30, 30, 34), rgb(230, 150, 20), rgb(40, 110, 60) }
local BIKE_COLORS = { rgb(210, 40, 40), rgb(30, 30, 34), rgb(240, 150, 30), rgb(40, 90, 200), rgb(90, 180, 90) }
local CRUISER_COLORS = { rgb(20, 20, 22), rgb(110, 16, 20), rgb(30, 50, 90), rgb(200, 200, 204), rgb(70, 80, 60) }

Vehicles.Specs = {
	Sedan = {
		name = "Sedan",
		category = "Car",
		kind = "Car",
		description = "Comfortable all-rounder",
		colors = CAR_COLORS,
		tuning = {}, -- Config.Car is the sedan
		sound = "Engine",
		camera = { distance = 19, height = 3, hood = Vector3.new(0, 1.45, -3.6) },
	},
	SportsCar = {
		name = "Sports car",
		category = "Car",
		kind = "Car",
		description = "Low, fast and grippy",
		colors = SPORT_COLORS,
		tuning = {
			TopSpeed = 205,
			Acceleration = 64,
			BrakeDeceleration = 135,
			MaxSteerLow = rad(32),
			MaxSteerHigh = rad(5.5),
			SteerSpeed = 3.6,
			SuspensionLength = 2.2,
			SuspensionFrequency = 2.8,
			SuspensionDamping = 0.62,
			WheelRadius = 1.25,
			ChassisSize = Vector3.new(6.4, 1.8, 14.2),
			HalfTrack = 2.95,
			HalfBase = 4.7,
			Grip = 1.6,
			RearGrip = 1.1,
			StabilityAssist = 1.8,
			Drag = 1.2e-4,
			BodyLength = 16.2,
		},
		sound = "SportsEngine",
		camera = { distance = 16, height = 2.6, hood = Vector3.new(0, 1.05, -3.3) },
	},
	Pickup = {
		name = "Pickup truck",
		category = "Car",
		kind = "Car",
		description = "Tall and relaxed",
		colors = TRUCK_COLORS,
		tuning = {
			TopSpeed = 140,
			Acceleration = 38,
			BrakeDeceleration = 100,
			MaxSteerLow = rad(32),
			MaxSteerHigh = rad(6),
			SteerSpeed = 2.8,
			SuspensionLength = 3.0,
			SuspensionFrequency = 1.9,
			SuspensionDamping = 0.5,
			WheelRadius = 1.45,
			ChassisSize = Vector3.new(6.6, 2.8, 19),
			HalfTrack = 3.15,
			HalfBase = 6.5,
			Grip = 1.2,
			RearGrip = 1.1,
			StabilityAssist = 1.8,
			Drag = 1.9e-4,
			BodyLength = 21,
		},
		sound = "PickupEngine",
		camera = { distance = 21, height = 3.8, hood = Vector3.new(0, 2.25, -4.6) },
	},
	Semi = {
		name = "Tractor-trailer",
		category = "Car",
		kind = "Car",
		description = "Long haul, take it easy",
		colors = SEMI_COLORS,
		tuning = {
			TopSpeed = 110,
			Acceleration = 20,
			BrakeDeceleration = 80,
			CoastDeceleration = 4,
			MaxSteerLow = rad(32),
			MaxSteerHigh = rad(8.5), -- a long wheelbase needs more lock for the same bend
			SteerSpeed = 2.2,
			SteerGrip = 0.6, -- no more than 0.65 g at full lock
			SuspensionLength = 2.8,
			SuspensionFrequency = 1.8,
			SuspensionDamping = 0.6,
			WheelRadius = 1.85,
			ChassisSize = Vector3.new(7, 3, 24),
			HalfTrack = 3.65, -- steer axle
			HalfTrackRear = 3.3, -- centre of the dual tyres
			HalfBase = 9.75,
			Grip = 1.1,
			HandbrakeGrip = 1.1, -- the handbrake only brakes; no drifting a semi
			RearGrip = 1.1,
			StabilityAssist = 2,
			Drag = 1.6e-4,
			BodyLength = 27, -- the tractor unit (the trailer stays built-in)
			-- the trailer, hitched to a fifth wheel on the tractor
			Trailer = {
				FifthWheel = Vector3.new(0, 4.5, 8.8), -- hitch point: ground space of the tractor
				Length = 44, -- box length
				KingpinSetback = 3.2, -- trailer front to kingpin
				AxleDistance = 33.2, -- kingpin to tandem centre
				AxleSpread = 4.4,
				ComDistance = 18, -- kingpin to centre of mass (sets the axle load)
				MassRatio = 1.4, -- trailer mass / tractor mass
				HalfTrack = 3.3,
				WheelRadius = 1.85,
				ChassisSize = Vector3.new(7, 2, 36),
				RollStiffness = 390, -- roll coupling to the tractor (per unit trailer mass)
			},
		},
		sound = "TruckEngine",
		camera = { distance = 74, height = 17, hood = Vector3.new(0, 5.9, -5.6) },
	},
	Naked = {
		name = "Naked bike",
		category = "Bike",
		kind = "Motorcycle",
		description = "Upright roadster",
		colors = BIKE_COLORS,
		tuning = {}, -- Config.Motorcycle is the naked bike
		sound = "MotorcycleEngine",
		camera = { distance = 12, height = 2.4, hood = Vector3.new(0, 3.08, -0.46) },
	},
	Supermoto = {
		name = "Supermoto",
		category = "Bike",
		kind = "Motorcycle",
		description = "Light and flickable",
		colors = { rgb(240, 110, 20), rgb(240, 240, 240), rgb(30, 90, 200), rgb(220, 30, 40), rgb(250, 210, 30) },
		tuning = {
			TopSpeed = 150,
			Acceleration = 54,
			BrakeDeceleration = 125,
			MaxSteerLow = rad(32),
			MaxSteerHigh = rad(5.5),
			SteerSpeed = 3.6,
			SuspensionLength = 2.4,
			SuspensionFrequency = 2.2,
			SuspensionDamping = 0.5,
			WheelRadius = 1.1,
			HalfBase = 2.65,
			Grip = 1.45,
			RearGrip = 1.15,
			LeanMax = rad(48),
			BodyLength = 8,
		},
		sound = "SupermotoEngine",
		camera = { distance = 12, height = 2.8, hood = Vector3.new(0, 3.14, -0.7) },
	},
	Sportbike = {
		name = "Sportbike",
		category = "Bike",
		kind = "Motorcycle",
		description = "Tucked in and very fast",
		colors = BIKE_COLORS,
		tuning = {
			TopSpeed = 195,
			Acceleration = 66,
			BrakeDeceleration = 135,
			MaxSteerLow = rad(24),
			MaxSteerHigh = rad(4),
			SteerSpeed = 3.0,
			SuspensionLength = 1.9,
			SuspensionFrequency = 2.8,
			SuspensionDamping = 0.6,
			WheelRadius = 1.1,
			HalfBase = 2.5,
			Grip = 1.6,
			RearGrip = 1.2,
			Drag = 1.3e-4,
			LeanMax = rad(50),
			BodyLength = 7.3,
		},
		sound = "SportbikeEngine",
		camera = { distance = 12, height = 2.2, hood = Vector3.new(0, 2.4, -1.6) },
	},
	Cruiser = {
		name = "Cruiser",
		category = "Bike",
		kind = "Motorcycle",
		description = "Long, low and laid back",
		colors = CRUISER_COLORS,
		tuning = {
			TopSpeed = 145,
			Acceleration = 40,
			BrakeDeceleration = 100,
			MaxSteerLow = rad(24),
			MaxSteerHigh = rad(4),
			SteerSpeed = 2.4,
			SuspensionLength = 1.9,
			SuspensionFrequency = 2.1,
			SuspensionDamping = 0.55,
			WheelRadius = 1.16,
			HalfBase = 2.975,
			ChassisSize = Vector3.new(3.6, 2.6, 8),
			Grip = 1.35,
			RearGrip = 1.2,
			Drag = 1.9e-4,
			LeanMax = rad(34),
			BodyLength = 8.6,
		},
		sound = "CruiserEngine",
		camera = { distance = 13, height = 2.3, hood = Vector3.new(0, 3.15, 0.52) },
	},
}

-- older names
local ALIASES = { Car = "Sedan", Motorcycle = "Naked" }

function Vehicles.resolve(id: string?): string
	id = id or Vehicles.Default
	id = ALIASES[id] or id
	return Vehicles.Specs[id] and id or Vehicles.Default
end

function Vehicles.get(id: string?)
	local key = Vehicles.resolve(id)
	local spec = Vehicles.Specs[key]
	spec.id = key
	return spec
end

-- The next vehicle in the list (wraps around).
function Vehicles.next(id: string): string
	local key = Vehicles.resolve(id)
	for i, v in Vehicles.Order do
		if v == key then
			return Vehicles.Order[i % #Vehicles.Order + 1]
		end
	end
	return Vehicles.Default
end

return Vehicles
