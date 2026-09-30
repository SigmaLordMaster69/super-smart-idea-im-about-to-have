--[[
	RoadBuilder
	-----------
	Builds every part that belongs to the road inside one chunk: the asphalt
	slab, lane markings, guard rails, bridges, tunnels, delineator posts and
	road signs.

	The road is a chain of straight box parts between road samples. Runs of
	samples that are nearly straight get merged into one longer part, and
	each part is stretched slightly so the outside of a curve has no gaps.

	A segment (sample k -> k+1) belongs to the chunk that contains sample k,
	so each chunk builds a fixed, non-overlapping piece of the road no matter
	when it is built.
]]

local Weather = require(script.Parent.Weather)

local RoadBuilder = {}
RoadBuilder.__index = RoadBuilder

local abs, sqrt, floor, max, min, atan2 = math.abs, math.sqrt, math.floor, math.max, math.min, math.atan2
local rgb = Color3.fromRGB

local MAX_MERGE = 8 -- samples per merged part

local CONCRETE = rgb(176, 174, 168)
local CONCRETE_DARK = rgb(132, 130, 126)
local CONCRETE_LIGHT = rgb(196, 194, 188)
local RAIL = rgb(176, 180, 184) -- galvanised steel
local RAIL_GROOVE = rgb(120, 124, 128) -- the W-beam's groove, mostly in shade
local RAIL_POST = rgb(112, 116, 120)
local TUNNEL_WALL = rgb(196, 192, 182) -- light walls
local TUNNEL_ROOF = rgb(150, 148, 142) -- darker arch and ceiling, so the lamps stand out
local LAMP_HOUSING = rgb(70, 72, 76)
local REFLECTOR = rgb(255, 170, 40)

-- W-beam guard rail, in studs (about 0.28 m each): the beam is 1.1 tall
-- (0.3 m) with its top 2.5 above the road (0.7 m)
local RAIL_TOP = 2.5

function RoadBuilder.new(world, config, props)
	local self = setmetatable({}, RoadBuilder)
	self.world = world
	self.config = config
	self.props = props
	local rc = config.Road
	self.hw = rc.HalfWidth
	self.laneEdge = rc.LaneWidth * rc.Lanes / 2
	self.step = rc.SampleSpacing
	-- per-build frame cache
	self._pos, self._fwd, self._right, self._up = {}, {}, {}, {}
	self.wetness = 0 -- set by the weather; new asphalt is built wet
	return self
end

function RoadBuilder:_frame(k: number)
	local pos = self._pos[k]
	if pos then
		return pos, self._fwd[k], self._right[k], self._up[k]
	end
	local p, f, r, u = self.world.road:frameAtIndex(k)
	self._pos[k], self._fwd[k], self._right[k], self._up[k] = p, f, r, u
	return p, f, r, u
end

local function flatForward(f: Vector3): Vector3
	local v = Vector3.new(f.X, 0, f.Z)
	return v.Unit
end

-- Can samples k0..k1 be covered by one straight part?
function RoadBuilder:_straightEnough(k0: number, k1: number): boolean
	local road = self.world.road
	local px, pz, y, bank = road.px, road.pz, road.y, road.bank
	local mid = (k0 + k1) // 2
	if mid == k0 then
		return true
	end
	-- horizontal sagitta of the middle sample from the chord
	local ax, az = px[k0], pz[k0]
	local vx, vz = px[k1] - ax, pz[k1] - az
	local len = sqrt(vx * vx + vz * vz)
	local dev = abs((px[mid] - ax) * -vz + (pz[mid] - az) * vx) / len
	if dev > 0.12 then
		return false
	end
	local t = (mid - k0) / (k1 - k0)
	if abs(y[mid] - (y[k0] + (y[k1] - y[k0]) * t)) > 0.1 then
		return false
	end
	return abs(bank[k1] - bank[k0]) < 0.012
end

