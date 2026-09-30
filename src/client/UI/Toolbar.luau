--[[
	Toolbar
	-------
	The bar of icon + label buttons at the bottom of the screen. A button
	can be "active" (filled with the accent colour, for toggles such as
	Autodrive) or "open" (outlined while its popover or panel is open), and
	shows a tooltip when the mouse is over it.

	  Toolbar.new(parent, items, { tooltips = boolean, canTip = function() -> boolean })
	items: a list of { id, label, icon, tip = function() -> string, onClick },
	or "|" for a divider between groups.
]]

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)

local Toolbar = {}
Toolbar.__index = Toolbar

local GAP = 4
local DIVIDER = 13

function Toolbar.new(parent: Instance, items, spec)
	local self = setmetatable({}, Toolbar)
	self.entries = {}
	local bw, bh, pad = Theme.ToolbarButtonWidth, Theme.ToolbarButtonHeight, Theme.ToolbarPad

	-- lay the buttons out left to right; x is each slot's left edge
	local slots, x = {}, pad
	for i, item in items do
		table.insert(slots, x)
		x += (item == "|" and DIVIDER or bw) + (i < #items and GAP or 0)
	end
	local width = x + pad
	self.width = width

	local frame = Kit.panel(parent, {
		Name = "Toolbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.ToolbarBottom),
		Size = UDim2.fromOffset(width, Theme.ToolbarHeight),
		ZIndex = 3,
	})
	self.frame = frame

	for i, item in items do
		local left = slots[i]
		if item == "|" then
			Kit.new("Frame", {
				Name = "Divider",
				BackgroundColor3 = Theme.Stroke,
				BackgroundTransparency = 0.86,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(left + math.floor(DIVIDER / 2), pad + 12),
				Size = UDim2.fromOffset(1, bh - 24),
				Parent = frame,
			})
			continue
		end
		local button = Kit.new("TextButton", {
			Name = item.id,
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Surface,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			Position = UDim2.fromOffset(left, pad),
			Size = UDim2.fromOffset(bw, bh),
			Parent = frame,
		})
		Kit.corner(button, Theme.RadiusSmall)
		local entry = {
			id = item.id,
			button = button,
			stroke = Kit.stroke(button, Theme.Accent, 1, 1.5),
			icon = Kit.text(button, {
				Name = "Icon",
				Text = item.icon,
				TextSize = 22,
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.new(1, 0, 0, 24),
			}),
			label = Kit.text(button, {
				Name = "Label",
				Text = item.label,
				TextSize = 12,
				TextColor3 = Theme.TextDim,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.fromOffset(2, 36),
				Size = UDim2.new(1, -4, 0, 16),
			}),
			x = left + bw / 2 - width / 2,
			hovered = false,
			active = false,
			open = false,
		}
		Kit.hover(button, function()
			entry.hovered = true
			self:_paint(entry)
		end, function()
			entry.hovered = false
			self:_paint(entry)
		end)
		if spec.tooltips then
			Kit.tooltip(button, item.tip or function()
				return item.label
			end, spec.canTip)
		end
		button.Activated:Connect(item.onClick)
		self.entries[item.id] = entry
	end
	return self
end

function Toolbar:_paint(entry)
	local color, transparency, text = Theme.Surface, 1, Theme.TextDim
	if entry.active then
		color, transparency, text = Theme.Accent, 0, Theme.OnAccent
	elseif entry.open then
		color, transparency, text = Theme.SurfaceHover, 0, Theme.Text
	elseif entry.hovered then
		color, transparency, text = Theme.Surface, 0, Theme.Text
	end
	Kit.tween(entry.button, { BackgroundColor3 = color, BackgroundTransparency = transparency }, Theme.Fast)
	Kit.tween(entry.label, { TextColor3 = text }, Theme.Fast)
	entry.stroke.Transparency = (entry.open and not entry.active) and 0 or 1
end

-- Filled with the accent colour (a toggle that is on).
function Toolbar:setActive(id: string, on: boolean)
	local entry = self.entries[id]
	if entry and entry.active ~= on then
		entry.active = on
		self:_paint(entry)
	end
end

-- Outlined (its popover or panel is open).
function Toolbar:setOpen(id: string, on: boolean)
	local entry = self.entries[id]
	if entry and entry.open ~= on then
		entry.open = on
		self:_paint(entry)
	end
end

function Toolbar:setIcon(id: string, icon: string)
	local entry = self.entries[id]
	if entry and entry.icon.Text ~= icon then
		entry.icon.Text = icon
	end
end

-- Horizontal offset of a button's centre from the toolbar's centre.
function Toolbar:offset(id: string): number
	local entry = self.entries[id]
	return entry and entry.x or 0
end

-- Slide up from below the screen.
function Toolbar:slideIn()
	self.frame.Position = UDim2.new(0.5, 0, 1, Theme.ToolbarHeight + 20)
	Kit.tween(self.frame, { Position = UDim2.new(0.5, 0, 1, -Theme.ToolbarBottom) }, Theme.Slow)
end

return Toolbar
