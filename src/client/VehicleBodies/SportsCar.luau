--[[
	SportsCar: a front-engined GT coupe (about 4.5 m long, 2 m wide across
	the rear haunches, 1.2 m tall, 2.65 m wheelbase). Long hood between
	raised front fenders, a 20 degree windshield, cab set well back, a
	fastback roof with body-coloured sail panels, wide rear haunches, a
	rear wing on two stands, splitter, diffuser and a light bar across the
	tail. Low-profile tyres on slim six-spoke wheels.

	Ground space: y = 0 is the road, front is -Z, axles at z = -4.7 / +4.7.
]]

local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local V = Vector3.new
local rgb = Color3.fromRGB

local SportsCar = {}

function SportsCar.build(k, car)
	local halfW = 3.45 -- front fenders and doors
	local haunchW = 3.6 -- rear fenders
	local sill = 0.45
	local arch = 2.6
	local belt = 2.95
	local glassTop, roofTop = 4.15, 4.3
	local glassW = 2.45
	local nose, tail = -8.0, 8.1
	local cowl, roofFront, roofRear, deck = -1.9, 1.4, 3.3, 7.0
	local hoodFront = 1.9 -- hood height at the nose
	local fz, rz = car.wheels[1].z, car.wheels[3].z
	local aw = 1.5
	local carbon = rgb(24, 24, 26)

	-- lower body
	k:span("Doors", V(-halfW, sill, fz + aw), V(halfW, arch, rz - aw))
	k:span("SideSkirts", V(-halfW - 0.05, sill - 0.05, fz + aw + 0.05), V(halfW + 0.05, sill + 0.3, rz - aw - 0.05), C.Trim)
	k:span("FrontEnd", V(-halfW, 0.5, nose), V(halfW, hoodFront, fz - aw))
	k:span("RearEnd", V(-haunchW, 0.8, rz + aw), V(haunchW, arch, tail))
	for _, z in { fz, rz } do
		local w = z < 0 and halfW or haunchW
		k:wedge("ArchFront", V(0, arch, z - aw), V(0, -0.6, 0), V(0, 0, 0.6), w * 2)
		k:wedge("ArchRear", V(0, arch, z + aw), V(0, -0.6, 0), V(0, 0, -0.6), w * 2)
	end
	k:span("WheelWells", V(-3.1, 0.55, nose + 0.4), V(3.1, hoodFront - 0.05, tail - 0.5), C.Interior)

	-- hood between raised front fenders
	local hoodW = 2.25
	k:wedge("Hood", V(0, hoodFront, cowl), V(0, belt - hoodFront, 0), V(0, 0, nose - cowl), hoodW * 2)
	k:pair("FenderTop", V(hoodW, arch, fz - aw), V(halfW, 2.9, cowl))
	k:wedgePair("FenderFront", V((hoodW + halfW) * 0.5, hoodFront, fz - aw), V(0, 2.9 - hoodFront, 0), V(0, 0, nose - (fz - aw)), halfW - hoodW)
	-- shoulders along the doors, wide haunches over the rear wheels
	k:pair("Shoulder", V(glassW, arch, cowl), V(halfW, belt, rz - aw))
	k:pair("Haunch", V(glassW, arch, rz - aw), V(haunchW, 3.15, tail))
	k:span("TailDeck", V(-glassW, arch, deck), V(glassW, 3.0, tail))

	-- cabin behind the glass
	k:span("Cabin", V(-glassW + 0.05, hoodFront - 0.05, cowl), V(glassW - 0.05, belt + 0.02, deck), C.Interior)
	k:span("Seats", V(-2.2, belt + 0.02, 1.0), V(2.2, 3.75, 3.2), C.Interior)

	-- greenhouse: raked windshield, frameless side glass, fastback
	local glass, gp = C.Glass, Kit.GlassProps
	local rise = glassTop - belt
	k:span("SideGlass", V(-glassW, belt, roofFront), V(glassW, glassTop, roofRear), glass, gp)
	k:wedge("Windshield", V(0, belt, roofFront), V(0, rise, 0), V(0, 0, cowl - roofFront), glassW * 2, glass, gp)
	k:wedge("Fastback", V(0, belt, roofRear), V(0, rise, 0), V(0, 0, deck - roofRear), glassW * 2, glass, gp)
	k:span("Roof", V(-2.25, glassTop, roofFront - 0.2), V(2.25, roofTop, roofRear + 0.2))
	k:wedgePair("RoofEdge", V(2.25, glassTop, (roofFront + roofRear) * 0.5), V(0, roofTop - glassTop, 0), V(0.2, 0, 0), roofRear - roofFront + 0.4)
	for _, s in { -1, 1 } do
		local a, b = V(s * (glassW - 0.1), belt + 0.02, cowl + 0.05), V(s * (glassW - 0.1), glassTop, roofFront)
		local along = b - a
		local normal = along.Unit:Cross(Vector3.xAxis)
		if normal.Y < 0 then
			normal = -normal
		end
		k:oriented("APillar", (a + b) * 0.5 + normal * 0.04, V(0.3, 0, 0), normal * 0.2, along, carbon)
		-- sail panel beside the fastback glass
		k:wedge("Sail", V(s * (glassW + 0.09), belt, roofRear), V(0, rise, 0), V(0, 0, deck - roofRear), 0.12)
	end

	-- rear wing on two stands
	for _, s in { -1, 1 } do
		k:span("WingStand", V(s * 1.4, 3.0, 7.7), V(s * 1.6, 3.55, 8.0), carbon)
	end
	k:span("Wing", V(-2.9, 3.55, 7.35), V(2.9, 3.68, 8.25), carbon)

	-- front: splitter, intake, slim headlights
	k:span("Splitter", V(-3.3, 0.35, -8.15), V(3.3, 0.5, -6.9), carbon)
	k:span("Intake", V(-1.75, 0.7, nose - 0.04), V(1.75, 1.4, nose + 0.04), C.Trim)
	for _, s in { -1, 1 } do
		k:headlight("Headlight", V(1.4, 0.3, 0.1), CFrame.new(s * 2.55, 1.6, nose - 0.04), true)
	end
	-- rear: light bar, diffuser, centre exhaust
	k:taillight("Taillight", V(6.6, 0.22, 0.1), CFrame.new(0, 2.75, tail + 0.03))
	k:span("Diffuser", V(-3.2, 0.4, 7.5), V(3.2, 0.95, 8.3), carbon)
	k:cyl("Exhaust", V(0, 0.72, 8.35), Vector3.zAxis, 0.3, 0.55, C.Chrome, Kit.ChromeProps)

	k:wedgePair("Mirror", V(halfW + 0.25, belt, -1.2), V(0, 0.4, 0), V(0, 0, -0.5), 0.5)

	k:wheels(car.wheels, car.attachY, { width = 1.0, rim = rgb(70, 72, 78), rimRatio = 0.72, spokes = 3, spokeWidth = 0.2, rimProps = { Reflectance = 0.2 } })
end

return SportsCar