--[[
	One strip of parts following the road between samples a and b+1
	(segments a..b), only over segments where filter(k) is true.
	spec: offset, width, top (height of the top face above the road surface),
	      thickness, material, color, collide, query, name, roll, centered,
	      extend (extra length, so the ends of strips laid side by side do not
	      share a plane)
]]
function RoadBuilder:_strip(parent, a: number, b: number, filter, spec, origin: Vector3)
	local road = self.world.road
	local hd = road.hd
	local offset, width, top, thick = spec.offset, spec.width, spec.top, spec.thickness
	local roll = spec.roll
	local k = a
	while k <= b do
		if not filter(k) then
			k += 1
			continue
		end
		local k0, k1 = k, k
		while k1 + 1 <= b and k1 + 1 - k0 < MAX_MERGE and filter(k1 + 1) and self:_straightEnough(k0, k1 + 2) do
			k1 += 1
		end
		local kEnd = k1 + 1
		local pA, _, rA, uA = self:_frame(k0)
		local pB, _, rB, uB = self:_frame(kEnd)
		local a3 = pA + rA * offset + uA * top
		local b3 = pB + rB * offset + uB * top
		local up = (uA + uB).Unit
		local dir = b3 - a3
		local len = dir.Magnitude
		local cf = CFrame.lookAt((a3 + b3) * 0.5, (a3 + b3) * 0.5 + dir, up)
		if roll then
			cf *= CFrame.Angles(0, 0, roll)
		end
		if not spec.centered then
			cf *= CFrame.new(0, -thick / 2, 0)
		end
		local turn = abs(hd[kEnd] - hd[k0])
		local p = Instance.new("Part")
		p.Name = spec.name
		p.Anchored = true
		p.CanCollide = spec.collide == true
		p.CanQuery = spec.query == true
		p.CanTouch = false
		p.CastShadow = spec.shadow ~= false
		p.Material = spec.material
		p.Color = spec.color
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Size = Vector3.new(width, thick, len + 0.5 * width * turn + 0.12 + (spec.extend or 0))
		p.CFrame = cf - origin
		if spec.transparency then
			p.Transparency = spec.transparency
		end
		if spec.asphalt then
			local color, reflect = Weather.wetLook(spec.color, self.wetness)
			p.Color = color
			p.Reflectance = reflect
			p:AddTag("IR_Asphalt")
		end
		p.Parent = parent
		k = kEnd
	end
end

-- Premade guard rail segments laid end to end along the rail. Segments sit
-- on a fixed grid of arc length, so neighbouring chunks line up.
function RoadBuilder:_railSegments(a, b, side, hasRail, rail, origin, parent)
	local road = self.world.road
	local step = self.step
	local len = rail.length
	local sA, sB = (a - 1) * step, b * step
	local n = math.ceil(sA / len)
	while n * len < sB do
		local s0, s1 = n * len, (n + 1) * len
		local k0, k1 = floor(s0 / step) + 1, floor(s1 / step) + 1
		if hasRail(k0) and hasRail(k1) then
			local pA, _, rA = road:frameAt(s0)
			local pB, _, rB = road:frameAt(s1)
			local a3 = pA + rA * side * (self.hw + 1.3)
			local b3 = pB + rB * side * (self.hw + 1.3)
			local mid = (a3 + b3) * 0.5
			-- the same face of the model looks at the road on both sides
			local cf = CFrame.lookAt(mid, mid + (b3 - a3)) * CFrame.Angles(0, side < 0 and math.pi or 0, 0)
			local seg = rail.template:Clone()
			seg:PivotTo(cf - origin)
			seg.Parent = parent
		end
		n += 1
	end
end

-- A plain anchored part that nothing collides with.
local function piece(name: string, size: Vector3, cf: CFrame, color: Color3, material, parent, shadow: boolean?)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = shadow ~= false
	p.Material = material
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- Turned-down guard rail end: the beam bends down into the ground over
-- 12 studs, flared a little away from the road. `dir` is -1 at the start
-- of a run (going back) and 1 at its end.
function RoadBuilder:_railEnd(k: number, dir: number, side: number, origin: Vector3, parent)
	local road = self.world.road
	local hw = self.hw
	local p0, _, r0, u0 = self:_frame(k)
	local p1, _, r1, u1 = road:frameAt((k - 1) * self.step + dir * 12)
	local a = p0 + r0 * side * (hw + 1.2) + u0 * (RAIL_TOP - 0.55)
	local b = p1 + r1 * side * (hw + 1.6) - u1 * 0.4
	local mid = (a + b) * 0.5
	local len = (b - a).Magnitude
	-- (a little thinner than the beam, so their sides never share a plane)
	piece("RailEnd", Vector3.new(0.3, 1.1, len + 0.4), CFrame.lookAt(mid, b, u0) - origin, RAIL, Enum.Material.Metal, parent)
end

