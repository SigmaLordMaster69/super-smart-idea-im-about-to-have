--[[
	Kit
	---
	Part helpers shared by the procedural vehicle bodies.

	Bodies are designed in "ground space": y = 0 is the road under the
	resting vehicle, x = 0 its centre line, z its length axis (front is -Z,
	z = 0 is the centre of the physics chassis). Every part is massless,
	non-colliding and welded to a base part (the chassis, or the trailer).

	Shapes (Roblox geometry):
	  WedgePart        right-angled prism; `wedge(P, A, B, width)` puts the
	                   right angle at P with legs A and B (perpendicular
	                   vectors), extruded `width` across, centred on P
	  CornerWedgePart  pyramid with its apex straight above one base corner;
	                   `corner(P, up, A, B)` has the apex at P + up and the
	                   base spanned by A and B from P
	  Cylinder         `cyl(center, axis, length, diameter)`

	Faces of different parts never lie in the same plane where they overlap
	(that flickers, "z-fighting"): touching parts meet face to face, and
	trims sit at least 0.02 studs proud of the panel under them.
]]

local Kit = {}
Kit.__index = Kit

local rgb = Color3.fromRGB
local SMOOTH = Enum.SurfaceType.Smooth

Kit.Colors = {
	Tyre = rgb(30, 30, 32),
	Trim = rgb(28, 28, 30), -- black plastic
	Dark = rgb(44, 45, 48),
	Chrome = rgb(206, 208, 212),
	Alloy = rgb(178, 181, 186),
	Glass = rgb(26, 32, 40),
	Lamp = rgb(255, 250, 236),
	LampHousing = rgb(186, 194, 204),
	Amber = rgb(255, 150, 30),
	TailOff = rgb(120, 16, 16),
	Plate = rgb(236, 236, 228),
	Interior = rgb(22, 22, 24),
}
local C = Kit.Colors

Kit.Paint = { Reflectance = 0.06 }
Kit.GlassProps = { Material = Enum.Material.Glass, Transparency = 0.35, Reflectance = 0.25 }
Kit.ChromeProps = { Reflectance = 0.45 }
Kit.MetalProps = { Material = Enum.Material.Metal }
Kit.NeonProps = { Material = Enum.Material.Neon }

-- `origin` is the ground-space frame in the world (default: the road under
-- the base part); parts are welded to `base` wherever they are.
function Kit.new(car, base: BasePart, groundY: number, color: Color3, parent: Instance, origin: CFrame?)
	local self = setmetatable({}, Kit)
	self.car = car
	self.base = base
	self.groundY = groundY
	self.color = color
	self.parent = parent
	self.origin = origin or base.CFrame * CFrame.new(0, groundY, 0)
	self.count = 0
	return self
end

-- A visual part at `cf` (ground space). Without a color it is painted in
-- the body color.
function Kit:part(className: string, name: string, size: Vector3, cf: CFrame, color: Color3?, props)
	local p = Instance.new(className)
	p.Name = name
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.Color = color or self.color
	if not color then
		p.Reflectance = Kit.Paint.Reflectance
	end
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	p.CFrame = self.origin * cf
	p.Parent = self.parent
	local w = Instance.new("WeldConstraint")
	w.Part0 = self.base
	w.Part1 = p
	w.Parent = p
	self.count += 1
	return p
end

-- axis-aligned block between two corners
function Kit:span(name: string, lo: Vector3, hi: Vector3, color: Color3?, props)
	local a = Vector3.new(math.min(lo.X, hi.X), math.min(lo.Y, hi.Y), math.min(lo.Z, hi.Z))
	local b = Vector3.new(math.max(lo.X, hi.X), math.max(lo.Y, hi.Y), math.max(lo.Z, hi.Z))
	return self:part("Part", name, b - a, CFrame.new((a + b) * 0.5), color, props)
end

-- the same block and its mirror image across the centre line (lo.X > 0)
function Kit:pair(name: string, lo: Vector3, hi: Vector3, color: Color3?, props)
	local a = self:span(name, lo, hi, color, props)
	local b = self:span(name, Vector3.new(-lo.X, lo.Y, lo.Z), Vector3.new(-hi.X, hi.Y, hi.Z), color, props)
	return a, b
end

-- block with edge vectors ax, ay, az (orthogonal) centred on `center`
function Kit:oriented(name: string, center: Vector3, ax: Vector3, ay: Vector3, az: Vector3, color: Color3?, props, className: string?)
	local x, y = ax.Unit, ay.Unit
	local cf = CFrame.fromMatrix(center, x, y, x:Cross(y))
	return self:part(className or "Part", name, Vector3.new(ax.Magnitude, ay.Magnitude, az.Magnitude), cf, color, props)
end

