--[[
	Kit
	---
	Helpers for building the interface in the Theme style:
	  Kit.new / text / panel / button / scroll   instances and styled parts
	  Kit.corner / round / stroke / padding / list
	  Kit.tween, Kit.fade                        short animations
	  Kit.chips, Kit.toggle, Kit.caption          reusable widgets
	  Kit.popover, Kit.tooltip
	  Kit.screen   a ScreenGui whose content scales to fit the screen
	  Kit.device   touch / keyboard / gamepad
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)

local Kit = {}

-- optional click sound for every button, chip and switch
local clickSound: Sound? = nil
function Kit.setClickSound(sound: Sound?)
	clickSound = sound
end
function Kit.click()
	if clickSound then
		pcall(function()
			game:GetService("SoundService"):PlayLocalSound(clickSound)
		end)
	end
end

local LEFT = Enum.TextXAlignment.Left
local RIGHT = Enum.TextXAlignment.Right

local function merge(defaults, props)
	local t = table.clone(defaults)
	if props then
		for k, v in props do
			t[k] = v
		end
	end
	return t
end

-- Instance.new with properties (Parent is set last).
function Kit.new(className: string, props: { [string]: any }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.corner(parent: Instance, radius: number?)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius), Parent = parent })
end

-- Fully rounded ends (pills and circles).
function Kit.round(parent: Instance)
	return Kit.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = parent })
end

function Kit.stroke(parent: Instance, color: Color3?, transparency: number?, thickness: number?)
	return Kit.new("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or Theme.Stroke,
		Transparency = transparency or Theme.StrokeTransparency,
		Thickness = thickness or 1,
		Parent = parent,
	})
end

function Kit.padding(parent: Instance, top: number, right: number?, bottom: number?, left: number?)
	right = right or top
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right :: number),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right :: number),
		Parent = parent,
	})
end

function Kit.list(parent: Instance, horizontal: boolean?, gap: number?, props: { [string]: any }?)
	return Kit.new("UIListLayout", merge({
		FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or Theme.Gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	}, props))
end

-- Tween to `goal`; a time of 0 sets the values at once.
function Kit.tween(inst: Instance, goal: { [string]: any }, time: number?)
	time = time or Theme.Normal
	if time <= 0 then
		for k, v in goal do
			(inst :: any)[k] = v
		end
		return nil
	end
	local tween = TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

function Kit.text(parent: Instance?, props: { [string]: any }?): TextLabel
	return Kit.new("TextLabel", merge({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Font,
		TextSize = 15,
		TextColor3 = Theme.Text,
		Text = "",
		Parent = parent,
	}, props))
end

-- A dark rounded panel with a faint outline. It sinks clicks, so they
-- don't fall through to whatever is behind it.
function Kit.panel(parent: Instance?, props: { [string]: any }?): Frame
	local frame = Kit.new("Frame", merge({
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = Theme.PanelTransparency,
		BorderSizePixel = 0,
		Active = true,
		Parent = parent,
	}, props))
	Kit.corner(frame, Theme.Radius)
	Kit.stroke(frame)
	return frame
end

function Kit.scroll(parent: Instance?, props: { [string]: any }?): ScrollingFrame
	return Kit.new("ScrollingFrame", merge({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.TextDim,
		ScrollBarImageTransparency = 0.4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = parent,
	}, props))
end

function Kit.hover(button: GuiObject, enter: () -> (), leave: () -> ())
	button.MouseEnter:Connect(enter)
	button.MouseLeave:Connect(leave)
end

--[[
	A rounded button. style: "surface" (default, raised on a panel) or
	"primary" (filled with the accent colour).
]]
function Kit.button(parent: Instance?, props: { [string]: any }?, onClick: (() -> ())?, style: string?): TextButton
	local primary = style == "primary"
	local base = primary and Theme.Accent or Theme.Surface
	local hover = primary and Theme.Accent:Lerp(Color3.new(1, 1, 1), 0.2) or Theme.SurfaceHover
	local button = Kit.new("TextButton", merge({
		AutoButtonColor = false,
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Font = primary and Theme.FontBold or Theme.Font,
		TextSize = 15,
		TextColor3 = primary and Theme.OnAccent or Theme.Text,
		Text = "",
		Parent = parent,
	}, props))
	Kit.corner(button, Theme.RadiusSmall)
	if not primary then
		Kit.stroke(button)
	end
	Kit.hover(button, function()
		Kit.tween(button, { BackgroundColor3 = hover }, Theme.Fast)
	end, function()
		Kit.tween(button, { BackgroundColor3 = base }, Theme.Fast)
	end)
	if onClick then
		button.Activated:Connect(function()
			Kit.click()
			onClick()
		end)
	end
	return button