-- Place a model's ground pivot at world position `base`, facing oncoming
-- traffic.
local function placeFacing(model: Model, base: Vector3, fwd: Vector3, origin: Vector3, parent)
	local f = flatForward(fwd)
	model:PivotTo(CFrame.lookAt(base - origin, base - origin - f))
	model.Parent = parent
end

-- How far a sign reaches from its pivot towards the road (its +X side once
-- it faces oncoming drivers on the right).
local function signReach(model: Model): number
	local pivot = model:GetPivot()
	local reach = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local rel = pivot:ToObjectSpace(d.CFrame)
			local x0, _, _, r00, r01, r02 = rel:GetComponents()
			local s = d.Size
			reach = max(reach, x0 + abs(r00) * s.X / 2 + abs(r01) * s.Y / 2 + abs(r02) * s.Z / 2)
		end
	end
	return reach
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
function RoadBuilder:build(x0: number, z0: number, size: number, origin: Vector3, parent)
	local world = self.world
	local road = world.road
	local cfg = self.config
	local hw = self.hw
	local step = self.step

	road:ensureX(x0 + size + 64)
	local kA = road:indexAtX(x0)
	if road.px[kA] < x0 then
		kA += 1
	end
	local kB = road:indexAtX(x0 + size - 1e-6)
	if kB < kA then
		return
	end
	road:ensureFlags(kB + 120)

	self._pos, self._fwd, self._right, self._up = {}, {}, {}, {}

	-- runs of samples that lie inside this chunk
	local pz = road.pz
	local z1 = z0 + size
	local runStart
	for k = kA, kB + 1 do
		local inside = k <= kB and pz[k] >= z0 and pz[k] < z1
		if inside and not runStart then
			runStart = k
		elseif not inside and runStart then
			self:_buildRun(runStart, k - 1, origin, parent)
			runStart = nil
		end
	end
end

function RoadBuilder:_buildRun(a: number, b: number, origin: Vector3, parent)
	local world = self.world
	local road = world.road
	local cfg = self.config
	local rc = cfg.Road
	local hw = self.hw
	local laneEdge = self.laneEdge
	local curv = road.curv

	local function isBridge(k)
		return road:isBridge(k)
	end
	local function isTunnel(k)
		return road:isTunnel(k)
	end
	local function notBridge(k)
		return not road:isBridge(k)
	end
	local function always()
		return true
	end
	local function noPassing(k)
		return road:isTunnel(k) or road:isBridge(k) or abs(curv[k] or 0) > 1 / 320
	end

	-- asphalt
	local asphalt = Enum.Material.Asphalt
	self:_strip(parent, a, b, notBridge, {
		name = "Road", offset = 0, width = hw * 2, top = 0, thickness = rc.Thickness,
		material = asphalt, color = rc.AsphaltColor, collide = true, query = true, asphalt = true,
	}, origin)
	self:_strip(parent, a, b, isBridge, {
		name = "BridgeDeck", offset = 0, width = hw * 2 + 3, top = 0, thickness = 2.5,
		material = asphalt, color = rc.AsphaltColor, collide = true, query = true, asphalt = true,
	}, origin)

	-- markings
	local paint = Enum.Material.SmoothPlastic
	for _, side in { -1, 1 } do
		self:_strip(parent, a, b, always, {
			name = "EdgeLine", offset = side * (laneEdge + 0.3), width = 0.5, top = 0.09, thickness = 0.12,
			material = paint, color = rc.EdgeLineColor, shadow = false,
		}, origin)
		self:_strip(parent, a, b, noPassing, {
			name = "CenterLine", offset = side * 0.35, width = 0.3, top = 0.09, thickness = 0.12,
			material = paint, color = rc.CenterLineColor, shadow = false,
		}, origin)
	end
	self:_dashes(a, b, noPassing, origin, parent)

	-- guard rails: a W-beam on posts. The "GuardRail" strip is the beam and
	-- its collider; a thin dark strip along its middle stands in for the
	-- W's shaded groove. Runs that start or stop in open country end in a
	-- turned-down terminal (runs meeting a bridge or tunnel stop against the
	-- parapet or portal). Asset segments, if provided, sit on an invisible
	-- collider instead.
	local railAsset = self.props.assets and self.props.assets.rail
	local metal = Enum.Material.Metal
	for _, side in { -1, 1 } do
		local function hasRail(k)
			return road:hasRail(k, side)
		end
		self:_strip(parent, a, b, hasRail, {
			name = "GuardRail", offset = side * (hw + 1.2), width = 0.35, top = RAIL_TOP, thickness = 1.1,
			material = metal, color = RAIL, collide = true,
			transparency = railAsset and 1 or 0,
		}, origin)
		if railAsset then
			self:_railSegments(a, b, side, hasRail, railAsset, origin, parent)
			continue
		end
		self:_strip(parent, a, b, hasRail, {
			name = "RailGroove", offset = side * (hw + 0.99), width = 0.1, top = RAIL_TOP - 0.43, thickness = 0.24,
			material = metal, color = RAIL_GROOVE, extend = 0.1,
		}, origin)
		-- open country: no rail, bridge or tunnel
		local function openGround(k)
			return not hasRail(k) and not road:isBridge(k) and not road:isTunnel(k)
		end
		for k = a, b do
			if not hasRail(k) then
				continue
			end
			if k % cfg.GuardRail.PostSpacing == 0 then
				-- a deep post (spacer block and post in one) right behind the
				-- beam, driven 3.5 deep: the terrain hides it where the verge
				-- is level
				local p, f, _, u = self:_frame(k)
				local cf = CFrame.lookAt(p, p + f, u) - origin
				piece("RailPost", Vector3.new(0.8, 5.85, 0.5), cf * CFrame.new(side * (hw + 1.76), -0.575, 0), RAIL_POST, metal, parent, false)
				if k % (cfg.GuardRail.PostSpacing * 4) == 0 then
					-- reflector on top of the beam, glowing like the delineators
					piece("RailReflector", Vector3.new(0.14, 0.34, 0.1), cf * CFrame.new(side * (hw + 1.2), RAIL_TOP + 0.15, 0), REFLECTOR, Enum.Material.Neon, parent, false)
				end
			end
			if openGround(k - 1) then
				self:_railEnd(k, -1, side, origin, parent)
			end
			if openGround(k + 1) then
				self:_railEnd(k + 1, 1, side, origin, parent)
			end
		end
	end

	self:_bridges(a, b, isBridge, origin, parent)
	self:_tunnels(a, b, isTunnel, origin, parent)
	self:_roadside(a, b, origin, parent)
