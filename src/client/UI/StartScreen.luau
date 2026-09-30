--[[
	StartScreen
	-----------
	Shown after the loading screen, over the blurred and dimmed world: the
	title, the vehicle picker, season / weather / time of day chips, the
	day/night cycle switch and the "Drive" and "Autodrive" buttons. Every
	choice applies at once, so the world behind it changes as you pick.
	Closing it fades it out and removes the blur.

	  StartScreen.new(parent, {
	      state = { get, set },             -- see App.luau for the keys
	      setVehicle = function(id, color),
	      onStart = function(autodrive: boolean),
	      seed = number?,
	      device = Kit.device(),
	  })
]]

local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Controls = require(script.Parent.Controls)
local VehiclePicker = require(script.Parent.VehiclePicker)

local StartScreen = {}
StartScreen.__index = StartScreen

local LEFT_W, RIGHT_W, COL_GAP = 520, 420, 28
local PAD = 24
local HEADER_H, FOOTER_H = 64, 48
local SECTION_GAP = 18
local BLUR_SIZE = 14
local LEFT = Enum.TextXAlignment.Left

local function column(parent: Instance, name: string, width: number, order: number): Frame
	local frame = Kit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, 0),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.list(frame, false, SECTION_GAP)
	return frame
end

function StartScreen.new(parent: Instance, spec)
	local self = setmetatable({}, StartScreen)
	self.visible = true
	self.widgets = {}
	self.onStart = spec.onStart
	local state = spec.state
	local device = spec.device or Kit.device()

	local gui, root, view = Kit.screen(parent, "InfiniteRoadStart", 8, true)
	self.gui, self.root = gui, root

	self.blur = Kit.new("BlurEffect", { Name = "IR_StartBlur", Size = 0, Parent = Lighting })
	Kit.tween(self.blur, { Size = BLUR_SIZE }, Theme.Slow)

	local dim = Kit.new("Frame", {
		Name = "Dim",
		BackgroundColor3 = Theme.Backdrop,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
		Parent = dim,
	})

	local card = Kit.panel(root, {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 0.12,
	})
	Kit.padding(card, PAD)
	self.card = card

	-- title
	local header = Kit.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER_H),
		Parent = card,
	})
	local bar = Kit.new("Frame", {
		Name = "Accent",
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(36, 4),
		Parent = header,
	})
	Kit.round(bar)
	Kit.text(header, {
		Name = "Title",
		Text = "INFINITE SCENIC ROAD",
		Font = Theme.FontBold,
		TextSize = 30,
		TextXAlignment = LEFT,
		Position = UDim2.fromOffset(0, 10),
		Size = UDim2.new(1, 0, 0, 34),
	})
	Kit.text(header, {
		Name = "Subtitle",
		Text = spec.seed and ("An endless drive  ·  seed " .. tostring(spec.seed)) or "An endless drive",
		Font = Theme.FontLight,
		TextSize = 14,
		TextColor3 = Theme.TextDim,
		TextXAlignment = LEFT,
		Position = UDim2.fromOffset(0, 45),
		Size = UDim2.new(1, 0, 0, 18),
	})

	-- two columns, stacked when the screen is too narrow for both
	local body = Kit.scroll(card, { Name = "Body", Position = UDim2.fromOffset(0, HEADER_H + 16) })
	Kit.list(body, true, COL_GAP, { Wraps = true, HorizontalAlignment = Enum.HorizontalAlignment.Center })
	self.body = body

	local left = column(body, "Vehicle", LEFT_W, 1)
	local picker = VehiclePicker.new(left, {
		width = LEFT_W,
		order = 1,
		get = function()
			return state.get("vehicle"), state.get("color")
		end,
		set = spec.setVehicle,
	})
	table.insert(self.widgets, picker)
	local leftH = picker.height
	left.Size = UDim2.fromOffset(LEFT_W, leftH)

	local right = column(body, "World", RIGHT_W, 2)
	local rightH = -SECTION_GAP
	local function section(title: string, order: number, build)
		local _, h = Kit.section(right, title, order, build)
		rightH += h + SECTION_GAP
	end
	section("Season", 1, function(frame)
		local w = Controls.season(frame, state)
		table.insert(self.widgets, w)
		return w.height
	end)
	section("Weather", 2, function(frame)
		local w = Controls.weather(frame, state)
		table.insert(self.widgets, w)
		return w.height
	end)
	section("Time of day", 3, function(frame)
		local chips = Controls.time(frame, state, 1)
		local cycle = Controls.dayCycle(frame, state, 2)
		table.insert(self.widgets, chips)
		table.insert(self.widgets, cycle)
		return chips.height + 8 + cycle.height
	end)
	right.Size = UDim2.fromOffset(RIGHT_W, rightH)

	-- buttons
	local footer = Kit.new("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER_H),
		Parent = card,
	})
	local hint = Kit.text(footer, {
		Name = "Hint",
		Text = device.keyboard and "Press Enter to drive. You can change all of this later from the toolbar."
			or "You can change all of this later from the toolbar.",
		Font = Theme.FontLight,
		TextSize = 13,
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
		TextXAlignment = LEFT,
		Size = UDim2.new(1, -400, 1, 0),
	})
	self.driveButton = Kit.button(footer, {
		Name = "Drive",
		Text = "Drive",
		TextSize = 17,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(180, FOOTER_H),
	}, function()
		self:_start(false)
	end, "primary")
	self.autodriveButton = Kit.button(footer, {
		Name = "Autodrive",
		Text = "🛣️ Autodrive",
		TextSize = 16,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -192, 0, 0),
		Size = UDim2.fromOffset(180, FOOTER_H),
	}, function()
		self:_start(true)
	end)

	local function layout()
		local width = math.min(LEFT_W + COL_GAP + RIGHT_W + 2 + PAD * 2, view.width - 48)
		local inner = width - PAD * 2
		local sideBySide = inner >= LEFT_W + COL_GAP + RIGHT_W
		local bodyH = sideBySide and math.max(leftH, rightH) or (leftH + COL_GAP + rightH)
		local maxBody = view.height - 96 - (HEADER_H + 16 + 16 + FOOTER_H + PAD * 2)
		local shownH = math.clamp(bodyH, 120, math.max(120, maxBody))
		body.Size = UDim2.new(1, 0, 0, shownH)
		card.Size = UDim2.fromOffset(width, HEADER_H + 16 + shownH + 16 + FOOTER_H + PAD * 2)
		hint.Visible = inner >= 640
		self.stacked = not sideBySide
	end
	view.onResize(layout)
	layout()

	-- gamepads: highlight "Drive" so A starts right away (the selection
	-- clears itself when the screen is destroyed)
	if device.gamepad then
		GuiService.SelectedObject = self.driveButton
	end
	return self
end

function StartScreen:_start(autodrive: boolean)
	if self.visible and self.onStart then
		self.onStart(autodrive)
	end
end

function StartScreen:refresh()
	if not self.visible then
		return
	end
	for _, widget in self.widgets do
		widget:refresh()
	end
end

-- Fade out, remove the blur, then destroy everything.
function StartScreen:close()
	if not self.visible then
		return
	end
	self.visible = false
	Kit.fade(self.root, false, Theme.Slow)
	Kit.tween(self.card, { Position = UDim2.new(0.5, 0, 0.5, 24) }, Theme.Slow)
	if self.blur then
		Kit.tween(self.blur, { Size = 0 }, Theme.Slow)
	end
	task.delay(Theme.Slow + 0.05, function()
		self:destroy()
	end)
end

function StartScreen:destroy()
	self.visible = false
	if self.blur then
		self.blur:Destroy()
		self.blur = nil
	end
	if self.gui then
		self.gui:Destroy()
		self.gui = nil
	end
end

return StartScreen
