--[[
	Naked: an upright roadster (1.40 m wheelbase, 0.8 m seat, 25 degree
	rake, 17 inch wheels). Exposed parallel-twin engine leaning forward
	with the radiator in front of it, twin frame spars, a sculpted tank with
	side scoops, round headlight on the fork, wide flat bar, short upswept
	tail, underbelly exhaust and a red rear shock.

	Ground space: y = 0 is the road, front is -Z, axles at z = -2.5 / +2.5.
	Motorcycle adds the fork rig, wheels, swingarm rig and rider.
]]

local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local V = Vector3.new
local rgb = Color3.fromRGB
local rad = math.rad

local Naked = {
	rake = 25,
	forkLength = 2.62, -- axle to top clamp, along the steering axis
	front = { radius = 1.08, width = 0.55, rimRatio = 0.72, rim = rgb(30, 30, 32), spokes = 3, spokeWidth = 0.14, disc = -1 },
	rear = { radius = 1.12, width = 0.8, rimRatio = 0.7, rim = rgb(30, 30, 32), spokes = 3, spokeWidth = 0.16, disc = 1, sprocket = -1 },
	swingarmPivot = V(0, 1.65, 0.55),
	-- where the rider sits, puts their feet and holds the bar; torso lean (degrees)
	rider = { seat = V(0, 2.85, 0.75), foot = V(0.62, 1.35, 0.35), hand = V(1.2, 3.95, -1.04), lean = 15 },
}

function Naked.build(kits, geo, color, _v)
	local body, steer, arm = kits.body, kits.steer, kits.swingarm
	local head, axis = geo.head, geo.axis
	local back = Vector3.xAxis:Cross(axis) -- across the steering axis, pointing back
	local metal = Kit.MetalProps
	local dark = rgb(36, 36, 40)
	local gunmetal = rgb(62, 64, 70)
	local silver = rgb(160, 162, 166)
	local fa = geo.frontAxle

	-- steering: fork, clamp, bar, round headlight, front fender
	for _, s in { -1, 1 } do
		steer:tube("Fork", V(s * 0.7, fa.Y, fa.Z), head + axis * 0.3 + V(s * 0.7, 0, 0), 0.28, silver, metal)
	end
	steer:oriented("TopClamp", head + axis * 0.12, V(1.6, 0, 0), axis * 0.18, back * 0.55, dark, metal)
	steer:cyl("Handlebar", V(0, 3.95, head.Z + 0.35), Vector3.xAxis, 2.6, 0.2, dark, metal)
	local lampAt = head - back * 0.62 - axis * 0.4
	steer:cyl("HeadlightBucket", lampAt, -Vector3.zAxis, 0.5, 0.95, dark)
	local lens = steer:cyl("Headlight", lampAt - V(0, 0, 0.27), -Vector3.zAxis, 0.06, 0.74, C.Lamp, Kit.NeonProps)
	steer:beam(lens, Enum.NormalId.Right)
	steer:part("Part", "FrontFender", V(0.62, 0.08, 1.3), CFrame.new(0, fa.Y + geo.front.radius + 0.22, fa.Z - 0.05) * CFrame.Angles(rad(-8), 0, 0))

	-- tank with side scoops, seat and upswept tail
	body:span("Tank", V(-0.7, 2.75, -0.95), V(0.7, 3.5, 0.25))
	body:wedge("TankFront", V(0, 2.75, -0.95), V(0, 0.75, 0), V(0, 0, -0.45), 1.4)
	body:wedgePair("Scoop", V(0.75, 3.1, -0.6), V(0, -1.0, 0), V(0, 0, -0.9), 0.1)
	body:span("Seat", V(-0.55, 2.62, 0.2), V(0.55, 2.85, 1.95), rgb(24, 24, 26))
	local tail = CFrame.new(0, 2.95, 2.55) * CFrame.Angles(rad(-12), 0, 0)
	body:part("Part", "Tail", V(0.9, 0.4, 1.4), tail)
	body:taillight("Taillight", V(0.5, 0.16, 0.08), tail * CFrame.new(0, 0, 0.74))

	-- exposed parallel twin: crankcase, cylinders leaning forward, cam cover
	body:span("Crankcase", V(-0.6, 0.78, -0.95), V(0.6, 1.75, 0.55), gunmetal, metal)
	local cyl = CFrame.new(0, 2.05, -0.72) * CFrame.Angles(rad(-20), 0, 0)
	body:part("Part", "Cylinders", V(1.05, 0.9, 0.72), cyl, dark, metal)
	body:part("Part", "CamCover", V(0.98, 0.22, 0.66), cyl * CFrame.new(0, 0.55, 0), silver, metal)
	body:span("Radiator", V(-0.55, 1.9, -1.4), V(0.55, 2.75, -1.28), C.Trim)
	for _, s in { -1, 1 } do
		body:bar("Frame", V(s * 0.5, head.Y - 0.15, head.Z + 0.25), V(s * 0.62, 1.95, 0.55), 0.22, gunmetal, metal)
	end
	body:bar("Header", V(0.32, 1.8, -1.12), V(0.3, 0.72, -0.55), 0.2, silver, metal)
	body:cyl("Muffler", V(0.25, 0.62, 0.3), Vector3.zAxis, 1.2, 0.5, dark, metal)
	body:tube("Shock", V(0, 1.75, 0.85), V(0, 2.55, 1.35), 0.28, rgb(210, 50, 40))
	body:bar("Footpegs", V(-0.75, 1.35, 0.35), V(0.75, 1.35, 0.35), 0.12, dark, metal)

	-- swingarm (moves with the rear wheel) and chain
	for _, s in { -1, 1 } do
		arm:bar("Swingarm", V(s * 0.82, 1.65, 0.55), V(s * 0.82, geo.rearAxle.Y, geo.rearAxle.Z), 0.22, gunmetal, metal)
	end
	arm:bar("Chain", V(-0.645, 1.55, 0.3), V(-0.645, 1.65, geo.rearAxle.Z), 0.08, dark, metal)
end

return Naked
