--[[
	VehiclePicker
	-------------
	Vehicle cards grouped by category (cars, motorcycles), each with its
	name, description and paint colours, and below them big paint swatches
	for the selected vehicle. Used by the start screen and by the toolbar's
	Vehicle popover.

	  VehiclePicker.new(parent, {
	      width = number,
	      get = function() -> (id, color),
	      set = function(id, color),
	      order = number?,
	  })
	picker.height is the height it needs; picker:refresh() re-reads the
	current vehicle and colour.
]]

local Vehicles = require(script.Parent.Parent.Vehicles)
local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Options = require(script.Parent.Options)

local VehiclePicker = {}
VehiclePicker.__index = VehiclePicker

local CARD_W, CARD_H = 124, 96
local GAP = 8
local SWATCH = 30
local DOT = 10
local LEFT = Enum.TextXAlignment.Left

local SELECTED = Theme.Surface:Lerp(Theme.Accent, 0.18)

local function sameColor(a: Color3?, b: Color3?): boolean
	if a == nil or b == nil then
		return false
	end
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.01
end

-- The colour in `colors` closest to `color` (keeps "red" when switching
-- between vehicles with different palettes).
local function nearest(colors, color: Color3?): Color3?
	if not color then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, c in colors do
		local d = (c.R - color.R) ^ 2 + (c.G - color.G) ^ 2 + (c.B - color.B) ^ 2
		if d < bestD then
			best, bestD = c, d
		end
	end
	return best
end

-- Vehicle ids grouped by category, in catalogue order.
local function groups()
	local list, byCategory = {}, {}
	for _, id in Vehicles.Order do
		local category = Vehicles.get(id).category or "Car"
		if not byCategory[category] then
			byCategory[category] = { category = category, ids = {} }
			table.insert(list, byCategory[category])
		end
		table.insert(byCategory[category].ids, id)
	end
	return list
end

function VehiclePicker.new(parent: Instance, spec)
	local self = setmetatable({}, VehiclePicker)
	self.getter = spec.get
	self.setter = spec.set
	self.cards = {}
	self.swatches = {}
	self.paintId = nil
	self.selectedId = nil
	self.selectedColor = nil

	local width = spec.width
	local perRow = math.max(1, math.floor((width + GAP) / (CARD_W + GAP)))
	local cardW = math.floor((width - GAP * (perRow - 1)) / perRow)

	local frame = Kit.new("Frame", {
		Name = "VehiclePicker",
		BackgroundTransparency = 1,
		LayoutOrder = spec.order or 0,
		Parent = parent,
	})
	Kit.list(frame, false, GAP)
	self.frame = frame

	local height, order = -GAP, 0
	local function nextOrder(h: number): number
		height += h + GAP
		order += 1
		return order
	end

	for _, group in groups() do
		Kit.caption(frame, Options.CategoryNames[group.category] or group.category, nextOrder(Theme.LabelHeight))
		local rows = math.ceil(#group.ids / perRow)
		local gridH = rows * CARD_H + (rows - 1) * GAP
		local grid = Kit.new("Frame", {
			Name = group.category,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, gridH),
			LayoutOrder = nextOrder(gridH),
			Parent = frame,
		})
		Kit.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(cardW, CARD_H),
			CellPadding = UDim2.fromOffset(GAP, GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		for i, id in group.ids do
			self:_card(grid, id, i)
		end
	end

	Kit.caption(frame, "Paint", nextOrder(Theme.LabelHeight))
	local paint = Kit.new("Frame", {
		Name = "Paint",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, SWATCH + 6),
		LayoutOrder = nextOrder(SWATCH + 6),
		Parent = frame,
	})
	Kit.list(paint, true, 10, { VerticalAlignment = Enum.VerticalAlignment.Center })
	Kit.padding(paint, 0, 3)
	self.paint = paint

	self.height = height
	frame.Size = UDim2.fromOffset(width, height)
	self:refresh()
	return self
end