end

-- Small upper-case heading above a group of controls.
function Kit.caption(parent: Instance, text: string, order: number?): TextLabel
	return Kit.text(parent, {
		Name = "Caption",
		Text = string.upper(text),
		Font = Theme.FontBold,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		TextXAlignment = LEFT,
		Size = UDim2.new(1, 0, 0, Theme.LabelHeight),
		LayoutOrder = order or 0,
	})
end

--[[
	A captioned group of controls. build(frame) adds the controls (with
	LayoutOrder 1 and up) and returns their height. Returns the frame and
	its total height.
]]
function Kit.section(parent: Instance, title: string, order: number, build: (Frame) -> number): (Frame, number)
	local frame = Kit.new("Frame", {
		Name = title,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.list(frame, false, 8)
	Kit.caption(frame, title, 0)
	local height = Theme.LabelHeight + 8 + build(frame)
	frame.Size = UDim2.new(1, 0, 0, height)
	return frame, height
end

---------------------------------------------------------------------------
-- Chips: pick one option by clicking it
---------------------------------------------------------------------------
local Chips = {}
Chips.__index = Chips

--[[
	A grid of chips, one per option. The current option is filled with the
	accent colour; clicking a chip calls spec.set(value).
	  options  { { value = any, text = string }, ... }
	  spec     { get = function() -> value, set = function(value),
	             columns = number?, name = string?, order = number? }
	group.height is the height of its rows.
]]
function Kit.chips(parent: Instance, options, spec)
	local columns = spec.columns or #options
	local rows = math.ceil(#options / columns)
	local h, gap = Theme.ChipHeight, 6
	local self = setmetatable({
		getter = spec.get,
		entries = {},
		current = nil,
		height = rows * h + (rows - 1) * gap,
	}, Chips)
	local frame = Kit.new("Frame", {
		Name = spec.name or "Chips",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, self.height),
		LayoutOrder = spec.order or 0,
		Parent = parent,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(1 / columns, -gap * (columns - 1) / columns, 0, h),
		CellPadding = UDim2.fromOffset(gap, gap),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = frame,
	})
	for i, option in options do
		local button = Kit.new("TextButton", {
			Name = tostring(option.value),
			LayoutOrder = i,
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Surface,
			BorderSizePixel = 0,
			Font = Theme.Font,
			TextSize = 14,
			TextColor3 = Theme.Text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = option.text,
			Parent = frame,
		})
		Kit.corner(button, Theme.RadiusSmall)
		local entry = { value = option.value, button = button, stroke = Kit.stroke(button), hovered = false }
		Kit.hover(button, function()
			entry.hovered = true
			self:_paint(entry, Theme.Fast)
		end, function()
			entry.hovered = false
			self:_paint(entry, Theme.Fast)
		end)
		button.Activated:Connect(function()
			Kit.click()
			spec.set(option.value)
			self:refresh()
		end)
		table.insert(self.entries, entry)
	end
	self.frame = frame
	self:refresh(true)
	return self
end

function Chips:_paint(entry, time: number)
	local on = entry.value == self.current
	Kit.tween(entry.button, {
		BackgroundColor3 = on and Theme.Accent or (entry.hovered and Theme.SurfaceHover or Theme.Surface),
		TextColor3 = on and Theme.OnAccent or Theme.Text,
	}, time)
	entry.stroke.Color = on and Theme.Accent or Theme.Stroke
end

-- Re-read the current value; only repaints when it changed.
function Chips:refresh(force: boolean?)
	local value = self.getter()
	if value == self.current and not force then
		return
	end
	self.current = value
	for _, entry in self.entries do
		self:_paint(entry, force and 0 or Theme.Fast)
	end
end

---------------------------------------------------------------------------
-- Toggle: a labelled on/off switch
---------------------------------------------------------------------------
local Toggle = {}
Toggle.__index = Toggle

--[[
	A row with a label (and an optional detail line) and a switch.
	Clicking anywhere on the row flips it.
	  spec { text, detail?, get = function() -> boolean,
	         set = function(boolean), order? }
]]
function Kit.toggle(parent: Instance, spec)
	local row = Kit.new("TextButton", {
		Name = spec.name or spec.text,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.new(1, 0, 0, Theme.ToggleHeight),
		LayoutOrder = spec.order or 0,
		Parent = parent,
	})
	Kit.text(row, {
		Name = "Label",
		Text = spec.text,
		TextXAlignment = LEFT,
		Position = UDim2.fromOffset(0, spec.detail and 4 or 0),
		Size = UDim2.new(1, -60, 0, spec.detail and 20 or Theme.ToggleHeight),
	})
	if spec.detail then
		Kit.text(row, {
			Name = "Detail",
			Text = spec.detail,
			Font = Theme.FontLight,
			TextSize = 12,
			TextColor3 = Theme.TextDim,
			TextXAlignment = LEFT,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(1, -60, 0, 16),
		})
	end
	local track = Kit.new("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(46, 26),
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		Parent = row,
	})
	Kit.round(track)
	Kit.stroke(track)
	local knob = Kit.new("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		Parent = track,
	})
	Kit.round(knob)
	local self = setmetatable({ getter = spec.get, frame = row, track = track, knob = knob, current = nil }, Toggle)
	row.Activated:Connect(function()
		Kit.click()
		spec.set(not spec.get())
		self:refresh()
	end)
	self:refresh(true)
	return self
