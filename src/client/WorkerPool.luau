--[[
	WorkerPool
	----------
	Runs chunk terrain builds on GenWorker Actors (Parallel Luau), so the
	expensive sampling happens on other CPU cores.

	The pool is optional and fails safe: if the workers do not report ready,
	take too long, or keep erroring, `broken` is set and ChunkManager builds
	everything on the main thread as before.
]]

local WorkerPool = {}
WorkerPool.__index = WorkerPool

local READY_TIMEOUT = 6 -- seconds to wait for workers to start
local INIT_RETRY = 1 -- resend Init to workers that have not answered yet
local JOB_TIMEOUT = 12 -- a job taking longer than this breaks the pool
local MAX_ERRORS = 3

function WorkerPool.new(template: Actor, count: number, seed: number, builderModule: ModuleScript, season, parent: Instance)
	local self = setmetatable({}, WorkerPool)
	self.workers = {}
	self.freeList = {}
	self.jobs = {} -- jobId -> { worker, key, started }
	self.results = {}
	self.nextJob = 0
	self.errors = 0
	self.broken = false
	self.readyCount = 0
	self.created = os.clock()
	self.season = season
	self.seed = seed
	self.builderModule = builderModule
	self.lastInit = math.huge

	local event = Instance.new("BindableEvent")
	event.Name = "GenWorkerResults"
	event.Parent = parent
	self.event = event
	event.Event:Connect(function(kind, a, b)
		if kind == "ready" then
			local w = self.workers[a]
			if w and not w.ready then
				w.ready = true
				self.readyCount += 1
				-- the season may have changed while the worker was starting
				w.actor:SendMessage("Season", self.season)
				table.insert(self.freeList, w)
			end
		elseif kind == "done" or kind == "error" then
			local job = self.jobs[a]
			if not job then
				return
			end
			self.jobs[a] = nil
			table.insert(self.freeList, job.worker)
			if kind == "error" then
				self.errors += 1
				warn("[InfiniteRoad] worker job failed: " .. tostring(b))
				if self.errors >= MAX_ERRORS then
					self:_break("too many worker errors")
				end
			end
			table.insert(self.results, { jobId = a, key = job.key, ok = kind == "done", data = kind == "done" and b or nil })
		end
	end)

	for i = 1, count do
		local actor = i == 1 and template or template:Clone()
		actor.Name = "GenWorker" .. i
		if actor.Parent ~= parent then
			actor.Parent = parent
		end
		self.workers[i] = { actor = actor, id = i, ready = false }
	end
	-- the worker scripts need a moment to start and bind their messages;
	-- free() resends Init until every worker has answered
	task.delay(0.2, function()
		self:_init()
	end)
	return self
end

function WorkerPool:_init()
	self.lastInit = os.clock()
	for _, w in self.workers do
		if not w.ready then
			w.actor:SendMessage("Init", self.seed, self.event, self.builderModule, self.season, w.id)
		end
	end
end

function WorkerPool:_break(reason: string)
	if not self.broken then
		self.broken = true
		warn("[InfiniteRoad] parallel generation disabled (" .. reason .. "), building on the main thread")
	end
end

-- Number of workers ready for a new job right now.
function WorkerPool:free(): number
	if self.broken then
		return 0
	end
	local now = os.clock()
	if self.readyCount < #self.workers and now - self.lastInit > INIT_RETRY then
		if self.readyCount == 0 and now - self.created > READY_TIMEOUT then
			self:_break("workers did not start")
			return 0
		end
		self:_init()
	end
	return #self.freeList
end

function WorkerPool:inflight(): number
	local n = 0
	for _ in self.jobs do
		n += 1
	end
	return n
end

function WorkerPool:dispatch(key: number, cx: number, cz: number, origin: Vector3): number
	local w = table.remove(self.freeList)
	self.nextJob += 1
	local id = self.nextJob
	self.jobs[id] = { worker = w, key = key, started = os.clock() }
	w.actor:SendMessage("Build", id, cx, cz, origin.X, origin.Z)
	return id
end

-- Finished jobs since the last call, plus jobs abandoned by a timeout
-- (returned as failures so the caller rebuilds them locally).
function WorkerPool:poll()
	local now = os.clock()
	for id, job in self.jobs do
		if now - job.started > JOB_TIMEOUT then
			self.jobs[id] = nil
			self:_break("a job timed out")
			table.insert(self.results, { jobId = id, key = job.key, ok = false })
		end
	end
	local out = self.results
	self.results = {}
	return out
end

function WorkerPool:setSeason(season)
	self.season = season
	for _, w in self.workers do
		if w.ready then
			w.actor:SendMessage("Season", season)
		end
	end
end

return WorkerPool
