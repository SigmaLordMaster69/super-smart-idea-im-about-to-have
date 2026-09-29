--[[
	InfiniteRoadServer
	------------------
	The world is generated on each client, so the server only:
	  * picks the seed everyone on this server shares,
	  * keeps a "km driven" leaderboard.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("InfiniteRoad")
local Config = require(Shared.Config)

local seed = Config.Seed
if seed == 0 then
	seed = Random.new():NextInteger(1, 2147483646)
end
Shared:SetAttribute("Seed", seed)
print("[InfiniteRoad] seed", seed)

local report = Instance.new("RemoteEvent")
report.Name = "ReportDistance"
report.Parent = Shared

local lastReport = {}

Players.PlayerAdded:Connect(function(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local km = Instance.new("NumberValue")
	km.Name = "km"
	km.Parent = stats
	stats.Parent = player
	lastReport[player] = os.clock()
end)

Players.PlayerRemoving:Connect(function(player)
	lastReport[player] = nil
end)

-- Clients report their total distance. Clamp it to something a car could
-- actually have driven since the last report.
report.OnServerEvent:Connect(function(player, value)
	if typeof(value) ~= "number" or value ~= value then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	local km = stats and stats:FindFirstChild("km")
	if not km then
		return
	end
	local now = os.clock()
	local last = lastReport[player] or now
	lastReport[player] = now
	local maxGain = (now - last) * 0.06 + 0.02 -- ~215 km/h
	km.Value = math.floor(math.clamp(value, km.Value, km.Value + maxGain) * 10 + 0.5) / 10
end)