-- Flat panel along the line a-b (in a plane across X): `width` across X,
-- `thickness` under the line, its outer face `lift` above it (use a lift
-- of 0.02 or more to sit a window on a sloped panel without flicker).
function Kit:panel(name: string, a: Vector3, b: Vector3, width: number, thickness: number, color: Color3?, props, lift: number?)
	local along = b - a
	local across = Vector3.xAxis * width
	local normal = along.Unit:Cross(Vector3.xAxis)
	if normal.Y < 0 then
		normal = -normal
	end
	return self:oriented(name, (a + b) * 0.5 + normal * ((lift or 0) - thickness * 0.5), across, normal * thickness, along, color, props)
end

-- right-angled prism: right angle at P, legs A and B, extruded `width`
function Kit:wedge(name: string, P: Vector3, A: Vector3, B: Vector3, width: number, color: Color3?, props)
	local y = A.Unit
	local z = -B.Unit
	local x = y:Cross(z)
	local center = P + A * 0.5 + B * 0.5
	local cf = CFrame.fromMatrix(center, x, y, z)
	return self:part("WedgePart", name, Vector3.new(width, A.Magnitude, B.Magnitude), cf, color, props)
end

-- the wedge and its mirror image (P.X > 0 is the right side)
function Kit:wedgePair(name: string, P: Vector3, A: Vector3, B: Vector3, width: number, color: Color3?, props)
	local m = Vector3.new(-1, 1, 1)
	return self:wedge(name, P, A, B, width, color, props), self:wedge(name, P * m, A * m, B * m, width, color, props)
end

-- pyramid with its apex at P + up and its base spanned by A and B from P
function Kit:corner(name: string, P: Vector3, up: Vector3, A: Vector3, B: Vector3, color: Color3?, props)
	local y = up.Unit
	local x, z = -A.Unit, B.Unit
	if x:Cross(y):Dot(z) < 0 then
		A, B = B, A
		x, z = -A.Unit, B.Unit
	end
	local center = P + up * 0.5 + A * 0.5 + B * 0.5
	local cf = CFrame.fromMatrix(center, x, y, z)
	return self:part("CornerWedgePart", name, Vector3.new(A.Magnitude, up.Magnitude, B.Magnitude), cf, color, props)
end

function Kit:cornerPair(name: string, P: Vector3, up: Vector3, A: Vector3, B: Vector3, color: Color3?, props)
	local m = Vector3.new(-1, 1, 1)
	return self:corner(name, P, up, A, B, color, props), self:corner(name, P * m, up * m, A * m, B * m, color, props)
end

local function perpendicular(axis: Vector3): Vector3
	local ref = math.abs(axis.Y) < 0.9 and Vector3.yAxis or Vector3.zAxis
	return axis:Cross(ref).Unit
end

