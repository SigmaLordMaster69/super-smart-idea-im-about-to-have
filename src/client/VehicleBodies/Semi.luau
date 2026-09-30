--[[
	Semi: a conventional (long-nose) sleeper tractor pulling a box trailer.

	Tractor: about 7.5 m long on a 5.5 m wheelbase, 2.45 m wide, 4 m tall
	over the roof fairing. Long sloping hood with fenders sweeping back to
	the cab, tall chrome grille, near-upright windshield, a high-roof
	sleeper, aluminium fuel tanks, twin exhaust stacks, the fifth wheel on
	the frame, and dual tyres on a tandem drive axle.

	Trailer: a 12 m dry van (2.6 m wide, 4.1 m tall, floor at 1.26 m), with
	a refrigeration unit on the front, landing gear, rear doors in a frame,
	an underride bar, mud flaps and a tandem axle with dual tyres. It is a
	separate physics body (see Car); this module only draws it.

	Ground space: y = 0 is the road, front is -Z. Tractor axles at z = -9.75
	(steer) and +9.75 (tandem centre, axles 4.7 apart); the trailer is drawn
	in its own space, z = 0 at its centre of mass.
]]

local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local V = Vector3.new
local rgb = Color3.fromRGB

local Semi = {}

-- opaque tinted glass on a painted panel
local TINT = { Material = Enum.Material.Glass, Transparency = 0, Reflectance = 0.3 }
local ALU = { Reflectance = 0.35 }

local function tractor(k, car)
	local cabW, sleeperW = 4.2, 4.3
	local floor = 4.6 -- cab floor
	local cowlY, cabTop, roofTop = 7.6, 11.2, 14.2
	local nose = -12.4
	local cowl, cabFront, cabBack, sleeperBack = -5.2, -4.0, -0.2, 3.8
	local hoodW = 2.7
	local rz = car.wheels[3].z

	-- chrome bumper, hood and grille
	k:span("Bumper", V(-4.2, 2.3, nose - 0.8), V(4.2, 3.7, nose), C.Chrome, Kit.ChromeProps)
	k:span("Hood", V(-hoodW, 3.7, nose), V(hoodW, 6.8, cowl))
	k:wedge("HoodTop", V(0, 6.8, cowl), V(0, cowlY - 6.8, 0), V(0, 0, nose - cowl), hoodW * 2)
	k:span("GrilleFrame", V(-2.45, 3.85, nose - 0.08), V(2.45, 6.65, nose), C.Chrome, Kit.ChromeProps)
	k:span("Grille", V(-2.2, 4.05, nose - 0.11), V(2.2, 6.45, nose - 0.05), C.Trim)
	-- fenders sweep from the headlights back to the cab
	k:pair("Fender", V(hoodW, 4.0, -11.8), V(4.1, 5.6, cowl))
	k:wedgePair("FenderNose", V((hoodW + 4.1) * 0.5, 4.0, -11.8), V(0, 1.6, 0), V(0, 0, -0.6), 4.1 - hoodW)
	for _, s in { -1, 1 } do
		k:headlight("Headlight", V(1.2, 0.6, 0.3), CFrame.new(s * 3.4, 4.75, -12.25), true)
	end

	-- cab: lower body, upper body, raked nose with the windshield, fairing
	k:span("CabLower", V(-cabW, floor, cowl), V(cabW, cowlY, cabBack))
	k:span("CabUpper", V(-cabW, cowlY, cabFront), V(cabW, cabTop, cabBack))
	k:wedge("CabNose", V(0, cowlY, cabFront), V(0, cabTop - cowlY, 0), V(0, 0, cowl - cabFront), cabW * 2)
	-- the windshield glass lies on the nose slope, just proud of it
	local slope = V(0, cabTop - cowlY, cabFront - cowl)
	local function onSlope(t)
		return V(0, cowlY, cowl) + slope * t
	end
	k:panel("Windshield", onSlope(0.08), onSlope(0.95), 7.6, 0.12, C.Glass, TINT, 0.04)
	k:wedge("RoofFairing", V(0, cabTop, cabBack), V(0, roofTop - cabTop, 0), V(0, 0, cabFront - cabBack), cabW * 2)
	k:span("Sleeper", V(-sleeperW, floor, cabBack), V(sleeperW, roofTop, sleeperBack))
	k:pair("DoorWindow", V(cabW - 0.02, 8.0, -3.7), V(cabW + 0.04, 10.8, -0.8), C.Glass, TINT)
	k:pair("Mirror", V(cabW, 8.3, -3.95), V(cabW + 0.45, 10.3, -3.55), C.Trim)
	k:span("MarkerLights", V(-1.6, cabTop + 0.25, cabFront + 0.05), V(1.6, cabTop + 0.45, cabFront + 0.45), C.Amber, Kit.NeonProps)

	-- chassis: frame, fuel tanks, side fairings, fifth wheel
	k:span("Frame", V(-1.7, 3.2, nose + 0.3), V(1.7, 4.3, 14.6), C.Dark)
	for _, s in { -1, 1 } do
		k:cyl("FuelTank", V(s * 3.75, 2.8, -3.4), Vector3.zAxis, 4.4, 1.9, C.Alloy, ALU)
	end
	k:span("SideFairing", V(-cabW, 2.2, -1.2), V(cabW, floor, 5.3))
	k:span("FifthWheel", V(-2.3, 4.3, 7.3), V(2.3, 4.5, 11.0), C.Trim)
	-- tandem: quarter fenders over the duals and mud flaps behind
	k:pair("RearFender", V(2.2, 4.4, rz - 3.6), V(4.4, 4.55, rz + 3.55), C.Trim)
	k:pair("MudFlap", V(2.3, 0.8, rz + 4.35), V(4.3, 3.9, rz + 4.45), C.Trim)
	-- exhaust stacks behind the sleeper
	for _, s in { -1, 1 } do
		k:cyl("Stack", V(s * 4.55, 10.25, sleeperBack + 0.35), Vector3.yAxis, 10.5, 0.55, C.Chrome, Kit.ChromeProps)
	end

	local front = function(w)
		return w.front
	end
	local rear = function(w)
		return not w.front
	end
	local spread = 4.7
	k:wheels(car.wheels, car.attachY, { width = 1.0, rim = C.Alloy, rimRatio = 0.6, hub = rgb(60, 60, 64), hubRatio = 0.5, rimProps = ALU }, front)
	k:wheels(car.wheels, car.attachY, { width = 2.0, dual = true, rim = C.Alloy, rimRatio = 0.6, hub = rgb(60, 60, 64), hubRatio = 0.45, rimProps = ALU, axles = { -spread * 0.5, spread * 0.5 } }, rear)
