--[[
	Hud
	---
	The driving overlay, in the same style as the rest of the interface:
	loading screen, trip panel (distance plus season, weather and time),
	speedometer with an autodrive badge, region banner, toasts and the stats
	overlay. Controls live in the toolbar (UI/App.luau), not here.
]]

local Players = game:GetService("Players")

local Theme = require(script.Parent.UI.Theme)
local Kit = require(script.Parent.UI.Kit)

local Hud = {}
Hud.__index = Hud

local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right
local MPH = 0.621371

-- parent: where the ScreenGuis go (defaults to the local PlayerGui)
function Hud.new(seed: number, parent: Instance?)
	local self = setmetatable({}, Hud)
	local target = parent or Players.LocalPlayer:WaitForChild("PlayerGui")
	local touch = Kit.device().touch
	local m = Theme.Margin
	self.units = "km/h"

	local gui, root = Kit.screen(target, "InfiniteRoadHud", 1)
	self.gui, self.root = gui, root
	root.Visible = false -- shown when the drive starts

	-- trip: distance, then season / weather / time (top left)
	local trip = Kit.panel(root, {
		Name = "Trip",
		Position = UDim2.fromOffset(m, m),
		Size = UDim2.fromOffset(0, 56),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	Kit.padding(trip, 8, 16)
	Kit.list(trip, false, 2)
	self.distanceText = Kit.text(trip, {
		Name = "Distance",
		Text = "0.0 km",
		Font = Theme.FontBold,
		TextSize = 20,
		TextXAlignment = LEFT,
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 1,
	})
	self.infoText = Kit.text(trip, {
		Name = "Info",
		Font = Theme.FontLight,
		TextSize = 13,
		TextColor3 = Theme.TextDim,
		TextXAlignment = LEFT,
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = 2,
	})

	-- stats overlay (below the trip panel)
	self.statsPanel = Kit.panel(root, {
		Name = "Stats",
		Position = UDim2.fromOffset(m, m + 64),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
	})
	Kit.padding(self.statsPanel, 10, 14)
	self.statsText = Kit.text(self.statsPanel, {
		Name = "Text",
		Font = Theme.FontMono,
		TextSize = 12,
		TextColor3 = Theme.Text,
		TextXAlignment = LEFT,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.XY,
	})

	-- speedometer: bottom right, or top right on touch screens, where the
	-- pedals take the bottom corners
	self.speedPanel = Kit.panel(root, {
		Name = "Speedometer",
		AnchorPoint = Vector2.new(1, touch and 0 or 1),
		Position = touch and UDim2.new(1, -m, 0, m) or UDim2.new(1, -m, 1, -m),
		Size = UDim2.fromOffset(150, 76),
	})
	Kit.padding(self.speedPanel, 6, 16)
	self.speedText = Kit.text(self.speedPanel, {
		Name = "Speed",
		Text = "0",
		Font = Theme.FontBold,
		TextSize = 44,
		TextXAlignment = RIGHT,
		Size = UDim2.new(1, 0, 0, 46),
	})
	self.unitText = Kit.text(self.speedPanel, {
		Name = "Unit",
		Text = "km/h",
		Font = Theme.FontLight,
		TextSize = 13,
		TextColor3 = Theme.TextDim,
		TextXAlignment = RIGHT,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 16),
	})
	-- autodrive badge, just outside the speedometer
	self.badgeFrame = Kit.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, touch and 0 or 1),
		Position = touch and UDim2.new(1, 16, 1, 14) or UDim2.new(1, 16, 0, -14),
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Visible = false,
		Parent = self.speedPanel,
	})
	Kit.round(self.badgeFrame)
	Kit.padding(self.badgeFrame, 0, 12)
	self.badgeText = Kit.text(self.badgeFrame, {
		Name = "Text",
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.OnAccent,
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
	})

	-- region banner (top centre)
	local region = Kit.new("Frame", {
		Name = "Region",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, m + 4),
		Size = UDim2.fromOffset(700, 78),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	self.regionFrame = region
	self.regionText = Kit.text(region, {
		Name = "Name",
		Font = Theme.FontBold,
		TextSize = 34,
		TextStrokeTransparency = 0.8,
		Size = UDim2.new(1, 0, 0, 40),
	})
	local bar = Kit.new("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 46),
		Size = UDim2.fromOffset(36, 3),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = region,
	})
	Kit.round(bar)
	self.regionSubText = Kit.text(region, {
		Name = "Subtitle",
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = Theme.Text,
		TextStrokeTransparency = 0.85,
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.new(1, 0, 0, 18),
	})

	-- toasts (just above the toolbar)
	self.toastFrame = Kit.panel(root, {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.ToolbarReserve),
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
	})
	Kit.padding(self.toastFrame, 0, 18)
	self.toastText = Kit.text(self.toastFrame, {
		Name = "Text",
		TextSize = 15,
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
	})

	self:_buildLoading(target, seed)
	return self
end

