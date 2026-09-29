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

local RoadBuilder = {}
RoadBuilder.__index = RoadBuilder

local abs, sqrt, floor, max, min, atan2 = math.abs, math.sqrt, math.floor, math.max, math.min, math.atan2
local rgb = Color3.fromRGB

local MAX_MERGE = 8 -- samples per merged part

local CONCRETE = rgb(176, 174, 168)
local CONCRETE_DARK = rgb(132, 130, 126)
local RAIL = rgb(176, 180, 184)
local TUNNEL_WALL = rgb(196, 192, 182)

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
	      thickness, material, color, collide, query, name, roll, centered
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
		p.Size = Vector3.new(width, thick, len + 0.5 * width * turn + 0.12)
		p.CFrame = cf - origin
		p.Parent = parent
		k = kEnd
	end
end

-- Place a model's ground pivot at world position `base`, facing oncoming
-- traffic.
local function placeFacing(model: Model, base: Vector3, fwd: Vector3, origin: Vector3, parent)
	local f = flatForward(fwd)
	model:PivotTo(CFrame.lookAt(base - origin, base - origin - f))
	model.Parent = parent
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
		material = asphalt, color = rc.AsphaltColor, collide = true, query = true,
	}, origin)
	self:_strip(parent, a, b, isBridge, {
		name = "BridgeDeck", offset = 0, width = hw * 2 + 3, top = 0, thickness = 2.5,
		material = asphalt, color = rc.AsphaltColor, collide = true, query = true,
	}, origin)

	-- markings
	local paint = Enum.Material.SmoothPlastic
	for _, side in { -1, 1 } do
		self:_strip(parent, a, b, always, {
			name = "EdgeLine", offset = side * (laneEdge + 0.3), width = 0.5, top = 0.04, thickness = 0.1,
			material = paint, color = rc.EdgeLineColor, shadow = false,
		}, origin)
		self:_strip(parent, a, b, noPassing, {
			name = "CenterLine", offset = side * 0.35, width = 0.3, top = 0.04, thickness = 0.1,
			material = paint, color = rc.CenterLineColor, shadow = false,
		}, origin)
	end
	self:_dashes(a, b, noPassing, origin, parent)

	-- guard rails
	for _, side in { -1, 1 } do
		local function hasRail(k)
			return road:hasRail(k, side)
		end
		self:_strip(parent, a, b, hasRail, {
			name = "GuardRail", offset = side * (hw + 1.2), width = 0.35, top = 2.7, thickness = 1.1,
			material = Enum.Material.Metal, color = RAIL, collide = true,
		}, origin)
		for k = a, b do
			if k % cfg.GuardRail.PostSpacing == 0 and hasRail(k) then
				local p, f, r, u = self:_frame(k)
				local c = p + r * side * (hw + 1.35) + u * 1.1
				local post = Instance.new("Part")
				post.Name = "RailPost"
				post.Anchored = true
				post.CanCollide = false
				post.CanQuery = false
				post.CanTouch = false
				post.CastShadow = false
				post.Material = Enum.Material.Metal
				post.Color = CONCRETE_DARK
				post.Size = Vector3.new(0.45, 3.2, 0.45)
				post.CFrame = CFrame.lookAt(c, c + f, u) - origin
				post.Parent = parent
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
			local mid = (pA + pB) * 0.5 + up * 0.04
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
			p.Size = Vector3.new(0.4, 0.1, dir.Magnitude)
			p.CFrame = CFrame.lookAt(mid, mid + dir, up) * CFrame.new(0, -0.05, 0) - origin
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
		self:_strip(parent, a, b, isBridge, {
			name = "Parapet", offset = side * (hw + 0.9), width = 1.2, top = 3.2, thickness = 5.7,
			material = concrete, color = CONCRETE, collide = true,
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
			local height = topY - bottomY
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

	for _, side in { -1, 1 } do
		self:_strip(parent, a, b, isTunnel, {
			name = "TunnelWall", offset = side * wallO, width = 4, top = wall, thickness = wall + 2.5,
			material = concrete, color = TUNNEL_WALL, collide = true,
		}, origin)
		local dO, dV = wallO - topHalf, ceil - wall
		self:_strip(parent, a, b, isTunnel, {
			name = "TunnelArch", offset = side * (wallO + topHalf) / 2, width = sqrt(dO * dO + dV * dV) + 1,
			top = (wall + ceil) / 2, thickness = 1.2, centered = true, roll = atan2(-side * dV, dO),
			material = concrete, color = TUNNEL_WALL,
		}, origin)
	end
	self:_strip(parent, a, b, isTunnel, {
		name = "TunnelCeiling", offset = 0, width = topHalf * 2 + 1, top = ceil + 1.2, thickness = 1.2,
		material = concrete, color = TUNNEL_WALL,
	}, origin)

	for k = a, b do
		if not isTunnel(k) then
			continue
		end
		local p, f, r, u = self:_frame(k)
		if k % cfg.LightSpacing == 0 then
			local c = p + u * (ceil - 0.2)
			local lamp = Instance.new("Part")
			lamp.Name = "TunnelLight"
			lamp.Anchored = true
			lamp.CanCollide = false
			lamp.CanQuery = false
			lamp.CanTouch = false
			lamp.CastShadow = false
			lamp.Material = Enum.Material.Neon
			lamp.Color = rgb(255, 222, 170)
			lamp.Size = Vector3.new(1.4, 0.3, 6)
			lamp.CFrame = CFrame.lookAt(c, c + f, u) - origin
			local light = Instance.new("PointLight")
			light.Range = 44
			light.Brightness = 1.3
			light.Color = rgb(255, 214, 160)
			light.Shadows = false
			light.Parent = lamp
			lamp.Parent = parent
		end
		local entering = not isTunnel(k - 1)
		if entering or not isTunnel(k + 1) then
			self:_portal(k, entering, origin, parent)
		end
	end
end

function RoadBuilder:_portal(k: number, entering: boolean, origin, parent)
	local cfg = self.config.Tunnel
	local hw = self.hw
	local p, f = self:_frame(k)
	local ff = flatForward(f)
	local rr = Vector3.new(-ff.Z, 0, ff.X)
	local open = hw + 4
	local height = 44
	-- blocks face the traffic that sees them
	local face = entering and -ff or ff
	for _, side in { -1, 1 } do
		local c = p + rr * side * (open + 13) + Vector3.new(0, height / 2 - 3, 0)
		self:_block("Portal", Vector3.new(26, height, 5), CFrame.lookAt(c, c + face), CONCRETE, origin, parent)
	end
	local lintelH = height - 3 - cfg.CeilingHeight - 1
	local c = p + Vector3.new(0, cfg.CeilingHeight + 1 + lintelH / 2, 0)
	local lintel = self:_block("Portal", Vector3.new(open * 2, lintelH, 5), CFrame.lookAt(c, c + face), CONCRETE, origin, parent)
	if entering then
		local sec = self.world.sections:get(self.world.road:indexToS(k))
		local word = string.match(sec.name, "^Lake (%a+)") or string.match(sec.name, "^([%a']+)") or "Mountain"
		local band = self:_block("PortalSign", Vector3.new(open * 1.4, 3.2, 0.3), CFrame.lookAt(c + face * 2.7, c + face * 3.7), rgb(30, 80, 160), origin, parent, false)
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
				sign = props:warningSign(curv[j] > 0 and "CURVE\n\u{BB}" or "CURVE\n\u{AB}")
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
				sign = props:warningSign("FALLING\nROCKS")
			elseif k % 1000 == 700 and (sec.type == "Forest" or sec.type == "Meadow" or sec.type == "RiverValley") then
				sign = props:warningSign("DEER\nCROSSING")
			end
		end

		if not sign then
			local km = floor(s * 0.00028)
			if km > 0 and km > floor((s - step) * 0.00028) then
				sign = props:distanceMarker(tostring(km))
			end
		end

		if sign then
			placeFacing(sign, right, f, origin, parent)
		end
	end
end

return RoadBuilder
