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

	Car.new(config, color, assets, id) builds one.
]]

local Vehicles = {}

local rgb = Color3.fromRGB

Vehicles.Order = { "Sedan", "SportsCar", "Pickup", "Semi", "Naked", "Supermoto", "Sportbike", "Cruiser" }
Vehicles.Default = "Sedan"

local CAR_COLORS = { rgb(196, 40, 40), rgb(30, 90, 180), rgb(236, 236, 232), rgb(40, 40, 44), rgb(46, 120, 76), rgb(226, 170, 40) }
local BIKE_COLORS = { rgb(210, 40, 40), rgb(30, 30, 34), rgb(240, 150, 30), rgb(40, 90, 200), rgb(90, 180, 90) }

Vehicles.Specs = {
	Sedan = { name = "Sedan", category = "Car", kind = "Car", description = "Comfortable all-rounder", colors = CAR_COLORS, tuning = {}, sound = "Engine" },
	SportsCar = { name = "Sports car", category = "Car", kind = "Car", description = "Low, fast and grippy", colors = CAR_COLORS, tuning = {}, sound = "Engine" },
	Pickup = { name = "Pickup truck", category = "Car", kind = "Car", description = "Tall and relaxed", colors = CAR_COLORS, tuning = {}, sound = "Engine" },
	Semi = { name = "Tractor-trailer", category = "Car", kind = "Car", description = "Long haul, take it easy", colors = CAR_COLORS, tuning = {}, sound = "Engine" },
	Naked = { name = "Naked bike", category = "Bike", kind = "Motorcycle", description = "Upright roadster", colors = BIKE_COLORS, tuning = {}, sound = "MotorcycleEngine" },
	Supermoto = { name = "Supermoto", category = "Bike", kind = "Motorcycle", description = "Light and flickable", colors = BIKE_COLORS, tuning = {}, sound = "MotorcycleEngine" },
	Sportbike = { name = "Sportbike", category = "Bike", kind = "Motorcycle", description = "Tucked in and very fast", colors = BIKE_COLORS, tuning = {}, sound = "MotorcycleEngine" },
	Cruiser = { name = "Cruiser", category = "Bike", kind = "Motorcycle", description = "Long, low and laid back", colors = BIKE_COLORS, tuning = {}, sound = "MotorcycleEngine" },
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