function VehiclePicker:_card(parent: Instance, id: string, order: number)
	local spec = Vehicles.get(id)
	local button = Kit.new("TextButton", {
		Name = id,
		LayoutOrder = order,
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Surface,
		BorderSizePixel = 0,
		Text = "",
		Parent = parent,
	})
	Kit.corner(button, Theme.RadiusSmall)
	local stroke = Kit.stroke(button)
	Kit.padding(button, 10)
	Kit.text(button, {
		Name = "Icon",
		Text = Options.vehicleIcon(id),
		TextSize = 17,
		TextXAlignment = LEFT,
		Size = UDim2.fromOffset(22, 20),
	})
	Kit.text(button, {
		Name = "Title",
		Text = spec.name,
		Font = Theme.FontBold,
		TextSize = 14,
		TextXAlignment = LEFT,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(25, 0),
		Size = UDim2.new(1, -25, 0, 20),
	})
	Kit.text(button, {
		Name = "Description",
		Text = spec.description or "",
		Font = Theme.FontLight,
		TextSize = 12,
		TextColor3 = Theme.TextDim,
		TextWrapped = true,
		TextXAlignment = LEFT,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 30),
	})
	local dots = Kit.new("Frame", {
		Name = "Colors",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, DOT),
		Parent = button,
	})
	Kit.list(dots, true, 4)
	for i, color in spec.colors do
		local dot = Kit.new("Frame", {
			Name = "Color" .. i,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(DOT, DOT),
			LayoutOrder = i,
			Parent = dots,
		})
		Kit.round(dot)
	end

	local entry = { button = button, stroke = stroke, hovered = false }
	Kit.hover(button, function()
		entry.hovered = true
		self:_paintCard(id, entry)
	end, function()
		entry.hovered = false
		self:_paintCard(id, entry)
	end)
	button.Activated:Connect(function()
		local _, color = self.getter()
		self.setter(id, nearest(spec.colors, color))
		self:refresh()
	end)
	self.cards[id] = entry
end

function VehiclePicker:_paintCard(id: string, entry)
	local on = id == self.selectedId
	Kit.tween(entry.button, {
		BackgroundColor3 = on and SELECTED or (entry.hovered and Theme.SurfaceHover or Theme.Surface),
	}, Theme.Fast)
	entry.stroke.Color = on and Theme.Accent or Theme.Stroke
	entry.stroke.Transparency = on and 0 or Theme.StrokeTransparency
	entry.stroke.Thickness = on and 2 or 1
end

-- Paint swatches for vehicle `id` (palettes differ between vehicles).
function VehiclePicker:_buildPaint(id: string)
	for _, swatch in self.swatches do
		swatch.button:Destroy()
	end
	self.swatches = {}
	for i, color in Vehicles.get(id).colors do
		local button = Kit.new("TextButton", {
			Name = "Swatch" .. i,
			AutoButtonColor = false,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Text = "",
			Size = UDim2.fromOffset(SWATCH, SWATCH),
			LayoutOrder = i,
			Parent = self.paint,
		})
		Kit.round(button)
		local stroke = Kit.stroke(button, Theme.Stroke, 0.7)
		button.Activated:Connect(function()
			self.setter(id, color)
			self:refresh()
		end)
		table.insert(self.swatches, { button = button, stroke = stroke, color = color })
	end
	self.paintId = id
	self.selectedId = nil -- repaint everything below
end

function VehiclePicker:refresh()
	local id, color = self.getter()
	if id ~= self.paintId then
		self:_buildPaint(id)
	end
	if id == self.selectedId and sameColor(color, self.selectedColor) then
		return
	end
	self.selectedId, self.selectedColor = id, color
	for cardId, entry in self.cards do
		self:_paintCard(cardId, entry)
	end
	for _, swatch in self.swatches do
		local on = sameColor(swatch.color, color)
		swatch.stroke.Color = Theme.Text
		swatch.stroke.Transparency = on and 0 or 0.7
		swatch.stroke.Thickness = on and 3 or 1
	end
end

return VehiclePicker
