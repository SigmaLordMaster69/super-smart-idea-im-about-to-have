--[[
	Waterfalls
	----------
	Terrain water cannot flow, so where a river or lake runs into a drop the
	water would just stop in a wall. This finds those edges in a chunk's
	column data (a water column next to a column whose surface is much
	lower), follows the ground down the drop, and builds a falling sheet of
	water over it, with foam falling from the lip and spray at the bottom.
	In winter (frozen water) it is an icefall instead.

	Waterfalls.find(data, sampler)  -> list of falls (world coordinates)
	Waterfalls.build(data, sampler, origin, parent, frozen, sounds) -> count
]]

local SoundUtil = require(script.Parent.SoundUtil)

local Waterfalls = {}

local rgb = Color3.fromRGB
local max, abs, sqrt, clamp = math.max, math.abs, math.sqrt, math.clamp

local LIP_DROP = 2.5 -- surface drop to the next column that starts a fall
local MIN_HEIGHT = 8 -- total drop worth a waterfall
local STEP = 4
local MAX_STEPS = 24
local FOAM_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function surfaceAt(sampler, x: number, z: number): (number, boolean)
	local h, water = sampler:groundAt(x, z)
	if water > h + 0.3 then
		return water, true
	end
	return h, false
end

-- Follow the ground from the lip outwards until it levels off or reaches
-- water. Returns the profile as { {dist, y}, ... } starting at the lip.
local function trace(sampler, lx: number, lz: number, dx: number, dz: number, top: number)
	local profile = { { 0, top } }
	local last = top
	for k = 1, MAX_STEPS do
		local d = k * STEP
		local y, wet = surfaceAt(sampler, lx + dx * d, lz + dz * d)
		if y > last + 0.5 then
			break -- rising again: the fall ended in a dip
		end
		table.insert(profile, { d, y })
		if wet or last - y < 0.8 then
			break -- a pool, or the ground has levelled off
		end
		last = y
	end
	return profile
end

