--[[
	Hud
	---
	Minimal slowroads-style overlay: loading screen, speed, distance,
	region banner, autodrive badge, control hints and short toasts.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Hud = {}
Hud.__index = Hud

local rgb = Color3.fromRGB
local FONT = Enum.Font.GothamBold
local FONT_LIGHT = Enum.Font.Gotham

local function label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = FONT
	l.TextStrokeTransparency = 0.7
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	for k, v in props do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function Hud.new(seed: number)
	local self = setmetatable({}, Hud)
	local gui = Instance.new("ScreenGui")
	gui.Name = "InfiniteRoadHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	-- driving HUD
	local root = Instance.new("Frame")
	root.Name = "Drive"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	self.root = root

	self.speed = label(root, {
		Name = "Speed",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -40),
		Size = UDim2.fromOffset(220, 60),
		TextSize = 54,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0",
	})
	label(root, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -30, 1, -22),
		Size = UDim2.fromOffset(220, 20),
		TextSize = 16,
		Font = FONT_LIGHT,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "km/h",
		TextTransparency = 0.2,
	})
	self.distance = label(root, {
		Name = "Distance",
		Position = UDim2.fromOffset(28, 26),
		Size = UDim2.fromOffset(400, 22),
		TextSize = 18,
		Font = FONT_LIGHT,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "0.0 km",
	})
	self.info = label(root, {
		Name = "Info",
		Position = UDim2.fromOffset(28, 48),
		Size = UDim2.fromOffset(400, 18),
		TextSize = 14,
		Font = FONT_LIGHT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 0.25,
		Text = "",
	})
	self.region = label(root, {
		Name = "Region",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(700, 48),
		TextSize = 40,
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	self.regionSub = label(root, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 118),
		Size = UDim2.fromOffset(700, 22),
		TextSize = 18,
		Font = FONT_LIGHT,
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	self.badge = label(root, {
		Name = "Badge",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -102),
		Size = UDim2.fromOffset(260, 22),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = rgb(150, 230, 170),
		Text = "",
	})
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	self.hints = label(root, {
		Name = "Hints",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 28, 1, -22),
		Size = UDim2.fromOffset(700, 40),
		TextSize = 14,
		Font = FONT_LIGHT,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		TextTransparency = 0.25,
		Visible = not touch,
		Text = "W/S drive   A/D steer   Space handbrake   F autodrive   C camera   V car/bike   N season   G weather   T time   M menu   R reset   H hide HUD   F3 stats",
	})
	self.toastLabel = label(root, {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.fromOffset(500, 26),
		TextSize = 20,
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	self.stats = label(gui, {
		Name = "Stats",
		Position = UDim2.fromOffset(28, 72),
		Size = UDim2.fromOffset(720, 100),
		TextSize = 14,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = rgb(210, 255, 210),
		TextStrokeTransparency = 0.4,
		Visible = false,
		Text = "",
	})
	root.Visible = false

	-- loading screen
	local loading = Instance.new("Frame")
	loading.Name = "Loading"
	loading.Size = UDim2.fromScale(1, 1)
	loading.BackgroundColor3 = rgb(18, 22, 28)
	loading.BorderSizePixel = 0
	loading.ZIndex = 10
	loading.Parent = gui
	self.loading = loading
	label(loading, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromOffset(800, 60),
		TextSize = 46,
		Text = "INFINITE SCENIC ROAD",
		ZIndex = 11,
	})
	label(loading, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.49),
		Size = UDim2.fromOffset(800, 24),
		TextSize = 18,
		Font = FONT_LIGHT,
		TextTransparency = 0.3,
		Text = "generating your road  -  seed " .. tostring(seed),
		ZIndex = 11,
	})
	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0.5, 0.5)
	barBack.Position = UDim2.fromScale(0.5, 0.56)
	barBack.Size = UDim2.fromOffset(360, 6)
	barBack.BackgroundColor3 = rgb(60, 66, 76)
	barBack.BorderSizePixel = 0
	barBack.ZIndex = 11
	barBack.Parent = loading
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = barBack
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0, 1)
	bar.BackgroundColor3 = rgb(240, 200, 80)
	bar.BorderSizePixel = 0
	bar.ZIndex = 12
	bar.Parent = barBack
	corner:Clone().Parent = bar
	self.bar = bar
	return self
end

function Hud:setProgress(fraction: number)
	self.bar.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
end

function Hud:finishLoading()
	local fade = TweenService:Create(self.loading, TweenInfo.new(1.2), { BackgroundTransparency = 1 })
	for _, d in self.loading:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		elseif d:IsA("Frame") then
			TweenService:Create(d, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		end
	end
	fade:Play()
	fade.Completed:Connect(function()
		self.loading.Visible = false
	end)
	self.root.Visible = true
end

function Hud:setVisible(on: boolean)
	self.root.Visible = on
end

function Hud:update(speed: number, distanceStuds: number)
	-- 1 stud ~ 0.28 m, so studs/s ~ km/h. Only touch the labels when the
	-- text changes (setting Text re-lays out the label).
	local sp = tostring(math.floor(math.abs(speed) * 1.008 + 0.5))
	if sp ~= self.speed.Text then
		self.speed.Text = sp
	end
	local dist = string.format("%.1f km", distanceStuds * 0.00028)
	if dist ~= self.distance.Text then
		self.distance.Text = dist
	end
end

-- Small line under the distance (season, weather, time).
function Hud:setInfo(text: string)
	if self.info.Text ~= text then
		self.info.Text = text
	end
end

-- Debug overlay text; nil hides it.
function Hud:setStats(text: string?)
	self.stats.Visible = text ~= nil
	if text and text ~= "" then
		self.stats.Text = text
	end
end

function Hud:setBadge(text: string)
	self.badge.Text = text
end

local function fadeText(l: TextLabel, visible: boolean, time: number)
	TweenService:Create(l, TweenInfo.new(time), {
		TextTransparency = visible and 0 or 1,
		TextStrokeTransparency = visible and 0.7 or 1,
	}):Play()
end

function Hud:showRegion(name: string, subtitle: string)
	self.region.Text = name
	self.regionSub.Text = subtitle
	fadeText(self.region, true, 1.5)
	fadeText(self.regionSub, true, 1.5)
	local token = {}
	self._regionToken = token
	task.delay(5, function()
		if self._regionToken == token then
			fadeText(self.region, false, 2)
			fadeText(self.regionSub, false, 2)
		end
	end)
end

function Hud:toast(text: string)
	self.toastLabel.Text = text
	fadeText(self.toastLabel, true, 0.2)
	local token = {}
	self._toastToken = token
	task.delay(1.8, function()
		if self._toastToken == token then
			fadeText(self.toastLabel, false, 0.6)
		end
	end)
end

return Hud
