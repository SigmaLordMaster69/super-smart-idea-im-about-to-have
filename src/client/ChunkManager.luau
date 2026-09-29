--[[
	ChunkManager
	------------
	Streams the world around the car in square chunks.

	All generation happens in one worker coroutine that is resumed every
	frame with a time budget; long jobs check the budget and yield, so
	building never causes a big frame spike. Jobs, in priority order:
	  1. rebase (floating origin), when requested
	  2. unload chunks that are too far away
	  3. build terrain + road for the nearest missing chunk
	  4. change a chunk's decoration detail (none / far / near)

	Floating origin: generator coordinates ("world") grow forever, but
	Roblox physics and rendering get jittery far from (0, 0, 0). Everything
	placed in the DataModel is world minus `origin`. When the car gets far
	from the Roblox origin, the origin jumps forward: terrain is copied to its
	new place over a few frames (out of sight), then every part, the car and
	the camera move in a single frame.
]]

local Workspace = game:GetService("Workspace")

local TerrainBuilder = require(script.Parent.TerrainBuilder)
local RoadBuilder = require(script.Parent.RoadBuilder)
local Decorator = require(script.Parent.Decorator)
local Props = require(script.Parent.Props)

local floor, sqrt = math.floor, math.sqrt

local ChunkManager = {}
ChunkManager.__index = ChunkManager

local function key(cx: number, cz: number): number
	return cx * 131072 + cz
end

function ChunkManager.new(world, config, terrain, assets)
	local self = setmetatable({}, ChunkManager)
	self.world = world
	self.config = config
	self.terrain = terrain
	self.size = config.World.ChunkSize

	local container = Instance.new("Folder")
	container.Name = "InfiniteRoadWorld"
	container.Parent = Workspace
	self.container = container

	self.props = Props.new(assets)
	self.terrainBuilder = TerrainBuilder.new(world, config, terrain)
	self.roadBuilder = RoadBuilder.new(world, config, self.props)
	self.decorator = Decorator.new(world, config, self.props)

	self.chunks = {}
	self.origin = Vector3.zero
	self.focus = Vector3.zero
	self.wanted = {}
	self.wantedFocus = nil
	self.wantedTime = 0
	self.deadline = 0
	self.pendingRebase = nil
	self.lastWork = 0
	self.onRebase = nil -- function(delta: Vector3)
	self.stats = { built = 0, unloaded = 0, decorated = 0, rebases = 0 }
	self:_newWorker()
	return self
end

---------------------------------------------------------------------------
-- Coordinates
---------------------------------------------------------------------------
function ChunkManager:toRoblox(worldPos: Vector3): Vector3
	return worldPos - self.origin
end

function ChunkManager:toWorld(robloxPos: Vector3): Vector3
	return robloxPos + self.origin
end

-- Initial origin: chunk-aligned so voxel grids line up.
function ChunkManager:setOrigin(worldPos: Vector3)
	local size = self.size
	self.origin = Vector3.new(floor(worldPos.X / size) * size, 0, floor(worldPos.Z / size) * size)
end

-- Focus point in world coordinates (usually car position + velocity lead).
function ChunkManager:setFocus(worldPos: Vector3)
	self.focus = worldPos
end

---------------------------------------------------------------------------
-- Worker
---------------------------------------------------------------------------
function ChunkManager:_yield()
	if os.clock() > self.deadline then
		coroutine.yield()
	end
end

function ChunkManager:_newWorker()
	self.yieldFn = function()
		self:_yield()
	end
	self.worker = coroutine.create(function()
		while true do
			local job = self:_nextJob()
			if job then
				local ok, err = pcall(job)
				if not ok then
					warn("[InfiniteRoad] generation job failed: " .. tostring(err))
				end
			else
				coroutine.yield()
			end
		end
	end)
end

