--[[
	Sportbike: a litre-class supersport (1.40 m wheelbase, 0.86 m seat, 24
	degree rake, 190 section rear tyre). Full fairing: a pointed nose with
	twin headlight slits and a tinted screen, side panels swept back, a
	belly pan, a tall tank, short seat and a sharp tail rising towards the
	back. Clip-on bars below the top clamp, gold upside-down fork, rearsets
	and a short side silencer. The rider tucks in behind the screen.

	Ground space: y = 0 is the road, front is -Z, axles at z = -2.5 / +2.5.
]]

local Kit = require(script.Parent.Kit)

local C = Kit.Colors
local V = Vector3.new
local rgb = Color3.fromRGB
local rad = math.rad

local TINT = { Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.3 }

local Sportbike = {
	rake = 24,
	forkLength = 2.48,
	front = { radius = 1.08, width = 0.55, rimRatio = 0.72, rim = rgb(22, 22, 24), spokes = 3, spokeWidth = 0.13, disc = -1 },
	rear = { radius = 1.12, width = 0.85, rimRatio = 0.7, rim = rgb(22, 22, 24), spokes = 3, spokeWidth = 0.15, disc = 1, sprocket = -1 },
	swingarmPivot = V(0, 1.75, 0.45),
	rider = { seat = V(0, 3.05, 0.85), foot = V(0.62, 1.7, 0.8), hand = V(1.0, 3.28, -1.12), lean = 48 },
}

function Sportbike.build(kits, geo, color, _v)
	local body, steer, arm = kits.body, kits.steer, kits.swingarm
	local head, axis = geo.head, geo.axis
	local back = Vector3.xAxis:Cross(axis)
	local metal = Kit.MetalProps
	local dark = rgb(30, 30, 34)
	local gold = rgb(214, 170, 60)
	local alloy = rgb(150, 152, 158)
	local fa = geo.frontAxle

	-- steering: gold upside-down fork, clamp, clip-ons, front fender
	for _, s in { -1, 1 } do
		steer:tube("Fork", V(s * 0.68, fa.Y, fa.Z), head + axis * 0.25 + V(s * 0.68, 0, 0), 0.3, gold, metal)
		steer:bar("ClipOn", V(s * 0.6, head.Y - 0.02, head.Z + 0.08), V(s * 1.05, 3.28, head.Z + 0.37), 0.16, dark, metal)
	end
	steer:oriented("TopClamp", head + axis * 0.1, V(1.5, 0, 0), axis * 0.16, back * 0.5, alloy, metal)
	steer:part("Part", "FrontFender", V(0.6, 0.08, 1.2), CFrame.new(0, fa.Y + geo.front.radius + 0.14, fa.Z - 0.1) * CFrame.Angles(rad(-6), 0, 0))

	-- fairing: nose with headlights and screen, side panels, belly pan
	local noseBack, noseFront = -1.25, -2.4
	body:wedge("Nose", V(0, 2.45, noseBack), V(0, 1.35, 0), V(0, 0, noseFront - noseBack), 1.6)
	body:panel("Screen", V(0, 3.45, -1.5), V(0, 4.15, -1.0), 1.1, 0.06, C.Glass, TINT)
	for _, s in { -1, 1 } do
		local lamp = body:headlight("Headlight", V(0.45, 0.16, 0.12), CFrame.new(s * 0.32, 2.62, -2.24), s > 0)
		local _ = lamp
		body:span("SidePanel", V(s * 0.72, 1.2, -1.3), V(s * 0.82, 3.0, 0.3))
		body:wedge("SidePanelTail", V(s * 0.77, 3.0, 0.3), V(0, -1.8, 0), V(0, 0, 0.9), 0.1)
	end
	body:span("BellyPan", V(-0.62, 0.5, -1.0), V(0.62, 1.2, 0.45), C.Trim)
	body:wedgePair("Mirror", V(0.95, 3.5, -1.2), V(0, 0.25, 0), V(0, 0, -0.35), 0.3, C.Trim)

	-- tank, seat, sharp tail
	body:span("Tank", V(-0.62, 2.9, -1.05), V(0.62, 3.6, 0.4))
	body:span("Seat", V(-0.48, 2.85, 0.4), V(0.48, 3.05, 1.55), rgb(24, 24, 26))
	local tail = CFrame.new(0, 3.2, 2.3) * CFrame.Angles(rad(-18), 0, 0)
	body:part("Part", "Tail", V(0.75, 0.42, 1.6), tail)
	body:taillight("Taillight", V(0.4, 0.14, 0.08), tail * CFrame.new(0, 0, 0.84))

	-- short side silencer, rearsets
	body:cyl("Silencer", V(0.62, 1.25, 1.3), V(0, 0.25, 1), 1.2, 0.45, rgb(70, 72, 78), metal)
	body:bar("Rearsets", V(-0.76, 1.7, 0.8), V(0.76, 1.7, 0.8), 0.12, alloy, metal)

	-- braced aluminium swingarm and chain
	for _, s in { -1, 1 } do
		arm:bar("Swingarm", V(s * 0.88, 1.75, 0.45), V(s * 0.88, geo.rearAxle.Y, geo.rearAxle.Z), 0.24, alloy, metal)
	end
	arm:bar("Chain", V(-0.67, 1.65, 0.25), V(-0.67, 1.66, geo.rearAxle.Z), 0.08, dark, metal)
end

return Sportbike
