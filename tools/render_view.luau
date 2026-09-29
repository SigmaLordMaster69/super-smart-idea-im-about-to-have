--[[
	Dumps a height field + materials + props around a road sample for the
	offline perspective renderer (tools/render_view.py).
	  lune run tools/render_view <seed> <sampleIndex> <out.bin> [size] [step]
]]

local process = require("@lune/process")
local fs = require("@lune/fs")
local env = require("./env")

local Config = env.require("src/shared/Config")
local World = env.require("src/shared/World")
local ChunkManager = env.require("src/client/ChunkManager")
local TerrainSampler = env.require("src/shared/TerrainSampler")
local Vector3 = env.roblox.Vector3

local seed = tonumber(process.args[1]) or 12345
local k = tonumber(process.args[2]) or 400
local out = process.args[3] or "view.bin"
local size = tonumber(process.args[4]) or 1400
local step = tonumber(process.args[5]) or 2

local world = World.new(Config, seed)
local road = world.road
road:ensureFlags(k + 600)
local camK = math.max(1, k - 8)
local p, f = road:frameAtIndex(camK)
-- window centred ahead of the camera
local center = p + Vector3.new(f.X, 0, f.Z).Unit * (size * 0.42)
local x0, z0 = math.floor((center.X - size / 2) / 4) * 4, math.floor((center.Z - size / 2) / 4) * 4
local W = math.floor(size / step)

-- build chunks through the real pipeline to get props
local manager = ChunkManager.new(world, Config, env.terrain)
manager:setOrigin(Vector3.new(0, 0, 0))
manager.origin = Vector3.zero
manager.config = table.clone(Config)
manager.config.World = table.clone(Config.World)
manager.config.World.TerrainRadius = size * 0.75
manager.config.World.NearDecorRadius = size * 0.75
manager.config.World.FarDecorRadius = size * 0.75
manager:setFocus(center)
for _ = 1, 100000 do
	manager:update(0.2)
	if manager:progress(size * 0.72) >= 1 then
		break
	end
end

local sampler = world.sampler
local tb = manager.terrainBuilder
local H = table.create(W * W)
local WLv = table.create(W * W)
local info = table.create(W * W)
for j = 0, W - 1 do
	local z = z0 + (j + 0.5) * step
	for i = 0, W - 1 do
		local x = x0 + (i + 0.5) * step
		local h, vb, vt, water, s, d, ty, hint, flags, ys = sampler:column(x, z)
		local idx = j * W + i + 1
		local kk = math.clamp(math.floor(s / road.step + 1.5), 1, road.nFeat)
		local deck = -9999
		local ad = math.abs(d)
		local special = 0
		if ad <= Config.Road.HalfWidth then
			special = 1
			if road:isBridge(kk) then
				deck = ys
			elseif road:isTunnel(kk) then
				special = 3
			end
			if ad > Config.Road.LaneWidth - 0.2 and ad < Config.Road.LaneWidth + 0.6 then
				special = special == 3 and 3 or 2 -- edge line
			end
		elseif ad <= Config.Road.HalfWidth + 1.5 and road:isBridge(kk) then
			deck = ys + 3
			special = 4
		end
		H[idx] = h
		WLv[idx] = water > -1e9 and water or -9999
		info[idx] = { ty, hint, flags, deck, special, ys }
	end
end

local parts = { string.pack("<iiff", W, step, x0, z0) }
local rows = table.create(W)
for j = 0, W - 1 do
	local row = table.create(W)
	for i = 0, W - 1 do
		local idx = j * W + i + 1
		local h = H[idx]
		local e = H[idx + (i < W - 1 and 1 or 0)]
		local w = H[idx - (i > 0 and 1 or 0)]
		local n = H[idx + (j < W - 1 and W or 0)]
		local sth = H[idx - (j > 0 and W or 0)]
		local slope = math.sqrt(((e - w) / (2 * step)) ^ 2 + ((n - sth) / (2 * step)) ^ 2)
		local inf = info[idx]
		local v = world.noise:n2((x0 + i * step) / 38, (z0 + j * step) / 38, 101) * 1.6
		local mat = tb:_surface(inf[1], inf[2], inf[3], slope, h, WLv[idx], v)
		row[i + 1] = string.pack("<fffHB", h, WLv[idx], inf[4], mat.Value, inf[5])
	end
	rows[j + 1] = table.concat(row)
end
parts[2] = table.concat(rows)

-- props: models and loose parts
local props = {}
for _, d in manager.container:GetDescendants() do
	if d:IsA("Model") and d.Parent and d.Parent.Name == "Decor" then
		local pv = d.WorldPivot
		local height, radius, color = 0, 0, nil
		for _, part in d:GetDescendants() do
			if part:IsA("BasePart") then
				local top = part.CFrame.Position.Y + part.Size.Y / 2
				height = math.max(height, top - pv.Position.Y)
				radius = math.max(radius, math.min(part.Size.Y, part.Size.Z) / 2)
				if part.Material ~= env.roblox.Enum.Material.Wood then
					color = part.Color
				end
			end
		end
		color = color or env.roblox.Color3.new(0.3, 0.5, 0.3)
		table.insert(props, string.pack("<ffffffBBB", pv.Position.X, pv.Position.Y, pv.Position.Z, height, radius, 0, color.R * 255, color.G * 255, color.B * 255))
	elseif d:IsA("BasePart") and (d.Name == "GuardRail" or d.Name == "Parapet" or d.Name == "Pier" or d.Name == "Portal" or d.Name == "PortalLintel" or d.Name == "Abutment" or d.Name == "Rock") then
		local c = d.Color
		local pos = d.CFrame.Position
		table.insert(props, string.pack("<ffffffBBB", pos.X, pos.Y - d.Size.Y / 2, pos.Z, d.Size.Y, math.max(d.Size.X, d.Size.Z) / 2, 1, c.R * 255, c.G * 255, c.B * 255))
	end
end
parts[3] = string.pack("<i", #props) .. table.concat(props)

local pc, fc = road:frameAtIndex(camK)
local look = road:frameAtIndex(camK + 14)
parts[4] = string.pack("<ffffff", pc.X, pc.Y, pc.Z, look.X, look.Y, look.Z)
fs.writeFile(out, table.concat(parts))
local sec = world.sections:get(road:indexToS(k))
print(string.format("%s (%s) tunnel %s bridge %s, %d props", sec.name, sec.type, tostring(road:isTunnel(k)), tostring(road:isBridge(k)), #props))