function Waterfalls.find(data, sampler)
	local G, H, WL = data.G, data.H, data.WL
	local N = G - 5
	local x0, z0 = data.x0, data.z0
	local edges = {}
	for j = 1, N do
		for i = 1, N do
			local idx = j * G + i + 1
			local w = WL[idx]
			if w > H[idx] + 0.5 then
				for di, dir in DIRS do
					local n = (j + dir[2]) * G + (i + dir[1]) + 1
					local below = max(H[n], WL[n])
					if w - below > LIP_DROP then
						table.insert(edges, { i = i, j = j, dir = di, top = w })
					end
				end
			end
		end
	end
	if #edges == 0 then
		return {}
	end

	-- Join edges into one fall per lip: edges of neighbouring columns (a
	-- diagonal lip is a staircase of +X and +Z edges) at a similar height.
	local byColumn = {}
	for n, e in edges do
		local k = e.j * G + e.i
		byColumn[k] = byColumn[k] or {}
		table.insert(byColumn[k], n)
	end
	local cluster = table.create(#edges, 0)
	local groups = {}
	for n, e in edges do
		if cluster[n] == 0 then
			local g = { n }
			cluster[n] = #groups + 1
			local head = 1
			while head <= #g do
				local cur = edges[g[head]]
				head += 1
				for oj = -1, 1 do
					for oi = -1, 1 do
						local list = byColumn[(cur.j + oj) * G + cur.i + oi]
						if list then
							for _, m in list do
								local o = edges[m]
								if cluster[m] == 0 and abs(o.top - cur.top) < 2 then
									-- no opposite-facing edges in one fall
									local d1, d2 = DIRS[o.dir], DIRS[e.dir]
									if d1[1] * d2[1] + d1[2] * d2[2] >= 0 then
										cluster[m] = #groups + 1
										table.insert(g, m)
									end
								end
							end
						end
					end
				end
			end
			table.insert(groups, g)
		end
	end

	local road = sampler.road
	local keepOff = sampler.hw + 8
	local falls = {}
	for _, g in groups do
		-- flow direction, lip centre and height
		local fx, fz, cx, cz, top = 0, 0, 0, 0, 0
		for _, n in g do
			local e = edges[n]
			local d = DIRS[e.dir]
			fx += d[1]
			fz += d[2]
			cx += x0 + (e.i - 0.5) * 4 + d[1] * 2
			cz += z0 + (e.j - 0.5) * 4 + d[2] * 2
			top += e.top
		end
		local count = #g
		local len = sqrt(fx * fx + fz * fz)
		if len > 0 then
			local dx, dz = fx / len, fz / len
			cx, cz, top = cx / count, cz / count, top / count
			-- width: spread of the edge midpoints across the flow, plus a column
			local lo, hi = math.huge, -math.huge
			for _, n in g do
				local e = edges[n]
				local d = DIRS[e.dir]
				local px = x0 + (e.i - 0.5) * 4 + d[1] * 2 - cx
				local pz = z0 + (e.j - 0.5) * 4 + d[2] * 2 - cz
				local along = px * dz - pz * dx
				lo, hi = math.min(lo, along), math.max(hi, along)
			end
			local width = hi - lo + 4
			local profile = trace(sampler, cx, cz, dx, dz, top)
			local last = profile[#profile]
			local bottom = last[2]
			local _, dLip = road:project(cx, cz)
			local _, dEnd = road:project(cx + dx * last[1], cz + dz * last[1])
			if top - bottom >= MIN_HEIGHT and abs(dLip) > keepOff and abs(dEnd) > keepOff then
				table.insert(falls, {
					lip = Vector3.new(cx, top, cz),
					width = width,
					dir = Vector3.new(dx, 0, dz),
					top = top,
					bottom = bottom,
					profile = profile,
				})
			end
		end
	end
	return falls
end

local function sheetPart(name, size, cf, frozen)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	if frozen then
		p.Material = Enum.Material.Ice
		p.Color = rgb(206, 228, 240)
	else
		p.Material = Enum.Material.Glass
		p.Color = rgb(196, 222, 234)
		p.Transparency = 0.3
	end
	return p
end

local function emitterHost(name, size, cf)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.CFrame = cf
	return p
end

local function seq(a, b)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

-- Builds the falls of one chunk into `parent`. Returns how many.
function Waterfalls.build(data, sampler, origin: Vector3, parent: Instance, frozen: boolean?, sounds)
	local falls = Waterfalls.find(data, sampler)
	for _, f in falls do
		local model = Instance.new("Model")
		model.Name = frozen and "Icefall" or "Waterfall"
		local dir = f.dir
		-- part axes: X along the lip, Z down the slope, Y out of the water
		local across = Vector3.new(dir.Z, 0, -dir.X)
		local lip = f.lip - origin
		local profile = f.profile
		for k = 1, #profile - 1 do
			local pa, pb = profile[k], profile[k + 1]
			-- a little above the ground so the sheet doesn't sink into it
			local lift = k == 1 and 0.15 or 0.6
			local a = lip + dir * pa[1] + Vector3.new(0, pa[2] - f.top + lift, 0)
			local b = lip + dir * pb[1] + Vector3.new(0, pb[2] - f.top + 0.6, 0)
			local look = (b - a).Unit
			local normal = look:Cross(across)
			local cf = CFrame.fromMatrix((a + b) * 0.5, across, normal)
			local part = sheetPart("Sheet", Vector3.new(f.width, 0.4, (b - a).Magnitude + 0.6), cf, frozen)
			part.Parent = model
		end
		if not frozen then
			local height = f.top - f.bottom
			-- foam falling from the lip
			local lipHost = emitterHost("Lip", Vector3.new(f.width, 0.3, 0.6), CFrame.fromMatrix(lip + dir * 0.6, across, Vector3.new(0, 1, 0)))
			local foam = Instance.new("ParticleEmitter")
			foam.Name = "Foam"
			foam.Texture = FOAM_TEXTURE
			foam.Color = ColorSequence.new(rgb(240, 248, 252))
			foam.Transparency = seq(0.35, 1)
			foam.Size = seq(1.4, 3.6)
			foam.LightInfluence = 0.8
			foam.EmissionDirection = Enum.NormalId.Bottom
			foam.Speed = NumberRange.new(4, 8)
			foam.SpreadAngle = Vector2.new(8, 8)
			foam.Acceleration = Vector3.new(0, -110, 0)
			local t = sqrt(2 * height / 110)
			foam.Lifetime = NumberRange.new(clamp(t * 0.8, 0.4, 3.5), clamp(t * 1.05, 0.5, 4))
			foam.Rate = clamp(f.width * 2.5, 8, 90)
			foam.Parent = lipHost
			lipHost.Parent = model
			-- spray at the bottom
			local last = profile[#profile]
			local base = lip + dir * (last[1] + 2) + Vector3.new(0, last[2] - f.top + 1, 0)
			local baseHost = emitterHost("Spray", Vector3.new(f.width, 1, 6), CFrame.fromMatrix(base, across, Vector3.new(0, 1, 0)))
			local spray = Instance.new("ParticleEmitter")
			spray.Name = "Spray"
			spray.Texture = FOAM_TEXTURE
			spray.Color = ColorSequence.new(rgb(236, 244, 250))
			spray.Transparency = seq(0.55, 1)
			spray.Size = seq(3, 9)
			spray.LightInfluence = 0.8
			spray.EmissionDirection = Enum.NormalId.Top
			spray.Speed = NumberRange.new(2, 6)
			spray.SpreadAngle = Vector2.new(50, 50)
			spray.Drag = 1.2
			spray.Lifetime = NumberRange.new(1.6, 2.6)
			spray.Rate = clamp(f.width * 1.2, 5, 40)
			spray.Parent = baseHost
			baseHost.Parent = model
			local s = sounds and SoundUtil.make(sounds.Waterfall, nil, clamp(height / 60, 0.2, 0.8), true)
			if s then
				s.RollOffMaxDistance = 260
				s.Parent = baseHost -- plays once the chunk is in the world
			end
		end
		model.Parent = parent
	end
	return #falls
end

return Waterfalls