end

-- dashed centre line where passing is allowed
function RoadBuilder:_dashes(a, b, noPassing, origin, parent)
	local road = self.world.road
	local rc = self.config.Road
	local step = self.step
	local period = rc.DashLength + rc.DashGap
	local sA, sB = (a - 1) * step, b * step
	local n = math.ceil(sA / period)
	while n * period < sB do
		local s0 = n * period
		local k = floor(s0 / step) + 1
		if not noPassing(k) then
			local pA, _, _, uA = road:frameAt(s0)
			local pB, _, _, uB = road:frameAt(s0 + rc.DashLength)
			local up = (uA + uB).Unit
			local mid = (pA + pB) * 0.5 + up * 0.09
			local dir = pB - pA
			local p = Instance.new("Part")
			p.Name = "Dash"
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			p.Color = rc.CenterLineColor
			p.Size = Vector3.new(0.4, 0.12, dir.Magnitude)
			p.CFrame = CFrame.lookAt(mid, mid + dir, up) * CFrame.new(0, -0.06, 0) - origin
			p.Parent = parent
		end
		n += 1
	end
end

---------------------------------------------------------------------------
-- Bridges
---------------------------------------------------------------------------
function RoadBuilder:_block(name, size: Vector3, cf: CFrame, color: Color3, origin, parent, collide)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide ~= false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Concrete
	p.Color = color
	p.Size = size
	p.CFrame = cf - origin
	p.Parent = parent
	return p
end

