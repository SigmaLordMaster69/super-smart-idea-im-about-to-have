--[[
	Sedan: a mid-size saloon (about 4.8 m long, 1.85 m wide, 1.45 m tall,
	2.75 m wheelbase). Three-box profile: sloping hood, a greenhouse with a
	raked windshield (about 24 degrees), thin A-pillars, black B-pillars and
	wide C-pillars, and a short trunk. Square-cut wheel arches with
	chamfered corners, a dark wheel-well box behind them, wrap-over
	headlights, grille, bumpers, mirrors and six-spoke alloys.

	Ground space: y = 0 is the road, front is -Z, axles at z = -4.9 / +4.9.
]]

local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local V = Vector3.new

local Sedan = {}

function Sedan.build(k, car)
	-- key lines (studs)
	local halfW = 3.25 -- body side
	local sill = 0.6 -- bottom of the doors
	local arch = 2.75 -- top of the wheel arches, bottom of the shoulder
	local belt = 3.5 -- bottom of the side windows
	local glassTop = 4.95
	local roofTop = 5.15
	local glassW = 2.95 -- greenhouse half width (tumblehome step at the belt)
	local nose, tail = -7.9, 8.4 -- body ends (bumpers stick out further)
	local cowl, roofFront, roofRear, deck = -3.0, 0.8, 4.8, 7.0
	local fz, rz = car.wheels[1].z, car.wheels[3].z
	local aw = 1.6 -- arch half width

	-- lower body: centre section between the arches, and the two ends
	k:span("Doors", V(-halfW, sill, fz + aw), V(halfW, arch, rz - aw))
	k:span("Sills", V(-halfW - 0.05, sill - 0.05, fz + aw + 0.05), V(halfW + 0.05, sill + 0.35, rz - aw - 0.05), C.Trim)
	k:span("FrontEnd", V(-halfW, 1.05, nose), V(halfW, arch, fz - aw))
	k:span("RearEnd", V(-halfW, 1.05, rz + aw), V(halfW, arch, tail))
	-- shoulder under the windows, hood and trunk
	k:pair("Shoulder", V(glassW, arch, cowl), V(halfW, belt, deck))
	k:wedge("Hood", V(0, arch, cowl), V(0, belt - arch, 0), V(0, 0, nose - cowl), halfW * 2)
	k:span("Trunk", V(-halfW, arch, deck), V(halfW, belt + 0.1, tail - 0.45))
	k:wedge("TrunkLip", V(0, arch, tail - 0.45), V(0, belt + 0.1 - arch, 0), V(0, 0, 0.45), halfW * 2)
	-- arch corners (full width: the lips at the sides, hidden in the middle)
	for _, z in { fz, rz } do
		k:wedge("ArchFront", V(0, arch, z - aw), V(0, -0.7, 0), V(0, 0, 0.7), halfW * 2)
		k:wedge("ArchRear", V(0, arch, z + aw), V(0, -0.7, 0), V(0, 0, -0.7), halfW * 2)
	end
	-- dark box behind the arches: wheel wells and underbody
	k:span("WheelWells", V(-3.0, 0.65, nose + 0.5), V(3.0, 2.7, tail - 0.5), C.Interior)

	-- bumpers: body colour, rounded front corners, black intake
	k:span("FrontBumper", V(-2.55, 0.6, -8.3), V(2.55, 1.95, nose + 0.4))
	k:wedgePair("BumperCorner", V(2.55, 1.275, nose + 0.4), V(0, 0, -0.8), V(0.6, 0, 0), 1.35)
	k:span("Intake", V(-2.2, 0.72, -8.34), V(2.2, 1.3, -8.2), C.Trim)
	k:span("RearBumper", V(-3.1, 0.6, tail - 0.6), V(3.1, 1.9, 8.8))

	-- greenhouse: windshield, side glass, rear window, roof with rounded edges
	local glass = C.Glass
	local gp = Kit.GlassProps
	local rise = glassTop - belt
	k:span("SideGlass", V(-glassW, belt, roofFront), V(glassW, glassTop, roofRear), glass, gp)
	k:wedge("Windshield", V(0, belt, roofFront), V(0, rise, 0), V(0, 0, cowl - roofFront), glassW * 2, glass, gp)
	k:wedge("RearWindow", V(0, belt, roofRear), V(0, rise, 0), V(0, 0, deck - roofRear), glassW * 2, glass, gp)
	k:span("Roof", V(-2.75, glassTop, roofFront - 0.2), V(2.75, roofTop, roofRear + 0.2))
	k:wedgePair("RoofEdge", V(2.75, glassTop, (roofFront + roofRear) * 0.5), V(0, roofTop - glassTop, 0), V(0.2, 0, 0), roofRear - roofFront + 0.4)
	-- pillars sit just outside the glass
	for _, s in { -1, 1 } do
		local x = s * (glassW - 0.1)
		-- A-pillar along the windshield edge
		local a, b = V(x, belt + 0.02, cowl + 0.05), V(x, glassTop, roofFront)
		local along = b - a
		local normal = along.Unit:Cross(Vector3.xAxis)
		if normal.Y < 0 then
			normal = -normal
		end
		k:oriented("APillar", (a + b) * 0.5 + normal * 0.04, V(0.34, 0, 0), normal * 0.22, along)
		-- B-pillar (black) and C-pillar (body colour)
		k:span("BPillar", V(s * (glassW + 0.01), belt, 1.9), V(s * (glassW + 0.06), glassTop, 2.3), C.Trim)
		k:span("CPillar", V(s * (glassW + 0.01), belt, 3.7), V(s * (glassW + 0.13), glassTop, roofRear))
		k:wedge("CPillarRake", V(s * (glassW + 0.07), belt, roofRear), V(0, rise, 0), V(0, 0, deck - roofRear), 0.12)
	end
	-- the dark cabin behind the glass: dashboard, floor and parcel shelf
	-- level between the shoulders, and the seat backs
	k:span("Cabin", V(-glassW + 0.05, arch, cowl), V(glassW - 0.05, belt + 0.12, deck), C.Interior)
	k:span("Seats", V(-2.6, belt + 0.12, roofFront + 0.1), V(2.6, 4.25, roofRear - 0.2), C.Interior)

	-- chrome strip along the bottom of the side windows
	k:span("BeltTrim", V(-glassW - 0.1, belt + 0.03, cowl + 0.3), V(glassW + 0.1, belt + 0.09, deck - 0.3), C.Chrome, Kit.ChromeProps)

	-- mirrors on the doors
	k:wedgePair("Mirror", V(halfW + 0.25, 3.3, -2.2), V(0, 0.5, 0), V(0, 0, -0.55), 0.5)

	-- lights, grille and plates
	for _, s in { -1, 1 } do
		k:headlight("Headlight", V(1.6, 0.42, 0.1), CFrame.new(s * 2.25, 2.4, nose - 0.04), true)
		k:taillight("Taillight", V(1.9, 0.5, 0.1), CFrame.new(s * 2.1, 2.3, tail + 0.03))
	end
	k:span("Grille", V(-1.2, 1.98, nose - 0.08), V(1.2, 2.62, nose + 0.02), C.Trim)
	k:span("Plate", V(-0.9, 1.95, tail - 0.02), V(0.9, 2.45, tail + 0.05), C.Plate)

	k:wheels(car.wheels, car.attachY, { width = 0.85, rim = C.Alloy, rimRatio = 0.68, spokes = 3, spokeWidth = 0.26 })
end

return Sedan
