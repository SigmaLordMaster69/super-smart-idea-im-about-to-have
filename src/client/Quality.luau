--[[
	Quality
	-------
	Picks a quality preset (Config.Quality) for this device. Touch devices
	start on Low; otherwise the player's graphics quality slider decides.
]]

local UserInputService = game:GetService("UserInputService")

local Quality = {}

function Quality.auto(config): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Low"
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if not ok or level == nil or level == Enum.SavedQualitySetting.Automatic then
		return "High"
	end
	local n = tonumber(string.match(level.Name, "%d+")) or 6
	if n <= 3 then
		return "Low"
	elseif n <= 6 then
		return "Medium"
	elseif n <= 8 then
		return "High"
	end
	return "Ultra"
end

-- The preset table for a name ("Auto" resolves to a real preset).
function Quality.get(config, name: string)
	if name == "Auto" or not config.Quality[name] then
		name = Quality.auto(config)
	end
	return config.Quality[name], name
end

-- Next preset name in the cycle.
function Quality.next(config, name: string): string
	local order = config.Quality.Order
	for i, n in order do
		if n == name then
			return order[i % #order + 1]
		end
	end
	return order[1]
end

return Quality