function RoadBuilder:_bridges(a, b, isBridge, origin, parent)
	local road = self.world.road
	local sampler = self.world.sampler
	local cfg = self.config
	local hw = self.hw
	local concrete = Enum.Material.Concrete

	for _, side in { -1, 1 } do
		-- the parapet stands 0.1 proud of the deck edge and reaches 0.3 below
		-- the deck, so none of its faces share a plane with the deck's
		self:_strip(parent, a, b, isBridge, {
			name = "Parapet", offset = side * (hw + 1), width = 1.2, top = 3.2, thickness = 6,
			material = concrete, color = CONCRETE, collide = true, extend = 0.16,
		}, origin)
		self:_strip(parent, a, b, isBridge, {
			name = "ParapetCap", offset = side * (hw + 1), width = 1.5, top = 3.45, thickness = 0.4,
			material = concrete, color = CONCRETE_LIGHT, extend = 0.3,
		}, origin)
	end
	self:_strip(parent, a, b, isBridge, {
		name = "Girder", offset = 0, width = hw * 2 - 6, top = -2.5, thickness = 5.5,
		material = concrete, color = CONCRETE_DARK,
	}, origin)

	for k = a, b do
		if not isBridge(k) then
			continue
		end
		local p, f, r, u = self:_frame(k)
		local ff = flatForward(f)
		-- piers
		if k % cfg.Bridge.PierSpacing == 0 and isBridge(k - 2) and isBridge(k + 2) then
			local topY = p.Y - 8
			local ground = sampler:groundAt(p.X, p.Z)
			local bottomY = ground - 5
			-- the column stops inside its cap; only the cap meets the girder
			local height = topY - 1 - bottomY
			if height > 3 then
				local depth = height > 110 and 8 or 5.5
				local c = Vector3.new(p.X, bottomY + height / 2, p.Z)
				self:_block("Pier", Vector3.new(hw * 2 - 10, height, depth), CFrame.lookAt(c, c + ff), CONCRETE, origin, parent)
				local capC = Vector3.new(p.X, topY - 1, p.Z)
				self:_block("PierCap", Vector3.new(hw * 2 - 3, 2, depth + 2), CFrame.lookAt(capC, capC + ff), CONCRETE_DARK, origin, parent, false)
			end
		end
		-- abutments at both ends hide the terrain face
		if not isBridge(k - 1) or not isBridge(k + 1) then
			local c = p - Vector3.new(0, 19, 0)
			self:_block("Abutment", Vector3.new(hw * 2 + 6, 34, 6), CFrame.lookAt(c, c + ff), CONCRETE, origin, parent)
		end
	end
end

---------------------------------------------------------------------------
-- Tunnels
---------------------------------------------------------------------------
function RoadBuilder:_tunnels(a, b, isTunnel, origin, parent)
	local road = self.world.road
	local cfg = self.config.Tunnel
	local hw = self.hw
	local concrete = Enum.Material.Concrete
	local wall, ceil = cfg.WallHeight, cfg.CeilingHeight
	local wallO = hw + 2
	local topHalf = 9

	-- the sloped arch slabs run from the walls' inner top edge to the
	-- ceiling's edge, so the lining has no step where they meet
	local dO, dV = hw - (topHalf + 0.5), ceil - wall
	local slope = sqrt(dO * dO + dV * dV)
	local archX = (hw + topHalf + 0.5) / 2 + 0.6 * dV / slope
	local archY = (wall + ceil) / 2 + 0.6 * dO / slope
	for _, side in { -1, 1 } do
		self:_strip(parent, a, b, isTunnel, {
			name = "TunnelWall", offset = side * wallO, width = 4, top = wall, thickness = wall + 2.5,
			material = concrete, color = TUNNEL_WALL, collide = true,
		}, origin)
		self:_strip(parent, a, b, isTunnel, {
			name = "TunnelArch", offset = side * archX, width = slope + 1,
			top = archY, thickness = 1.2, centered = true, roll = atan2(-side * dV, dO),
			material = concrete, color = TUNNEL_ROOF, extend = 0.1,
		}, origin)
	end
	self:_strip(parent, a, b, isTunnel, {
		name = "TunnelCeiling", offset = 0, width = topHalf * 2 + 1, top = ceil + 1.2, thickness = 1.2,
		material = concrete, color = TUNNEL_ROOF,
	}, origin)

	for k = a, b do
		if not isTunnel(k) then
			continue
		end
		local p, f, r, u = self:_frame(k)
		if k % cfg.LampSpacing == 0 then
			-- a housing sunk into the ceiling with the glowing lens under it
			local cf = CFrame.lookAt(p + u * ceil, p + u * ceil + f, u) - origin
			piece("TunnelLightHousing", Vector3.new(1.8, 0.6, 6.4), cf * CFrame.new(0, -0.1, 0), LAMP_HOUSING, Enum.Material.Metal, parent, false)
			local lamp = piece("TunnelLight", Vector3.new(1.3, 0.14, 5.8), cf * CFrame.new(0, -0.42, 0), rgb(255, 222, 170), Enum.Material.Neon, nil, false)
			-- real lights are expensive; only every other lamp casts one
			if k % cfg.LightSpacing == 0 then
				local light = Instance.new("PointLight")
				light.Range = 56
				light.Brightness = 1.5
				light.Color = rgb(255, 214, 160)
				light.Shadows = false
				light.Parent = lamp
			end
			lamp.Parent = parent
		end
		local entering = not isTunnel(k - 1)
		if entering or not isTunnel(k + 1) then
			self:_portal(k, entering, origin, parent)
		end
	end
