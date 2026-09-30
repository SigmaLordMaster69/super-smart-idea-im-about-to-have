--[[
	Worker (runs inside a GenWorker Actor)
	------
	Builds chunk terrain off the main thread. Each worker keeps its own copy
	of the world (same seed, so identical results), samples the height model
	in parallel in short slices, then writes the voxels in the serial phase.

	Messages from WorkerPool:
	  Init(seed, resultEvent, terrainBuilderModule, season)
	  Season(season)
	  Build(jobId, cx, cz, originX, originZ)
	Replies through resultEvent:
	  ("ready", workerId)  ("done", jobId, data)  ("error", jobId, message)
]]

local actor = script:GetActor()
if not actor then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("InfiniteRoad")
local Config = require(Shared.Config)
local World = require(Shared.World)

local SLICE = 0.004 -- seconds of parallel work before giving the frame back

local builder, resultEvent

actor:BindToMessage("Init", function(seed, event, builderModule, season, workerId)
	if builder then
		-- a repeated Init (the pool resends until it hears back)
		event:Fire("ready", workerId)
		return
	end
	local TerrainBuilder = require(builderModule)
	builder = TerrainBuilder.new(World.new(Config, seed), Config, Workspace.Terrain)
	builder:setSeason(season)
	resultEvent = event
	event:Fire("ready", workerId)
end)

actor:BindToMessage("Season", function(season)
	if builder then
		builder:setSeason(season)
	end
end)

actor:BindToMessageParallel("Build", function(jobId, cx, cz, originX, originZ)
	if not builder then
		return
	end
	local deadline = os.clock() + SLICE
	local function yieldFn()
		if os.clock() > deadline then
			task.wait()
			pcall(task.desynchronize)
			deadline = os.clock() + SLICE
		end
	end
	local ok, job = pcall(builder.compute, builder, cx, cz, Vector3.new(originX, 0, originZ), yieldFn)
	task.synchronize()
	if not ok then
		resultEvent:Fire("error", jobId, tostring(job))
		return
	end
	-- one voxel piece per frame, so several workers finishing together do
	-- not stack their writes into one long frame
	local okWrite, err = pcall(builder.write, builder, job, task.wait)
	builder:release(job)
	if not okWrite then
		resultEvent:Fire("error", jobId, tostring(err))
		return
	end
	resultEvent:Fire("done", jobId, job.data)
end)