end

local function trailer(car, color)
	local tr = car.trailer
	local tc = tr.config
	local white = rgb(234, 234, 230)
	local k = Kit.new(car, tr.chassis, tr.groundY, white, tr.model)
	local front = -tc.ComDistance - tc.KingpinSetback
	local back = front + tc.Length
	local floorY, roofY = tc.FifthWheel.Y, 14.6
	local halfW = 4.6

	k:span("Box", V(-halfW, floorY + 0.7, front), V(halfW, roofY, back))
	k:span("FloorRail", V(-halfW - 0.02, floorY, front + 0.02), V(halfW + 0.02, floorY + 0.7, back - 0.02), C.Dark)
	k:span("Stripe", V(-halfW - 0.02, 9.0, front + 0.6), V(halfW + 0.02, 9.8, back - 0.6), color)
	k:span("ReeferUnit", V(-3.2, 10.5, front - 0.7), V(3.2, 13.8, front), C.Dark)
	-- rear doors in a frame
	k:span("RearFrame", V(-halfW - 0.02, floorY, back), V(halfW + 0.02, roofY + 0.02, back + 0.15), C.Dark)
	k:span("RearDoors", V(-4.35, floorY + 0.3, back + 0.15), V(4.35, roofY - 0.25, back + 0.2))
	k:span("DoorSeam", V(-0.04, floorY + 0.3, back + 0.2), V(0.04, roofY - 0.25, back + 0.22), C.Dark)
	for _, s in { -1, 1 } do
		k:taillight("Taillight", V(0.9, 0.7, 0.08), CFrame.new(s * 3.95, floorY + 0.55, back + 0.23))
	end
	k:span("Underride", V(-4.0, 1.6, back - 0.4), V(4.0, 2.2, back - 0.1), C.Dark)
	-- landing gear (legs up while driving)
	local legZ = -tc.ComDistance + 8.8
	k:pair("LandingGear", V(2.8, 1.5, legZ - 0.25), V(3.2, floorY, legZ + 0.25), C.Dark)
	-- tandem: mud flaps behind the duals
	local axle = tr.axleZ
	local spread = tc.AxleSpread
	k:pair("MudFlap", V(2.3, 0.8, axle + spread * 0.5 + 2.4), V(4.4, 3.9, axle + spread * 0.5 + 2.5), C.Trim)
	k:wheels(tr.wheels, tr.attachY, { width = 2.0, dual = true, rim = C.Alloy, rimRatio = 0.6, hub = rgb(60, 60, 64), hubRatio = 0.45, rimProps = ALU, axles = { -spread * 0.5, spread * 0.5 } })
	return k.count
end

function Semi.build(k, car)
	tractor(k, car)
	car.trailerPartCount = trailer(car, k.color)
end

return Semi