end

--[[
	Portal: a concrete headwall around the tunnel mouth. Its opening follows
	the lining (walls, sloped arch, ceiling) but sits 0.25 studs outside it,
	so the lining shows as a clean inner step and no faces coincide. Two
	wedges fill the upper corners over the arch slabs, and a coping runs
	along the top. Entering portals carry the tunnel's name.

	The portal is centred where the lining ends (sample k when entering,
	k + 1 when leaving, as segment k is the last one lined) and leans with
	the road's bank like the lining does, so the two line up.
]]
function RoadBuilder:_portal(k: number, entering: boolean, origin, parent)
	local cfg = self.config.Tunnel
	local hw = self.hw
	local wall, ceil = cfg.WallHeight, cfg.CeilingHeight
	local ceilHalf = 9.5 -- half width of the tunnel ceiling (see _tunnels)
	local p, f, r = self:_frame(entering and k or k + 1)
	local ff = flatForward(f)
	local rr = (r - ff * r:Dot(ff)).Unit
	local up = rr:Cross(ff)
	local e = 0.25
	local open = hw + e
	local height, depth, wing = 44, 5, 30
	local topY = height - 3
	-- blocks face the traffic that sees them
	local face = entering and -ff or ff
	local function facing(c: Vector3): CFrame
		return CFrame.lookAt(c, c + face, up)
	end
	for _, side in { -1, 1 } do
		local c = p + rr * side * (open + wing / 2) + up * (height / 2 - 3)
		self:_block("Portal", Vector3.new(wing, height, depth), facing(c), CONCRETE, origin, parent)
	end
	local lintelH = topY - (ceil + e)
	local c = p + up * (ceil + e + lintelH / 2)
	local lintel = self:_block("Portal", Vector3.new(open * 2, lintelH, depth), facing(c), CONCRETE, origin, parent)
	self:_block("PortalCap", Vector3.new((open + wing) * 2 + 1, 1.2, depth + 1), facing(p + up * (topY + 0.4)), CONCRETE_DARK, origin, parent, false)

	-- corner fills: right-angled wedges whose slope is the arch line moved
	-- out by e (x across the road, y up, for either side)
	local dO, dV = hw - ceilHalf, ceil - wall
	local len = sqrt(dO * dO + dV * dV)
	local ax, ay = hw + e * dV / len, wall + e * dO / len -- a point on the moved line
	local dx, dy = -dO / len, dV / len -- along it, towards the ceiling
	local y1 = ay + (open - ax) / dx * dy -- where it meets the portal's side
	local x2 = ax + (ceil + e - ay) / dy * dx -- where it meets the lintel
	local legV, legH = ceil + e - y1, open - x2
	local down = -up
	for _, side in { -1, 1 } do
		local out = rr * side
		local centre = p + out * (open - legH / 2) + up * (ceil + e - legV / 2)
		local fill = Instance.new("WedgePart")
		fill.Name = "PortalFill"
		fill.Anchored = true
		fill.CanCollide = false
		fill.CanQuery = false
		fill.CanTouch = false
		fill.Material = Enum.Material.Concrete
		fill.Color = CONCRETE
		-- local Y points down and Z outwards, so the right angle sits in the
		-- opening's top corner and the slope faces into the tunnel
		fill.Size = Vector3.new(depth, legV, legH)
		fill.CFrame = CFrame.fromMatrix(centre, down:Cross(out), down) - origin
		fill.Parent = parent
	end

	if entering then
		local sec = self.world.sections:get(self.world.road:indexToS(k))
		local word = string.match(sec.name, "^Lake (%a+)") or string.match(sec.name, "^([%a']+)") or "Mountain"
		-- name band just above the opening, its back on the lintel's face
		local bandC = p + up * (ceil + e + 3) + face * (depth / 2 + 0.15)
		local band = self:_block("PortalSign", Vector3.new(open * 1.4, 3.2, 0.3), facing(bandC), rgb(30, 80, 160), origin, parent, false)
		self.props.addText(band, string.upper(word) .. " TUNNEL", Color3.new(1, 1, 1))
		band.Material = Enum.Material.SmoothPlastic
		lintel.Name = "PortalLintel"
	end