-- Run generation for up to `budget` seconds this frame.
function ChunkManager:update(budget: number)
	local start = os.clock()
	self.deadline = start + budget
	if coroutine.status(self.worker) == "dead" then
		self:_newWorker()
	end
	local ok, err = coroutine.resume(self.worker)
	if not ok then
		warn("[InfiniteRoad] generation worker crashed: " .. tostring(err))
		self:_newWorker()
	end
	self.lastWork = os.clock() - start
end

-- Wanted chunks that are not built yet.
function ChunkManager:pendingCount(): number
	local n = 0
	for _, w in self.wanted do
		if not self.chunks[w.key] then
			n += 1
		end
	end
	return n
end

function ChunkManager:_refreshWanted()
	local cfg = self.config.World
	local size = self.size
	local f = self.focus
	local radius = cfg.TerrainRadius
	local r = math.ceil(radius / size)
	local fcx, fcz = floor(f.X / size), floor(f.Z / size)
	local list = {}
	for dz = -r, r do
		for dx = -r, r do
			local cx, cz = fcx + dx, fcz + dz
			local mx, mz = (cx + 0.5) * size - f.X, (cz + 0.5) * size - f.Z
			local dist = sqrt(mx * mx + mz * mz)
			if dist <= radius then
				table.insert(list, { cx = cx, cz = cz, dist = dist, key = key(cx, cz) })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	self.wanted = list
	self.wantedFocus = f
	self.wantedTime = os.clock()
end

function ChunkManager:_distanceTo(rec): number
	local size = self.size
	local f = self.focus
	local mx, mz = (rec.cx + 0.5) * size - f.X, (rec.cz + 0.5) * size - f.Z
	return sqrt(mx * mx + mz * mz)
end

function ChunkManager:_decorLevelFor(dist: number): number
	local cfg = self.config.World
	if dist <= cfg.NearDecorRadius then
		return 2
	elseif dist <= cfg.FarDecorRadius then
		return 1
	end
	return 0
end

function ChunkManager:_nextJob()
	if self.pendingRebase then
		local target = self.pendingRebase
		self.pendingRebase = nil
		return function()
			self:_rebase(target)
		end
	end

	if not self.wantedFocus or (self.wantedFocus - self.focus).Magnitude > 24 or os.clock() - self.wantedTime > 1 then
		self:_refreshWanted()
	end

	-- unload
	local limit = self.config.World.TerrainRadius + self.config.World.UnloadMargin
	for k, rec in self.chunks do
		if (rec.data or rec.failed) and self:_distanceTo(rec) > limit then
			return function()
				self:_unload(k)
			end
		end
	end

	-- nearest first: build missing chunks, and bring decoration up to the
	-- detail its distance calls for. Near detail is worth doing before
	-- building far-away terrain; far detail waits until terrain is done.
	local farDecor
	for _, w in self.wanted do
		local rec = self.chunks[w.key]
		if not rec then
			return function()
				self:_build(w.cx, w.cz, w.key)
			end
		end
		if rec.data and not rec.failed then
			local level = self:_decorLevelFor(w.dist)
			if level ~= rec.decorLevel then
				if level == 2 or rec.decorLevel == 2 then
					return function()
						self:_decorate(rec, level)
					end
				elseif not farDecor then
					farDecor = function()
						self:_decorate(rec, level)
					end
				end
			end
		end
	end
	return farDecor
end

---------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------
function ChunkManager:_build(cx: number, cz: number, k: number)
	local rec = { cx = cx, cz = cz, decorLevel = 0 }
	self.chunks[k] = rec
	local origin = self.origin
	local ok, err = pcall(function()
		rec.data = self.terrainBuilder:build(cx, cz, origin, self.yieldFn)
		local folder = Instance.new("Folder")
		folder.Name = string.format("Chunk_%d_%d", cx, cz)
		rec.road = folder
		self.roadBuilder:build(rec.data.x0, rec.data.z0, self.size, origin, folder)
		folder.Parent = self.container
	end)
	if not ok then
		-- keep the record so the chunk is not retried every frame; it is
		-- dropped (and may be retried) once the car moves away
		rec.failed = true
		warn(string.format("[InfiniteRoad] chunk %d,%d failed: %s", cx, cz, tostring(err)))
		return
	end
	self.stats.built += 1