end

function Toggle:refresh(force: boolean?)
	local on = self.getter() == true
	if on == self.current and not force then
		return
	end
	self.current = on
	local time = force and 0 or Theme.Fast
	Kit.tween(self.track, { BackgroundColor3 = on and Theme.Accent or Theme.Surface }, time)
	Kit.tween(self.knob, { Position = UDim2.new(0, on and 23 or 3, 0.5, 0) }, time)
end

---------------------------------------------------------------------------
-- Popovers and tooltips
---------------------------------------------------------------------------

--[[
	A popover panel: a title, an optional status line on the right, then
	whatever is added below (it grows to fit). Hidden until shown.
	Returns the panel and the status label.
]]
function Kit.popover(parent: Instance, name: string, title: string, width: number)
	local panel = Kit.panel(parent, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.1,
		Visible = false,
		ZIndex = 5,
	})
	Kit.padding(panel, Theme.Pad)
	Kit.list(panel, false, 10)
	local header = Kit.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 0,
		Parent = panel,
	})
	Kit.text(header, {
		Name = "Title",
		Text = title,
		Font = Theme.FontBold,
		TextSize = 16,
		TextXAlignment = LEFT,
		Size = UDim2.fromScale(1, 1),
	})
	local status = Kit.text(header, {
		Name = "Status",
		Font = Theme.FontLight,
		TextSize = 13,
		TextColor3 = Theme.TextDim,
		TextXAlignment = RIGHT,
		Size = UDim2.fromScale(1, 1),
	})
	return panel, status
end

-- A hint above `button` while the mouse is over it. getText() is read
-- each time it shows; canShow() (optional) can keep it hidden.
function Kit.tooltip(button: GuiObject, getText: () -> string, canShow: (() -> boolean)?): TextLabel
	local tip = Kit.text(button, {
		Name = "Tooltip",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -10),
		Size = UDim2.fromOffset(0, 28),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		TextSize = 13,
		Visible = false,
		ZIndex = 10,
	})
	Kit.corner(tip, 6)
	Kit.padding(tip, 0, 10)
	Kit.stroke(tip)
	Kit.hover(button, function()
		if canShow == nil or canShow() then
			tip.Text = getText()
			tip.Visible = true
		end
	end, function()
		tip.Visible = false
	end)
	return tip