end

---------------------------------------------------------------------------
-- Roadside: delineators and signs
---------------------------------------------------------------------------
local SPEED = { Meadow = 90, Forest = 80, Mountains = 60, Coast = 60, Canyon = 70, Lake = 70, RiverValley = 70 }

function RoadBuilder:_isCurveStart(j: number): boolean
	local curv = self.world.road.curv
	local th = 1 / 340
	local c, cp = curv[j], curv[j - 1]
	return c ~= nil and cp ~= nil and abs(c) >= th and abs(cp) < th
end

function RoadBuilder:_roadside(a, b, origin, parent)
	local world = self.world
	local road = world.road
	local props = self.props
	local hw = self.hw
	local step = self.step
	local curv = road.curv

	for k = a, b do
		local p, f, r, u = self:_frame(k)
		local tunnel, bridge = road:isTunnel(k), road:isBridge(k)
		local s = (k - 1) * step

		if k == 3 then
			local m = props:roadEnd(hw * 2)
			m:PivotTo(CFrame.lookAt(p - origin, p - origin - flatForward(f)))
			m.Parent = parent
		end

		-- delineator posts
		if k % 12 == 6 and not tunnel and not bridge then
			for _, side in { -1, 1 } do
				if not road:hasRail(k, side) then
					local base = p + r * side * (hw + 2.4) - Vector3.new(0, 0.3, 0)
					placeFacing(props:delineator(), base, f, origin, parent)
				end
			end
		end

		if tunnel or bridge then
			continue
		end
		local right = p + r * (hw + 3.8) - Vector3.new(0, 0.4, 0)
		local sign

		-- chevrons around the outside of sharp curves
		local c = curv[k] or 0
		if abs(c) >= 1 / 240 and k % 8 == 0 then
			local side = c > 0 and -1 or 1
			local base = p + r * side * (hw + 3.8) - Vector3.new(0, 0.4, 0)
			placeFacing(props:chevron(c > 0), base, f, origin, parent)
		end

		local j = k + 35
		if self:_isCurveStart(j) then
			local isolated = true
			for q = j - 70, j - 1 do
				if self:_isCurveStart(q) then
					isolated = false
					break
				end
			end
			if isolated then
				if curv[j] > 0 then
					sign = props:warningSign("CURVE\n\u{BB}", "CurveRight")
				else
					sign = props:warningSign("CURVE\n\u{AB}", "CurveLeft")
				end
			end
		end

		if not sign then
			local t0 = k + 45
			if road:isTunnel(t0) and not road:isTunnel(t0 - 1) then
				local len = 0
				while road:isTunnel(t0 + len) and len < 2000 do
					len += 1
					road:ensureFlags(t0 + len + 1)
				end
				sign = props:tunnelSign(string.format("%d m", math.floor(len * step * 0.28 / 10 + 0.5) * 10))
			end
		end

		if not sign then
			local sec = world.sections:get(s)
			local sPrev = s - step
			if sec.index > 1 and sPrev < sec.startS + 60 and s >= sec.startS + 60 then
				sign = props:guideSign("Entering\n" .. sec.name)
			elseif k % 700 == 120 then
				sign = props:speedLimit(SPEED[sec.type] or 70)
			elseif k % 900 == 450 and (sec.type == "Mountains" or sec.type == "Canyon") then
				sign = props:warningSign("FALLING\nROCKS", "FallingRocks")
			elseif k % 1000 == 700 and (sec.type == "Forest" or sec.type == "Meadow" or sec.type == "RiverValley") then
				sign = props:warningSign("DEER\nCROSSING", "Deer")
			end
		end

		if not sign then
			local km = floor(s * 0.00028)
			if km > 0 and km > floor((s - step) * 0.00028) then
				sign = props:distanceMarker(tostring(km))
			end
		end

		if sign then
			-- wide signs (guide signs) stand further out, so neither a post
			-- nor the board's edge reaches over the shoulder or a guard rail
			local extra = max(0, signReach(sign) - 2.4)
			placeFacing(sign, right + r * extra, f, origin, parent)
		end
	end
end

return RoadBuilder
