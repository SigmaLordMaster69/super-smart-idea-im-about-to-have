--[[
	Supermoto: a tall, thin single (1.48 m wheelbase, 0.9 m seat, 26.5
	degree rake, long-travel fork, 17 inch wheels). High front fender under
	the fork clamps, a white number plate with a small headlight on the
	front, big radiator shrouds, a long flat seat running onto the tank,
	white side number boards, an upswept rear fender, high silencer, trellis
	frame, wire wheels with knobbly tyres and a wide flat bar.

	Ground space: y = 0 is the road, front is -Z, axles at z = -2.65 / +2.65.
]]

local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local V = Vector3.new
local rgb = Color3.fromRGB
local rad = math.rad

local SPOKES = rgb(196, 198, 202)

local Supermoto = {
	rake = 26.5,
	forkLength = 3.3,
	front = { radius = 1.1, width = 0.5, rimRatio = 0.72, rim = rgb(22, 22, 24), spokes = 3, spokeWidth = 0.06, spokeColor = SPOKES, knobby = true, disc = -1 },
	rear = { radius = 1.1, width = 0.72, rimRatio = 0.72, rim = rgb(22, 22, 24), spokes = 3, spokeWidth = 0.06, spokeColor = SPOKES, knobby = true, disc = 1, sprocket = -1 },
	swingarmPivot = V(0, 1.9, 0.45),
	rider = { seat = V(0, 3.25, 0.2), foot = V(0.65, 1.55, 0.3), hand = V(1.35, 4.4, -0.88), lean = 8 },
}

function Supermoto.build(kits, geo, color, _v)
	local body, steer, arm = kits.body, kits.steer, kits.swingarm
	local head, axis = geo.head, geo.axis
	local back = Vector3.xAxis:Cross(axis)
	local metal = Kit.MetalProps
	local dark = rgb(34, 34, 38)
	local white = rgb(240, 240, 236)
	local frameColor = rgb(240, 110, 20)
	local silver = rgb(170, 172, 176)
	local fa = geo.frontAxle

	-- steering: long fork, clamp, wide bar, high fender, number plate + lamp
	for _, s in { -1, 1 } do
		steer:tube("Fork", V(s * 0.68, fa.Y, fa.Z), head + axis * 0.3 + V(s * 0.68, 0, 0), 0.3, silver, metal)
	end
	steer:oriented("TopClamp", head + axis * 0.12, V(1.6, 0, 0), axis * 0.18, back * 0.5, dark, metal)
	steer:cyl("Handlebar", V(0, 4.4, head.Z + 0.3), Vector3.xAxis, 2.9, 0.18, dark, metal)
	steer:part("Part", "FrontFender", V(0.7, 0.1, 2.2), CFrame.new(0, head.Y - 0.85, head.Z - 0.55) * CFrame.Angles(rad(-10), 0, 0), white)
	local plate = head - back * 0.5 - axis * 0.55
	steer:oriented("NumberPlate", plate, V(1.0, 0, 0), axis * 1.1, back * 0.08, white)
	local lens = steer:cyl("Headlight", plate - back * 0.1 - axis * 0.2, -Vector3.zAxis, 0.08, 0.42, C.Lamp, Kit.NeonProps)
	steer:beam(lens, Enum.NormalId.Right)

	-- radiator shrouds, tank, long flat seat, side boards, rear fender
	body:wedgePair("Shroud", V(0.62, 3.3, -0.25), V(0, -1.3, 0), V(0, 0, -1.25), 0.12)
	body:span("Tank", V(-0.56, 2.7, -1.0), V(0.56, 3.18, -0.25))
	body:span("Seat", V(-0.42, 3.05, -0.6), V(0.42, 3.25, 2.4), rgb(24, 24, 26))
	body:span("Radiator", V(-0.5, 2.1, -1.1), V(0.5, 3.1, -0.95), C.Trim)
	body:pair("SideBoard", V(0.44, 2.35, 1.1), V(0.52, 3.05, 2.3), white)
	local fender = CFrame.new(0, 3.2, 3.05) * CFrame.Angles(rad(-15), 0, 0)
	body:part("Part", "RearFender", V(0.55, 0.1, 1.6), fender, white)
	body:taillight("Taillight", V(0.3, 0.14, 0.08), fender * CFrame.new(0, 0.1, 0.72))

	-- single-cylinder engine in an orange trellis frame
	body:span("Crankcase", V(-0.48, 0.95, -0.85), V(0.48, 1.95, 0.45), rgb(44, 44, 48), metal)
	body:part("Part", "Cylinder", V(0.72, 0.85, 0.72), CFrame.new(0, 2.35, -0.45) * CFrame.Angles(rad(-10), 0, 0), silver, metal)
	for _, s in { -1, 1 } do
		body:bar("Frame", V(s * 0.35, head.Y - 0.25, head.Z + 0.25), V(s * 0.45, 2.0, 0.4), 0.18, frameColor, metal)
	end
	body:cyl("Silencer", V(0.78, 2.55, 1.7), V(0, 0.3, 1), 1.4, 0.42, silver, metal)
	body:tube("Shock", V(0, 1.95, 0.8), V(0, 2.85, 1.2), 0.26, frameColor)
	body:bar("Footpegs", V(-0.78, 1.55, 0.3), V(0.78, 1.55, 0.3), 0.12, dark, metal)

	-- long aluminium swingarm and chain
	for _, s in { -1, 1 } do
		arm:bar("Swingarm", V(s * 0.78, 1.9, 0.45), V(s * 0.78, geo.rearAxle.Y, geo.rearAxle.Z), 0.2, silver, metal)
	end
	arm:bar("Chain", V(-0.605, 1.8, 0.2), V(-0.605, 1.62, geo.rearAxle.Z), 0.08, dark, metal)
end

return Supermoto