function Hud:_buildLoading(parent: Instance, seed: number)
	local gui, root = Kit.screen(parent, "InfiniteRoadLoading", 20, true)
	self.loadingGui = gui
	local loading = Kit.new("Frame", {
		Name = "Loading",
		BackgroundColor3 = Theme.Backdrop,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	self.loading = loading
	local center = Kit.new("Frame", {
		Name = "Center",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(600, 150),
		BackgroundTransparency = 1,
		Parent = loading,
	})
	local accent = Kit.new("Frame", {
		Name = "Accent",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(36, 4),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = center,
	})
	Kit.round(accent)
	Kit.text(center, {
		Name = "Title",
		Text = "INFINITE SCENIC ROAD",
		Font = Theme.FontBold,
		TextSize = 40,
		Position = UDim2.fromOffset(0, 16),
		Size = UDim2.new(1, 0, 0, 46),
	})
	Kit.text(center, {
		Name = "Subtitle",
		Text = "Generating your road  ·  seed " .. tostring(seed),
		Font = Theme.FontLight,
		TextSize = 15,
		TextColor3 = Theme.TextDim,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 20),
	})
	local track = Kit.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(360, 6),
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		Parent = center,
	})
	Kit.round(track)
	self.bar = Kit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	Kit.round(self.bar)
	self.percentText = Kit.text(center, {
		Name = "Percent",
		Text = "0%",
		Font = Theme.Font,
		TextSize = 13,
		TextColor3 = Theme.TextDim,
		Position = UDim2.fromOffset(0, 124),
		Size = UDim2.new(1, 0, 0, 18),
	})
end

function Hud:setProgress(fraction: number)
	local f = math.clamp(fraction, 0, 1)
	self.bar.Size = UDim2.fromScale(f, 1)
	self.percentText.Text = string.format("%d%%", math.floor(f * 100))
end

-- Fade the loading screen out (the start screen is ready behind it).
function Hud:finishLoading()
	Kit.fade(self.loading, false, 0.9)
	task.delay(1, function()
		if self.loadingGui then
			self.loadingGui:Destroy()
			self.loadingGui = nil
		end
	end)
end

function Hud:setVisible(on: boolean)
	self.root.Visible = on
end

function Hud:setUnits(units: string)
	self.units = units
	self.unitText.Text = units
end

function Hud:setSpeedometer(on: boolean)
	self.speedPanel.Visible = on
end

function Hud:update(speed: number, distanceStuds: number)
	-- 1 stud ~ 0.28 m, so studs/s ~ km/h. Only touch the labels when the
	-- text changes (setting Text re-lays out the label).
	local kmh = math.abs(speed) * 1.008
	local km = distanceStuds * 0.00028
	local sp, dist
	if self.units == "mph" then
		sp, dist = tostring(math.floor(kmh * MPH + 0.5)), string.format("%.1f mi", km * MPH)
	else
		sp, dist = tostring(math.floor(kmh + 0.5)), string.format("%.1f km", km)
	end
	if sp ~= self.speedText.Text then
		self.speedText.Text = sp
	end
	if dist ~= self.distanceText.Text then
		self.distanceText.Text = dist
	end
end

-- Small line under the distance (season, weather, time).
function Hud:setInfo(text: string)
	if self.infoText.Text ~= text then
		self.infoText.Text = text
	end
end

-- Stats overlay text; nil hides it.
function Hud:setStats(text: string?)
	self.statsPanel.Visible = text ~= nil
	if text and text ~= "" then
		self.statsText.Text = text
	end
end

-- Pill beside the speedometer ("" hides it).
function Hud:setBadge(text: string)
	if self.badgeText.Text ~= text then
		self.badgeText.Text = text
		self.badgeFrame.Visible = text ~= ""
	end
end

function Hud:showRegion(name: string, subtitle: string)
	self.regionText.Text = name
	self.regionSubText.Text = string.upper(subtitle)
	local frame = self.regionFrame
	frame.Position = UDim2.new(0.5, 0, 0, Theme.Margin - 6)
	Kit.tween(frame, { Position = UDim2.new(0.5, 0, 0, Theme.Margin + 4) }, 1.2)
	Kit.fade(frame, true, 1.2)
	local token = {}
	self.regionToken = token
	task.delay(5, function()
		if self.regionToken == token then
			Kit.fade(frame, false, 1.6)
		end
	end)
end

function Hud:toast(text: string)
	self.toastText.Text = text
	local frame = self.toastFrame
	if not frame.Visible then
		frame.Position = UDim2.new(0.5, 0, 1, -Theme.ToolbarReserve + 8)
	end
	Kit.tween(frame, { Position = UDim2.new(0.5, 0, 1, -Theme.ToolbarReserve) }, Theme.Normal)
	Kit.fade(frame, true, Theme.Normal)
	local token = {}
	self.toastToken = token
	task.delay(1.8, function()
		if self.toastToken == token then
			Kit.fade(frame, false, 0.5)
		end
	end)
end

return Hud
