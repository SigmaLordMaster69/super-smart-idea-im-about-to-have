--[[
	SettingsMenu
	------------
	A small panel (gear button top-right, or M) with one row per setting.
	Clicking a row cycles its value. Rows are registered by the client:
	  menu:addRow("Season", function() return label end, function() cycle() end)
]]

local Players = game:GetService("Players")

local SettingsMenu = {}
SettingsMenu.__index = SettingsMenu

local rgb = Color3.fromRGB

local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

function SettingsMenu.new()
	local self = setmetatable({}, SettingsMenu)
	self.rows = {}
	local gui = Instance.new("ScreenGui")
	gui.Name = "InfiniteRoadSettings"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.gui = gui

	local gear = Instance.new("TextButton")
	gear.Name = "Gear"
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -16, 0, 14)
	gear.Size = UDim2.fromOffset(44, 44)
	gear.BackgroundColor3 = rgb(20, 24, 30)
	gear.BackgroundTransparency = 0.35
	gear.Text = "\u{2699}"
	gear.TextColor3 = Color3.new(1, 1, 1)
	gear.TextSize = 26
	gear.Font = Enum.Font.GothamBold
	gear.AutoButtonColor = true
	gear.Parent = gui
	corner(gear, 10)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -16, 0, 66)
	panel.Size = UDim2.fromOffset(300, 10)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = rgb(18, 22, 28)
	panel.BackgroundTransparency = 0.2
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	self.panel = panel

	gear.Activated:Connect(function()
		self:toggle()
	end)
	return self
end

function SettingsMenu:toggle()
	self.panel.Visible = not self.panel.Visible
	if self.panel.Visible then
		self:refresh()
	end
end

-- label: function() -> current value text; action: function() when clicked
function SettingsMenu:addRow(title: string, label, action)
	local button = Instance.new("TextButton")
	button.Name = title
	button.LayoutOrder = #self.rows + 1
	button.Size = UDim2.new(1, 0, 0, 38)
	button.BackgroundColor3 = rgb(40, 46, 56)
	button.BackgroundTransparency = 0.1
	button.AutoButtonColor = true
	button.Text = ""
	button.Parent = self.panel
	corner(button, 8)
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(12, 0)
	name.Size = UDim2.new(0.45, 0, 1, 0)
	name.Font = Enum.Font.Gotham
	name.TextSize = 15
	name.TextColor3 = rgb(190, 198, 210)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = title
	name.Parent = button
	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -12, 0, 0)
	value.Size = UDim2.new(0.55, -12, 1, 0)
	value.Font = Enum.Font.GothamBold
	value.TextSize = 15
	value.TextColor3 = Color3.new(1, 1, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Text = label()
	value.Parent = button
	local row = { button = button, value = value, label = label }
	table.insert(self.rows, row)
	button.Activated:Connect(function()
		action()
		self:refresh()
	end)
end

function SettingsMenu:refresh()
	for _, row in self.rows do
		row.value.Text = row.label()
	end
end

return SettingsMenu