end

function ChunkManager:_decorate(rec, level: number)
	if rec.decor then
		rec.decor:Destroy()
		rec.decor = nil
	end
	rec.decorLevel = level
	if level == 0 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Decor"
	self.decorator:build(rec.data, level, self.origin, folder, self.yieldFn)
	if self.chunks[key(rec.cx, rec.cz)] ~= rec then
		folder:Destroy() -- unloaded while we were building
		return
	end
	folder.Parent = rec.road
	rec.decor = folder
	self.stats.decorated += 1
end

function ChunkManager:_unload(k: number)
	local rec = self.chunks[k]
	if not rec then
		return
	end
	self.chunks[k] = nil
	if rec.data then
		self.terrainBuilder:clear(rec.data, self.origin)
	end
	if rec.road then
		rec.road:Destroy()
	end
	self.stats.unloaded += 1
end

---------------------------------------------------------------------------
-- Floating origin
---------------------------------------------------------------------------
-- Ask for the origin to move so that `robloxPos` ends up near (0, 0, 0).
function ChunkManager:requestRebase(robloxPos: Vector3)
	if self.pendingRebase or self.rebasing then
		return
	end
	local size = self.size
	local delta = Vector3.new(floor(robloxPos.X / size) * size, 0, floor(robloxPos.Z / size) * size)
	self.pendingRebase = self.origin + delta
end

function ChunkManager:_rebase(newOrigin: Vector3)
	self.rebasing = true
	local terrain = self.terrain
	local old = self.origin
	local delta = newOrigin - old
	local dvx, dvz = delta.X // 4, delta.Z // 4

	-- 1. copy terrain to its new place (far from the car, so out of sight)
	local copied = {}
	for k, rec in self.chunks do
		if rec.data then
			local region = self.terrainBuilder:voxelRegion(rec.data, old)
			local ok, tr = pcall(function()
				return terrain:CopyRegion(region)
			end)
			if ok and tr then
				local m = region.Min
				local okPaste = pcall(function()
					terrain:PasteRegion(tr, Vector3int16.new(m.X - dvx, m.Y, m.Z - dvz), true)
				end)
				copied[k] = okPaste
			end
			self:_yield()
		end
	end

	-- 2. switch in one go: parts, origin, car/camera
	local parts, cframes = {}, {}
	for _, d in self.container:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(cframes, d.CFrame - delta)
		end
	end
	Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	self.origin = newOrigin
	self.focus = self.focus -- focus is in world coordinates, unchanged
	if self.onRebase then
		self.onRebase(delta)
	end
	self.stats.rebases += 1

	-- 3. clear the old terrain; anything that failed to copy gets rebuilt
	for k, rec in self.chunks do
		if rec.data then
			self.terrainBuilder:clear(rec.data, old)
			if not copied[k] then
				if rec.road then
					rec.road:Destroy()
				end
				self.chunks[k] = nil
			end
			self:_yield()
		end
	end
	self.rebasing = false
end

---------------------------------------------------------------------------
-- Loading progress
---------------------------------------------------------------------------
-- Fraction of chunks within `radius` of the focus that are fully built
-- (terrain, road and near decoration where due).
function ChunkManager:progress(radius: number): number
	if not self.wantedFocus then
		self:_refreshWanted()
	end
	local total, done = 0, 0
	for _, w in self.wanted do
		if w.dist <= radius then
			total += 1
			local rec = self.chunks[w.key]
			if rec and (rec.failed or (rec.data and rec.decorLevel == self:_decorLevelFor(w.dist))) then
				done += 1
			end
		end
	end
	if total == 0 then
		return 1
	end
	return done / total
end

function ChunkManager:loadedCount(): number
	local n = 0
	for _ in self.chunks do
		n += 1
	end
	return n
end

return ChunkManager
