--[[
	Compiles every Luau file in src/ (without running it) and checks the
	built place file's hierarchy and settings.
	  lune run tools/check_syntax
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local process = require("@lune/process")

local failures = 0
local function walk(dir)
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif path:match("%.luau$") then
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failures += 1
				print("SYNTAX ERROR " .. path .. ": " .. tostring(err))
			end
		end
	end
end
walk("src")

if fs.isFile("InfiniteScenicRoad.rbxl") then
	local game = roblox.deserializePlace(fs.readFile("InfiniteScenicRoad.rbxl"))
	local function need(cond, msg)
		if not cond then
			failures += 1
			print("PLACE: " .. msg)
		end
	end
	local ws = game:GetService("Workspace")
	need(ws.StreamingEnabled == false, "StreamingEnabled must be false")
	local shared = game:GetService("ReplicatedStorage"):FindFirstChild("InfiniteRoad")
	need(shared and shared:FindFirstChild("RoadPath") and shared.RoadPath.ClassName == "ModuleScript", "shared modules missing")
	local client = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	client = client and client:FindFirstChild("InfiniteRoadClient")
	need(client and client.ClassName == "LocalScript", "client LocalScript missing")
	need(client and client:FindFirstChild("ChunkManager"), "client modules missing")
	local server = game:GetService("ServerScriptService"):FindFirstChild("InfiniteRoadServer")
	need(server and server.ClassName == "Script", "server Script missing")
	need(ws:FindFirstChild("SpawnPlate"), "spawn plate missing")
	local assetRoot = game:GetService("ReplicatedStorage"):FindFirstChild("InfiniteRoadAssets")
	local trees = assetRoot and assetRoot:FindFirstChild("Trees")
	need(trees and trees:FindFirstChild("Pine"), "asset folders missing")
	local carSlot = assetRoot and assetRoot:FindFirstChild("Car")
	need(carSlot and carSlot:FindFirstChild("Body"), "car asset slot missing")
	local bikeSlot = assetRoot and assetRoot:FindFirstChild("Motorcycle")
	need(bikeSlot and bikeSlot:FindFirstChild("Body"), "motorcycle asset slot missing")
	local worker = client and client:FindFirstChild("GenWorker")
	need(worker and worker.ClassName == "Actor", "GenWorker must be an Actor")
	local workerScript = worker and worker:FindFirstChild("Worker")
	need(workerScript and workerScript.ClassName == "LocalScript", "GenWorker needs its Worker LocalScript")
	local ui = client and client:FindFirstChild("UI")
	need(ui and ui:FindFirstChild("App") and ui:FindFirstChild("Kit"), "UI modules missing")
	for _, name in { "Weather", "Seasons", "Environment", "Motorcycle", "WorkerPool", "Quality", "SettingsMenu", "Vehicles", "Waterfalls", "SoundUtil", "Ambience" } do
		local m = client and client:FindFirstChild(name)
		need(m and m.ClassName == "ModuleScript", name .. " module missing")
	end
	print("place file checked")
end

if failures > 0 then
	print(failures .. " FAILURES")
	process.exit(1)
end
print("ALL FILES COMPILE")
