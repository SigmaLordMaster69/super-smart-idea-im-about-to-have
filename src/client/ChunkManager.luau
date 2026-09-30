--[[
	ChunkManager
	------------
	Streams the world around the car in square chunks.

	All generation is driven by one worker coroutine that is resumed every
	frame with a time budget; long jobs check the budget and yield, so
	building never causes a big frame spike. The budget adapts: it shrinks
	when the frame rate drops and grows when there is work waiting and
	frames are fast.

	Terrain can be built on parallel GenWorker actors (WorkerPool). Then the
	main thread only builds road parts and decoration. Without a pool, or if
	it breaks, terrain is built here as before.

	Jobs, in priority order:
	  1. rebase (floating origin), once no worker jobs are in flight
	  2. finish terrain that workers have written (build road parts)
	  3. unload chunks that are too far away
	  4. build terrain + road for missing chunks, nearest and most ahead first
	  5. bring decoration detail (none / far / near) up to date
	  6. rebuild stale terrain after a season change

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
local Waterfalls = require(script.Parent.Waterfalls)

local floor, sqrt, max, min, clamp = math.floor, math.sqrt, math.max, math.min, math.clamp

local ChunkManager = {}
ChunkManager.__index = ChunkManager

local function key(cx: number, cz: number): number
	return cx * 131072 + cz
end

function ChunkManager.new(world, config, terrain, assets, pool)
	local self = setmetatable({}, ChunkManager)
	self.world = world
	self.config = config
	self.terrain = terrain
	self.size = config.World.ChunkSize
	self.pool = pool

	local container = Instance.new("Folder")
	container.Name = "InfiniteRoadWorld"
	container.Parent = Workspace
	self.container = container

	self.props = Props.new(assets)
	self.terrainBuilder = TerrainBuilder.new(world, config, terrain)
	self.roadBuilder = RoadBuilder.new(world, config, self.props)
	self.decorator = Decorator.new(world, config, self.props)

	self.chunks = {}
	self.finished = {} -- worker results waiting to be finished
	self.origin = Vector3.zero
	self.focus = Vector3.zero
	self.forward = Vector3.new(1, 0, 0)
	self.wanted = {}
	self.wantedFocus = nil
	self.wantedTime = 0
	self.deadline = 0
	self.pendingRebase = nil
	self.lastWork = 0
	self.budget = config.World.FrameBudget
	self.avgDt = 1 / 60
	self.onRebase = nil -- function(delta: Vector3)
	self.stats = { built = 0, unloaded = 0, decorated = 0, rebases = 0, parallel = 0, refreshed = 0, waterfalls = 0 }
	self:setQuality({
		TerrainRadius = config.World.TerrainRadius,
		NearDecorRadius = config.World.NearDecorRadius,
		FarDecorRadius = config.World.FarDecorRadius,
		BudgetMin = config.World.FrameBudget * 0.4,
		BudgetMax = config.World.FrameBudget * 1.6,
	})
	self:_newWorker()
	return self
end

-- Quality preset: radii and frame budget limits (see Config.Quality).
function ChunkManager:setQuality(q)
	self.quality = q
	self.budget = clamp(self.budget, q.BudgetMin, q.BudgetMax)
	self.wantedFocus = nil
end

-- Terrain season flags (snow ground, frozen water). Loaded chunks are
-- rebuilt in the background, nearest first.
function ChunkManager:setSeason(season)
	self.frozen = season and season.frozen or false
	self.terrainBuilder:setSeason(season)
	if self.pool then
		self.pool:setSeason(season)
	end
	for _, rec in self.chunks do
		if rec.data then
			rec.stale = true
		end
	end
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

-- Focus point in world coordinates (usually car position + velocity lead)
-- and the direction of travel, which gets loading priority.
function ChunkManager:setFocus(worldPos: Vector3, forward: Vector3?)
	self.focus = worldPos
	if forward then
		local flat = Vector3.new(forward.X, 0, forward.Z)
		if flat.Magnitude > 0.01 then
			self.forward = flat.Unit
		end
	end
end

---------------------------------------------------------------------------
-- Worker coroutine
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

-- Per-frame update with an adaptive budget. `dt` is the last frame time.
function ChunkManager:step(dt: number)
	local q = self.quality
	self.avgDt += (dt - self.avgDt) * 0.1
	local busy = self:pendingCount() > 0
	if self.avgDt > 1 / 50 then
		self.budget = max(q.BudgetMin, self.budget * 0.92)
	elseif busy and self.avgDt < 1 / 58 then
		self.budget = min(q.BudgetMax, self.budget * 1.04)
	end
	self:update(self.budget)
end

function ChunkManager:_refreshWanted()
	local size = self.size
	local f = self.focus
	local fwd = self.forward
	local radius = self.quality.TerrainRadius
	local r = math.ceil(radius / size)
	local fcx, fcz = floor(f.X / size), floor(f.Z / size)
	local list = {}
	for dz = -r, r do
		for dx = -r, r do
			local cx, cz = fcx + dx, fcz + dz
			local mx, mz = (cx + 0.5) * size - f.X, (cz + 0.5) * size - f.Z
			local dist = sqrt(mx * mx + mz * mz)
			if dist <= radius then
				-- chunks behind the car count as up to twice as far
				local ahead = dist > 1 and (mx * fwd.X + mz * fwd.Z) / dist or 1
				table.insert(list, { cx = cx, cz = cz, dist = dist, score = dist * (1.5 - 0.5 * ahead), key = key(cx, cz) })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.score < b.score
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

-- Decoration detail with hysteresis, so chunks near a boundary do not
-- flip back and forth as the car moves.
function ChunkManager:_decorLevelFor(dist: number, current: number?): number
	local q = self.quality
	local near, far = q.NearDecorRadius, q.FarDecorRadius
	if current == 2 then
		near *= 1.18
	end
	if current and current >= 1 then
		far *= 1.08
	end
	if dist <= near then
		return 2
	elseif dist <= far then
		return 1
	end
	return 0
end

function ChunkManager:_nextJob()
	local pool = self.pool
	local usePool = pool and not pool.broken

	if usePool then
		for _, r in pool:poll() do
			table.insert(self.finished, r)
		end
	end

	-- finished worker results are applied first: their voxels were written
	-- at the old origin and must be moved along with the rest
	if self.pendingRebase and #self.finished == 0 and (not usePool or pool:inflight() == 0) then
		local target = self.pendingRebase
		self.pendingRebase = nil
		return function()
			self:_rebase(target)
		end
	end

	local done = table.remove(self.finished, 1)
	if done then
		return function()
			self:_finish(done)
		end
	end

	if not self.wantedFocus or (self.wantedFocus - self.focus).Magnitude > 24 or os.clock() - self.wantedTime > 1 then
		self:_refreshWanted()
	end

	-- unload
	local limit = self.quality.TerrainRadius + self.config.World.UnloadMargin
	for k, rec in self.chunks do
		if rec.jobId == nil and (rec.data or rec.failed) and self:_distanceTo(rec) > limit then
			return function()
				self:_unload(k)
			end
		end
	end

	-- no new terrain while a rebase waits for workers to finish
	local canDispatch = usePool and self.pendingRebase == nil and pool:free() > 0

	-- nearest first: build missing chunks, and bring decoration up to the
	-- detail its distance calls for. Near detail is worth doing before
	-- building far-away terrain; far detail waits until terrain is done.
	local farDecor, staleJob
	for _, w in self.wanted do
		local rec = self.chunks[w.key]
		if not rec then
			if canDispatch then
				return function()
					self:_dispatch(w.cx, w.cz, w.key)
				end
			elseif not usePool and self.pendingRebase == nil then
				return function()
					self:_build(w.cx, w.cz, w.key)
				end
			end
		elseif rec.data and not rec.failed then
			local level = self:_decorLevelFor(w.dist, rec.decorLevel)
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
			if rec.stale and rec.jobId == nil and not staleJob then
				staleJob = rec
			end
		end
	end
	if farDecor then
		return farDecor
	end
	if staleJob and self.pendingRebase == nil then
		if canDispatch then
			return function()
				self:_dispatch(staleJob.cx, staleJob.cz, key(staleJob.cx, staleJob.cz))
			end
		elseif not usePool then
			return function()
				self:_refresh(staleJob)
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------
-- Terrain for a new chunk, or a stale one, on a parallel worker.
function ChunkManager:_dispatch(cx: number, cz: number, k: number)
	local rec = self.chunks[k]
	if not rec then
		rec = { cx = cx, cz = cz, decorLevel = 0 }
		self.chunks[k] = rec
	end
	rec.stale = nil
	rec.jobId = self.pool:dispatch(k, cx, cz, self.origin)
	self.stats.parallel += 1
end

-- A worker finished (or gave up on) a terrain job.
function ChunkManager:_finish(result)
	local rec = self.chunks[result.key]
	if not rec or rec.jobId ~= result.jobId then
		-- the chunk was unloaded meanwhile: remove what the worker wrote
		if result.ok and not rec then
			self.terrainBuilder:clear(result.data, self.origin)
		end
		return
	end
	rec.jobId = nil
	if not result.ok then
		-- rebuild it here instead
		if rec.data then
			self:_refresh(rec)
		else
			self.chunks[result.key] = nil
			self:_build(rec.cx, rec.cz, result.key)
		end
		return
	end
	local fresh = rec.data == nil
	rec.data = result.data
	if fresh then
		self:_buildRoad(rec)
		self.stats.built += 1
	else
		if rec.road then
			self:_buildFalls(rec)
		end
		self.stats.refreshed += 1
	end
end

function ChunkManager:_buildRoad(rec)
	local folder = Instance.new("Folder")
	folder.Name = string.format("Chunk_%d_%d", rec.cx, rec.cz)
	rec.road = folder
	local ok, err = pcall(function()
		self.roadBuilder:build(rec.data.x0, rec.data.z0, self.size, self.origin, folder)
	end)
	if not ok then
		warn(string.format("[InfiniteRoad] road for chunk %d,%d failed: %s", rec.cx, rec.cz, tostring(err)))
	end
	self:_buildFalls(rec)
	folder.Parent = self.container
end

-- Waterfalls (or icefalls in winter) where water runs off an edge.
function ChunkManager:_buildFalls(rec)
	if rec.falls then
		rec.falls:Destroy()
		rec.falls = nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Falls"
	local ok, count = pcall(Waterfalls.build, rec.data, self.world.sampler, self.origin, folder, self.frozen, self.config.Sounds)
	if ok and count > 0 then
		folder.Parent = rec.road
		rec.falls = folder
		self.stats.waterfalls += count
	else
		if not ok then
			warn(string.format("[InfiniteRoad] waterfalls for chunk %d,%d failed: %s", rec.cx, rec.cz, tostring(count)))
		end
		folder:Destroy()
	end
end

-- Terrain + road on this thread (no worker pool).
function ChunkManager:_build(cx: number, cz: number, k: number)
	local rec = { cx = cx, cz = cz, decorLevel = 0 }
	self.chunks[k] = rec
	local ok, err = pcall(function()
		rec.data = self.terrainBuilder:build(cx, cz, self.origin, self.yieldFn)
	end)
	if not ok then
		-- keep the record so the chunk is not retried every frame; it is
		-- dropped (and may be retried) once the car moves away
		rec.failed = true
		warn(string.format("[InfiniteRoad] chunk %d,%d failed: %s", cx, cz, tostring(err)))
		return
	end
	self:_buildRoad(rec)
	self.stats.built += 1
end

-- Rebuild a loaded chunk's terrain on this thread (season change).
function ChunkManager:_refresh(rec)
	rec.stale = nil
	local ok, data = pcall(function()
		return self.terrainBuilder:build(rec.cx, rec.cz, self.origin, self.yieldFn)
	end)
	if ok and self.chunks[key(rec.cx, rec.cz)] == rec then
		rec.data = data
		if rec.road then
			self:_buildFalls(rec)
		end
		self.stats.refreshed += 1
	end
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
-- Status
---------------------------------------------------------------------------
-- Fraction of chunks within `radius` of the focus that are fully built
-- (terrain, road and the decoration detail due at their distance).
function ChunkManager:progress(radius: number): number
	if not self.wantedFocus then
		self:_refreshWanted()
	end
	local total, done = 0, 0
	for _, w in self.wanted do
		if w.dist <= radius then
			total += 1
			local rec = self.chunks[w.key]
			if rec and (rec.failed or (rec.data and rec.jobId == nil and rec.decorLevel == self:_decorLevelFor(w.dist, rec.decorLevel))) then
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

-- Wanted chunks that are not built yet.
function ChunkManager:pendingCount(): number
	local n = 0
	for _, w in self.wanted do
		local rec = self.chunks[w.key]
		if not rec or not rec.data then
			n += 1
		end
	end
	return n
end

-- Rebuild every chunk's decoration (season or quality changed). Runs in
-- the background, nearest chunks first.
function ChunkManager:redecorate()
	for _, rec in self.chunks do
		if rec.data then
			rec.decorLevel = -1
		end
	end
end

-- Visit every loaded chunk's parts (for weather/season updates).
function ChunkManager:forEachChunk(fn)
	for _, rec in self.chunks do
		if rec.road then
			fn(rec)
		end
	end
end

return ChunkManager