end

---------------------------------------------------------------------------
-- Fading
---------------------------------------------------------------------------
local fadeTokens = setmetatable({}, { __mode = "k" })

local function fadeProps(inst: Instance): { string }?
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		return { "BackgroundTransparency", "TextTransparency", "TextStrokeTransparency" }
	elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		return { "BackgroundTransparency", "ImageTransparency" }
	elseif inst:IsA("GuiObject") then
		return { "BackgroundTransparency" }
	elseif inst:IsA("UIStroke") then
		return { "Transparency" }
	end
	return nil
end

--[[
	Fade `root` and everything inside it in or out (hiding it at the end of
	a fade out). The first fade remembers each object's own transparency in
	IR_ attributes and later fades return to it, so only use this on UI
	whose transparencies don't change for other reasons.
]]
function Kit.fade(root: GuiObject, visible: boolean, time: number?)
	local t = time or Theme.Normal
	local token = {}
	fadeTokens[root] = token
	local wasVisible = root.Visible
	if not visible and not wasVisible then
		return
	end
	local objects = root:GetDescendants()
	table.insert(objects, root)
	for _, inst in objects do
		local props = fadeProps(inst)
		if props then
			local goal = {}
			for _, prop in props do
				local key = "IR_" .. prop
				local base = inst:GetAttribute(key)
				if base == nil then
					base = (inst :: any)[prop]
					inst:SetAttribute(key, base)
				end
				if visible and not wasVisible then
					(inst :: any)[prop] = 1
				end
				goal[prop] = visible and base or 1
			end
			Kit.tween(inst, goal, t)
		end
	end
	root.Visible = true
	if not visible then
		task.delay(t, function()
			if fadeTokens[root] == token then
				root.Visible = false
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Screens and devices
---------------------------------------------------------------------------
local function flag(name: string): boolean
	local ok, value = pcall(function()
		return (UserInputService :: any)[name]
	end)
	return ok and value == true
end

-- touch: a touch screen without a keyboard (phones and tablets).
function Kit.device()
	local keyboard = flag("KeyboardEnabled")
	return {
		touch = flag("TouchEnabled") and not keyboard,
		keyboard = keyboard,
		gamepad = flag("GamepadEnabled"),
	}
end

local function screenSize(gui: ScreenGui): Vector2
	local ok, size = pcall(function()
		return gui.AbsoluteSize
	end)
	if ok and typeof(size) == "Vector2" and size.X > 0 and size.Y > 0 then
		return size
	end
	return Vector2.new(Theme.RefWidth, Theme.RefHeight)
end

--[[
	A ScreenGui with a scaled root frame. Lay out children of `root` in base
	pixels: the root is sized so that after its UIScale it covers exactly the
	screen, and the scale fits a Theme.RefWidth x RefHeight layout.
	`view` has the root's size in base pixels (width, height), the scale,
	and onResize(fn) to hear about screen changes.
	fullBleed: cover the whole screen, top bar and notches included;
	otherwise content stays clear of the Roblox top bar.
]]
function Kit.screen(parent: Instance, name: string, displayOrder: number, fullBleed: boolean?)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = displayOrder
	if fullBleed then
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.None
		gui.ClipToDeviceSafeArea = false
	else
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end
	local root = Kit.new("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local uiScale = Kit.new("UIScale", { Parent = root })
	local listeners = {}
	local view = { width = Theme.RefWidth, height = Theme.RefHeight, scale = 1 }
	function view.onResize(fn)
		table.insert(listeners, fn)
	end
	local minScale = Kit.device().touch and Theme.TouchMinScale or Theme.MinScale
	local function update()
		local size = screenSize(gui)
		local s = math.clamp(math.min(size.X / Theme.RefWidth, size.Y / Theme.RefHeight), minScale, Theme.MaxScale)
		s = math.min(s, size.X / Theme.MinViewWidth) -- narrow (portrait) screens
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		view.scale, view.width, view.height = s, size.X / s, size.Y / s
		for _, fn in listeners do
			fn(view)
		end
	end
	gui.Parent = parent
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
	return gui, root, view
end

return Kit
