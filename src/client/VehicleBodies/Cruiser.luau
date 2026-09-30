--[[
	Cruiser: a long, low V-twin (1.66 m wheelbase, 0.68 m seat, 32 degree
	rake, 240 section rear tyre on solid disc wheels). Wide-set chrome fork
	with a big chrome headlight, pull-back bars on a riser, fat tank with a
	chrome console, a 45 degree V-twin with chrome covers, deep valanced
	fenders, a stepped seat, twin shotgun exhausts on the right and
	floorboards far forward, so the rider sits back with feet forward.

	Ground space: y = 0 is the road, front is -Z, axles at z = -2.975 / +2.975.
]]

local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local V = Vector3.new
local rgb = Color3.fromRGB
local rad = math.rad

local CHROME = Kit.ChromeProps

local Cruiser = {
	rake = 32,
	forkLength = 2.82,
	front = { radius = 1.16, width = 0.6, rimRatio = 0.72, rim = C.Chrome, rimProps = CHROME, spokes = 0, disc = -1 },
	rear = { radius = 1.16, width = 0.86, rimRatio = 0.72, rim = C.Chrome, rimProps = CHROME, spokes = 0, disc = 1, sprocket = -1 },
	swingarmPivot = V(0, 1.45, 0.95),
	rider = { seat = V(0, 2.4, 0.85), foot = V(0.75, 1.15, -1.05), hand = V(1.3, 4.25, -0.4), lean = -5 },
}

function Cruiser.build(kits, geo, color, _v)
	local body, steer, arm = kits.body, kits.steer, kits.swingarm
	local head, axis = geo.head, geo.axis
	local back = Vector3.xAxis:Cross(axis)
	local metal = Kit.MetalProps
	local black = rgb(22, 22, 24)
	local chrome = C.Chrome
	local fa = geo.frontAxle

	-- steering: chrome fork, riser, pull-back bars, big headlight, fender
	for _, s in { -1, 1 } do
		steer:tube("Fork", V(s * 0.65, fa.Y, fa.Z), head + axis * 0.2 + V(s * 0.65, 0, 0), 0.36, chrome, CHROME)
		steer:bar("Handlebar", V(s * 0.12, 3.95, head.Z + 0.1), V(s * 1.3, 4.25, -0.4), 0.18, chrome, CHROME)
	end
	steer:oriented("TopClamp", head + axis * 0.08, V(1.7, 0, 0), axis * 0.2, back * 0.6, chrome, CHROME)
	steer:tube("Riser", head + axis * 0.18, V(0, 3.97, head.Z + 0.1), 0.24, chrome, CHROME)
	local lampAt = head - back * 0.72 - axis * 0.25
	steer:cyl("HeadlightBucket", lampAt, -Vector3.zAxis, 0.7, 1.15, chrome, CHROME)
	local lens = steer:cyl("Headlight", lampAt - V(0, 0, 0.37), -Vector3.zAxis, 0.06, 0.95, C.Lamp, Kit.NeonProps)
	steer:beam(lens, Enum.NormalId.Right)
	local R = geo.front.radius
	steer:part("Part", "FenderFront", V(0.82, 0.14, 1.3), CFrame.new(0, fa.Y + R * 0.78, fa.Z - R * 0.78) * CFrame.Angles(rad(-45), 0, 0))
	steer:part("Part", "Fender", V(0.82, 0.14, 1.2), CFrame.new(0, fa.Y + R + 0.2, fa.Z + 0.2) * CFrame.Angles(rad(8), 0, 0))

	-- fat tank with console, stepped seat
	body:span("Tank", V(-0.72, 2.65, -1.15), V(0.72, 3.4, 0.3))
	body:span("Console", V(-0.2, 3.4, -0.9), V(0.2, 3.48, 0.1), chrome, CHROME)
	body:span("Seat", V(-0.62, 2.1, 0.35), V(0.62, 2.4, 1.55), black, { Material = Enum.Material.Leather })
	body:span("Pillion", V(-0.45, 2.3, 1.55), V(0.45, 2.62, 2.4), black, { Material = Enum.Material.Leather })

	-- V-twin: crankcase, two cylinders at 45 degrees, chrome covers
	body:span("Crankcase", V(-0.55, 0.75, -0.75), V(0.55, 1.75, 0.75), rgb(32, 32, 34), metal)
	body:part("Part", "FrontCylinder", V(0.95, 1.1, 0.85), CFrame.new(0, 2.2, -0.5) * CFrame.Angles(rad(-22.5), 0, 0), C.Alloy, metal)
	body:part("Part", "RearCylinder", V(0.9, 1.1, 0.85), CFrame.new(0, 2.2, 0.45) * CFrame.Angles(rad(22.5), 0, 0), C.Alloy, metal)
	body:cyl("AirCleaner", V(0.63, 2.15, -0.05), Vector3.xAxis, 0.18, 0.9, chrome, CHROME)
	body:cyl("PrimaryCover", V(-0.63, 1.15, 0.35), Vector3.xAxis, 0.16, 1.0, chrome, CHROME)
	body:bar("DownTube", V(0, head.Y - 0.2, head.Z + 0.15), V(0, 0.85, -0.85), 0.26, black, metal)

	-- deep rear fender and taillight
	body:part("Part", "RearFender", V(1.0, 0.14, 1.8), CFrame.new(0, 2.5, 2.7) * CFrame.Angles(rad(-4), 0, 0))
	local skirt = CFrame.new(0, 2.05, 3.95) * CFrame.Angles(rad(50), 0, 0)
	body:part("Part", "RearFenderTail", V(1.0, 0.14, 1.2), skirt)
	body:taillight("Taillight", V(0.36, 0.16, 0.1), skirt * CFrame.new(0, 0.1, -0.1))

	-- shotgun exhausts, floorboards far forward
	body:cyl("ExhaustLow", V(1.0, 0.85, 1.6), Vector3.zAxis, 3.6, 0.34, chrome, CHROME)
	body:cyl("ExhaustHigh", V(1.0, 1.3, 1.9), Vector3.zAxis, 3.2, 0.34, chrome, CHROME)
	body:bar("Header", V(0.5, 1.95, -0.95), V(1.0, 1.05, -0.2), 0.26, chrome, CHROME)
	body:pair("Floorboard", V(0.5, 0.95, -1.5), V(1.0, 1.05, -0.6), black)

	-- short swingarm and belt drive
	for _, s in { -1, 1 } do
		arm:bar("Swingarm", V(s * 0.72, 1.45, 0.95), V(s * 0.72, geo.rearAxle.Y, geo.rearAxle.Z), 0.18, black, metal)
	end
	arm:bar("Belt", V(-0.57, 1.55, 0.35), V(-0.57, 1.72, geo.rearAxle.Z), 0.08, black, metal)
end

return Cruiser
