--[[
	Pickup: a full-size crew-cab pickup (about 5.9 m long, 2 m wide, 2 m
	tall, 3.65 m wheelbase, 1.7 m bed). Tall flat hood with a raised
	centre, big chrome-framed grille, upright windshield, four-door cab with
	black pillars, a separate bed with tailgate, black fender flares over
	all-terrain tyres, step bars and a chrome bumper.

	Ground space: y = 0 is the road, front is -Z, axles at z = -6.5 / +6.5.
]]

local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local V = Vector3.new
local rgb = Color3.fromRGB

local Pickup = {}

function Pickup.build(k, car)
	local halfW = 3.45
	local sill = 1.05
	local arch = 3.3 -- top of the arch openings
	local hoodY = 4.5 -- fender and hood line at the front
	local belt = 4.9
	local glassTop, roofTop = 6.9, 7.1
	local glassW = 3.25
	local nose, tail = -10.0, 10.7
	local cowl, roofFront, cabBack = -3.6, -1.2, 4.5
	local bedFront, bedTop, bedFloor = 4.7, 4.8, 3.2
	local fz, rz = car.wheels[1].z, car.wheels[3].z
	local aw = 1.85

	-- cab and front end
	k:span("Doors", V(-halfW, sill, fz + aw), V(halfW, belt, cabBack))
	k:span("FrontEnd", V(-halfW, 1.2, nose), V(halfW, arch, fz - aw))
	k:span("Fenders", V(-halfW, arch, nose), V(halfW, hoodY, fz + aw))
	k:wedge("Hood", V(0, hoodY, cowl), V(0, belt - hoodY, 0), V(0, 0, nose + 0.15 - cowl), 4.8)
	-- bed: sides, floor, tailgate, and the body under it behind the wheels
	k:pair("BedSide", V(3.0, arch, bedFront), V(halfW, bedTop, tail))
	k:span("RearEnd", V(-halfW, 1.2, rz + aw), V(halfW, arch, tail))
	k:span("Tailgate", V(-3.0, 2.1, tail - 0.25), V(3.0, bedTop - 0.02, tail + 0.03))
	-- arch corners and black flares
	for _, z in { fz, rz } do
		k:wedge("ArchFront", V(0, arch, z - aw), V(0, -0.8, 0), V(0, 0, 0.8), halfW * 2)
		k:wedge("ArchRear", V(0, arch, z + aw), V(0, -0.8, 0), V(0, 0, -0.8), halfW * 2)
		k:pair("Flare", V(halfW - 0.02, arch - 0.15, z - aw - 0.15), V(halfW + 0.18, arch + 0.15, z + aw + 0.15), C.Trim)
	end
	-- dark underbody; its top is the bed floor (a black liner)
	k:span("Underbody", V(-3.2, 1.1, nose + 0.6), V(3.2, bedFloor, tail - 0.26), C.Interior)
	k:span("StepBars", V(-halfW - 0.4, 1.0, fz + aw + 0.2), V(halfW + 0.4, 1.2, rz - aw - 0.2), C.Trim)

	-- greenhouse: upright windshield, crew cab glass, back wall with window
	local glass, gp = C.Glass, Kit.GlassProps
	local rise = glassTop - belt
	k:span("Dash", V(-glassW + 0.05, belt - 0.05, cowl + 0.1), V(glassW - 0.05, belt + 0.1, cabBack - 0.3), C.Interior)
	k:span("Seats", V(-2.9, belt + 0.1, -0.4), V(2.9, 5.85, 3.8), C.Interior)
	k:span("SideGlass", V(-glassW, belt, roofFront), V(glassW, glassTop, cabBack - 0.2), glass, gp)
	k:wedge("Windshield", V(0, belt, roofFront), V(0, rise, 0), V(0, 0, cowl - roofFront), glassW * 2, glass, gp)
	k:span("BackWall", V(-glassW, belt, cabBack - 0.2), V(glassW, glassTop, cabBack))
	k:span("RearWindow", V(-2.2, 5.3, cabBack - 0.02), V(2.2, 6.5, cabBack + 0.04), glass, { Material = Enum.Material.Glass, Transparency = 0, Reflectance = 0.3 })
	k:span("Roof", V(-3.05, glassTop, roofFront - 0.15), V(3.05, roofTop, cabBack))
	k:wedgePair("RoofEdge", V(3.05, glassTop, (roofFront - 0.15 + cabBack) * 0.5), V(0, roofTop - glassTop, 0), V(0.2, 0, 0), cabBack - roofFront + 0.15)
	for _, s in { -1, 1 } do
		local a, b = V(s * (glassW - 0.1), belt + 0.02, cowl + 0.05), V(s * (glassW - 0.1), glassTop, roofFront)
		local along = b - a
		local normal = along.Unit:Cross(Vector3.xAxis)
		if normal.Y < 0 then
			normal = -normal
		end
		k:oriented("APillar", (a + b) * 0.5 + normal * 0.04, V(0.34, 0, 0), normal * 0.22, along, C.Trim)
		k:span("BPillar", V(s * (glassW + 0.01), belt, 1.25), V(s * (glassW + 0.07), glassTop, 1.75), C.Trim)
		k:span("CPillar", V(s * (glassW + 0.01), belt, 3.7), V(s * (glassW + 0.07), glassTop, cabBack - 0.2), C.Trim)
	end
	k:pair("Mirror", V(halfW, belt, -3.2), V(halfW + 0.65, belt + 0.8, -2.75), C.Trim)

	-- front: chrome-framed grille, headlights, bumper
	k:span("Grille", V(-2.3, 2.6, nose - 0.06), V(2.3, 4.25, nose + 0.04), C.Trim)
	k:span("GrilleFrame", V(-2.45, 4.2, nose - 0.1), V(2.45, 4.45, nose), C.Chrome, Kit.ChromeProps)
	k:span("GrilleBar", V(-2.45, 3.3, nose - 0.1), V(2.45, 3.5, nose), C.Chrome, Kit.ChromeProps)
	for _, s in { -1, 1 } do
		k:headlight("Headlight", V(0.95, 0.7, 0.1), CFrame.new(s * 2.93, 3.95, nose - 0.04), true)
		k:taillight("Taillight", V(0.35, 1.3, 0.08), CFrame.new(s * 3.22, 4.0, tail + 0.03))
	end
	k:span("FrontBumper", V(-3.5, 1.15, nose - 0.4), V(3.5, 2.5, nose + 0.2), C.Chrome, Kit.ChromeProps)
	k:span("RearBumper", V(-3.5, 1.3, tail - 0.1), V(3.5, 2.1, tail + 0.35), C.Chrome, Kit.ChromeProps)

	k:wheels(car.wheels, car.attachY, { width = 1.05, rim = rgb(96, 98, 104), rimRatio = 0.62, spokes = 3, spokeWidth = 0.34 })
end

return Pickup