-- cylinder along `axis`
function Kit:cyl(name: string, center: Vector3, axis: Vector3, length: number, diameter: number, color: Color3?, props)
	axis = axis.Unit
	local up = perpendicular(axis)
	local cf = CFrame.fromMatrix(center, axis, up)
	local p = self:part("Part", name, Vector3.new(length, diameter, diameter), cf, color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- cylinder from a to b
function Kit:tube(name: string, a: Vector3, b: Vector3, diameter: number, color: Color3?, props)
	return self:cyl(name, (a + b) * 0.5, b - a, (b - a).Magnitude, diameter, color, props)
end

-- square bar from a to b
function Kit:bar(name: string, a: Vector3, b: Vector3, thickness: number, color: Color3?, props)
	local along = b - a
	local x = perpendicular(along)
	local y = along.Unit:Cross(x)
	return self:oriented(name, (a + b) * 0.5, x * thickness, y * thickness, along, color, props)
end

function Kit:ball(name: string, center: Vector3, diameter: number, color: Color3?, props)
	local p = self:part("Part", name, Vector3.new(diameter, diameter, diameter), CFrame.new(center), color, props)
	p.Shape = Enum.PartType.Ball
	return p
end

---------------------------------------------------------------------------
-- Lights
---------------------------------------------------------------------------

-- Make a part cast the headlight beam from one of its faces (switched on
-- at night by Car).
function Kit:beam(part: BasePart, face: Enum.NormalId?)
	local spot = Instance.new("SpotLight")
	spot.Face = face or Enum.NormalId.Front
	spot.Angle = 62
	spot.Range = 85
	spot.Brightness = 4
	spot.Color = rgb(255, 244, 222)
	spot.Shadows = true
	spot.Enabled = false
	spot.Parent = part
	table.insert(self.car.headlights, spot)
	return spot
end

-- A glowing headlight lens; the ones with `beam` cast a SpotLight forwards.
function Kit:headlight(name: string, size: Vector3, cf: CFrame, beam: boolean?)
	local lamp = self:part("Part", name, size, cf, C.Lamp, Kit.NeonProps)
	if beam then
		self:beam(lamp)
	end
	return lamp
end

-- A brake light: dark red, glows when braking (Car:step switches it).
function Kit:taillight(name: string, size: Vector3, cf: CFrame, className: string?)
	local p = self:part(className or "Part", name, size, cf, C.TailOff)
	table.insert(self.car.taillights, p)
	return p
end

---------------------------------------------------------------------------
-- Wheels
---------------------------------------------------------------------------
--[[
	Builds the visible wheels on physics corners. Each corner gets one wheel
	per entry in style.axles (z offsets, for tandem axles), driven by a Weld
	that Car:render moves. Style:
	  width       tyre width
	  rim         rim colour, rimRatio its size (share of the tyre diameter)
	  spokes      number of spoke bars across the face (each bar makes two
	              spokes); 0 for a plain disc
	  hub         hub cap colour (optional)
	  dual        twin tyres (trucks)
	  axles       list of z offsets from the corner (default { 0 })
	  rimProps    extra properties for the rim (material, reflectance)
]]
function Kit:wheels(corners, attachY: number, style, filter)
	for _, w in corners do
		if filter and not filter(w) then
			continue
		end
		w.visuals = w.visuals or {}
		local R = w.radius
		local side = w.x < 0 and -1 or 1
		for _, dz in style.axles or { 0 } do
			local hub = Vector3.new(w.x, attachY - w.length, w.z + dz) -- base space
			local parts = {}
			local width = style.width
			local tyre
			if style.dual then
				local gap = 0.16
				local single = (width - gap) * 0.5
				tyre = self:_raw("Wheel", Vector3.new(single, R * 2, R * 2), hub + Vector3.new(side * (single + gap) * 0.5, 0, 0), C.Tyre)
				local inner = self:_raw("WheelInner", Vector3.new(single, R * 2, R * 2), hub - Vector3.new(side * (single + gap) * 0.5, 0, 0), C.Tyre)
				table.insert(parts, inner)
			else
				tyre = self:_raw("Wheel", Vector3.new(width, R * 2, R * 2), hub, C.Tyre)
			end
			tyre.Shape = Enum.PartType.Cylinder
			for _, p in parts do
				p.Shape = Enum.PartType.Cylinder
			end
			-- the outer face of the (outer) tyre
			local tyreCenter = tyre.CFrame
			local tyreW = tyre.Size.X
			local face = tyreW * 0.5
			local rr = R * (style.rimRatio or 0.66)
			local rim = self:_raw("Rim", Vector3.new(tyreW + 0.04, rr * 2, rr * 2), nil, style.rim or C.Alloy, style.rimProps)
			rim.Shape = Enum.PartType.Cylinder
			rim.CFrame = tyreCenter
			table.insert(parts, rim)
			local n = style.spokes or 0
			local thickest = 0
			for i = 1, n do
				local t = 0.1 + 0.04 * (i - 1)
				thickest = t
				local spoke = self:_raw("Spoke", Vector3.new(t, style.spokeWidth or rr * 0.3, rr * 1.9), nil, style.rim or C.Alloy, style.rimProps)
				spoke.CFrame = tyreCenter * CFrame.new(side * (face + 0.02), 0, 0) * CFrame.Angles((i - 1) * math.pi / n, 0, 0)
				table.insert(parts, spoke)
			end
			if style.hub then
				local len = math.max(thickest, 0.1) + 0.12
				local cap = self:_raw("HubCap", Vector3.new(len, rr * (style.hubRatio or 0.34) * 2, rr * (style.hubRatio or 0.34) * 2), nil, style.hub, style.hubProps)
				cap.Shape = Enum.PartType.Cylinder
				cap.CFrame = tyreCenter * CFrame.new(side * (face + 0.02), 0, 0)
				table.insert(parts, cap)
			end
			local weld = Instance.new("Weld")
			weld.Part0 = self.base
			weld.Part1 = tyre
			weld.C0 = self.base.CFrame:ToObjectSpace(tyre.CFrame)
			weld.Parent = tyre
			tyre:SetAttribute("IR_Wheel", true)
			for _, p in parts do
				p:SetAttribute("IR_Wheel", true)
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = tyre
				wc.Part1 = p
				wc.Parent = p
			end
			-- where the tyre sits relative to the corner (dual tyres are offset)
			local offset = self.base.CFrame:PointToObjectSpace(tyre.CFrame.Position) - hub
			table.insert(w.visuals, { part = tyre, weld = weld, dz = dz, dx = offset.X, rim = rim, parts = parts })
		end
		local first = w.visuals[1]
		if first then
			w.part, w.hub, w.weld = first.part, first.rim, first.weld
		end
	end
end

-- an unwelded wheel part in base space (the wheel rig welds it)
function Kit:_raw(name: string, size: Vector3, pos: Vector3?, color: Color3, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = false
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = SMOOTH
	p.BottomSurface = SMOOTH
	p.Material = Enum.Material.SmoothPlastic
	p.Size = size
	p.Color = color
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	if pos then
		p.CFrame = self.base.CFrame * CFrame.new(pos)
	end
	p.Parent = self.parent
	self.count += 1
	return p
end

return Kit
