--[[
	SettingsMenu
	------------
	The settings panel, opened from the toolbar's Settings button (or M).
	Every option is a chip or a switch you click directly: graphics
	quality, camera, speed units, speedometer, stats overlay and the
	day/night cycle. It sits on the right above the toolbar and scrolls when
	the screen is short.

	  SettingsMenu.new(root, {
	      state = { get, set },        -- see UI/App.luau for the keys
	      view = view,                 -- from Kit.screen
	      device = Kit.device(),
	      onClose = function(),
	      onShortcuts = function()?,   -- adds a "shortcuts" button
	  })
]]

local UI = script.Parent.UI
local Theme = require(UI.Theme)
local Kit = require(UI.Kit)
local Controls = require(UI.Controls)

local SettingsMenu = {}
SettingsMenu.__index = SettingsMenu

local WIDTH = 380
local HEADER_H = 42
local SECTION_GAP = 18
local LEFT = Enum.TextXAlignment.Left

function SettingsMenu.new(parent: Instance, spec)
	local self = setmetatable({}, SettingsMenu)
	self.visible = false
	self.widgets = {}
	self.view = spec.view
	self.getter = spec.state.get
	local state = spec.state
	local device = spec.device or Kit.device()

	local panel = Kit.panel(parent, {
		Name = "Settings",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.Margin, 1, -Theme.ToolbarReserve),
		Size = UDim2.fromOffset(WIDTH, 400),
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 5,
	})
	Kit.padding(panel, Theme.Pad)
	self.panel = panel
	self.popScale = Kit.new("UIScale", { Parent = panel })

	Kit.text(panel, {
		Name = "Title",
		Text = "Settings",
		Font = Theme.FontBold,
		TextSize = 18,
		TextXAlignment = LEFT,
		Size = UDim2.new(1, -40, 0, 30),
	})
	Kit.button(panel, {
		Name = "Close",
		Text = "×",
		TextSize = 22,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(30, 30),
	}, spec.onClose)

	local body = Kit.scroll(panel, {
		Name = "Body",
		Position = UDim2.fromOffset(0, HEADER_H),
		Size = UDim2.new(1, 0, 1, -HEADER_H),
	})
	Kit.list(body, false, SECTION_GAP)
	Kit.padding(body, 0, 6, 2, 0) -- room for the scroll bar

	local contentH = -SECTION_GAP
	local function add(height: number)
		contentH += height + SECTION_GAP
	end
	local function track(widget)
		table.insert(self.widgets, widget)
		return widget
	end

	local _, h = Kit.section(body, "Graphics quality", 1, function(frame)
		local chips = track(Controls.quality(frame, state, 1))
		self.qualityHint = Kit.text(frame, {
			Name = "Hint",
			Font = Theme.FontLight,
			TextSize = 12,
			TextColor3 = Theme.TextDim,
			TextXAlignment = LEFT,
			Size = UDim2.new(1, 0, 0, 14),
			LayoutOrder = 2,
		})
		return chips.height + 8 + 14
	end)
	add(h)
	_, h = Kit.section(body, "Camera", 2, function(frame)
		return track(Controls.camera(frame, state)).height
	end)
	add(h)
	_, h = Kit.section(body, "Speed units", 3, function(frame)
		return track(Controls.units(frame, state)).height
	end)
	add(h)

	local switches = Kit.new("Frame", {
		Name = "Switches",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.ToggleHeight * 3),
		LayoutOrder = 4,
		Parent = body,
	})
	Kit.list(switches, false, 0)
	track(Controls.speedometer(switches, state, 1))
	track(Controls.stats(switches, state, 2))
	track(Controls.dayCycle(switches, state, 3))
	add(Theme.ToggleHeight * 3)

	if spec.onShortcuts and (device.keyboard or device.gamepad) then
		Kit.button(body, {
			Name = "Shortcuts",
			Text = "Keyboard and gamepad shortcuts",
			TextSize = 14,
			Size = UDim2.new(1, 0, 0, 38),
			LayoutOrder = 5,
		}, spec.onShortcuts)
		add(38)
	end

	self.contentHeight = contentH + 2
	self.view.onResize(function()
		self:_fit()
	end)
	self:_fit()
	return self
end

-- As tall as the content, but never taller than the space above the toolbar.
function SettingsMenu:_fit()
	local available = self.view.height - Theme.ToolbarReserve - Theme.Margin
	local wanted = self.contentHeight + HEADER_H + Theme.Pad * 2
	self.panel.Size = UDim2.fromOffset(WIDTH, math.max(160, math.min(wanted, available)))
end

function SettingsMenu:open()
	self.visible = true
	self:_fit()
	self.panel.Visible = true
	self.popScale.Scale = 0.94
	Kit.tween(self.popScale, { Scale = 1 }, Theme.Fast)
	self:refresh()
end

function SettingsMenu:close()
	self.visible = false
	self.panel.Visible = false
end

function SettingsMenu:toggle()
	if self.visible then
		self:close()
	else
		self:open()
	end
end

function SettingsMenu:refresh()
	for _, widget in self.widgets do
		widget:refresh()
	end
	local hint = self.getter("quality") == "Auto" and ("Auto picked " .. tostring(self.getter("qualityNow")) .. " for this device")
		or "Higher shows more of the world but needs a faster device"
	if self.qualityHint.Text ~= hint then
		self.qualityHint.Text = hint
	end
end

return SettingsMenu
