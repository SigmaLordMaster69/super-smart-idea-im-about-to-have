--[[
	App
	---
	The clickable interface on top of the game: the start screen, the
	bottom toolbar and its popovers (camera, vehicle, season, weather, time
	of day, shortcuts), the settings panel, photo mode, and on-screen pedals
	on touch screens. Keyboard and gamepad shortcuts (Input.luau) remain as
	optional extras and go through the same `app` functions.

	The client passes `app`, which reads and changes the game:
	  app.get(key) / app.set(key, value) with these keys:
	    vehicle, color          current vehicle id and paint (read only)
	    season, weather         "Auto" or a name
	    seasonNow, weatherNow   what is showing right now (read only)
	    clock                   Lighting.ClockTime
	    dayCycle                the day/night cycle is running
	    camera                  a CameraController mode name
	    autodrive               boolean
	    quality                 "Auto" or a preset name
	    qualityNow              the preset in use (read only)
	    units                   "km/h" or "mph"
	    speedometer, stats      booleans
	  app.setVehicle(id, color?)  switch vehicle, keeping position and speed
	  app.reset()                 put the vehicle back on the road
	  app.start(autodrive)        the player left the start screen

	  local ui = App.new(playerGui, app, { hud = hud, input = input, seed = seed })
	  ui:refresh()  -- re-read the game state (after shortcuts, and now and then)
]]

local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Options = require(script.Parent.Options)
local Controls = require(script.Parent.Controls)
local Toolbar = require(script.Parent.Toolbar)
local VehiclePicker = require(script.Parent.VehiclePicker)
local StartScreen = require(script.Parent.StartScreen)
local SettingsMenu = require(script.Parent.Parent.SettingsMenu)
local Vehicles = require(script.Parent.Parent.Vehicles)

local App = {}
App.__index = App

local PICKER_W = 520
local LEFT = Enum.TextXAlignment.Left

function App.new(parent: Instance, app, opts)
	local self = setmetatable({}, App)
	self.app = app
	self.hud = opts.hud
	self.device = opts.device or Kit.device()
	self.widgets = {}
	self.popovers = {}
	self.openId = nil
	self.started = false
	self.photoOn = false
	self.photoToken = nil

	-- what the widgets use: every change refreshes the whole interface
	self.state = {
		get = app.get,
		set = function(key, value)
			app.set(key, value)
			self:refresh()
		end,
	}

	local gui, root, view = Kit.screen(parent, "InfiniteRoadUI", 5)
	gui.Enabled = false -- shown when the start screen closes
	self.gui, self.root, self.view = gui, root, view

	-- a click anywhere outside an open popover closes it
	self.scrim = Kit.new("TextButton", {
		Name = "Scrim",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 1,
		Parent = root,
	})
	self.scrim.Activated:Connect(function()
		self:closeAll()
	end)

	self:_buildToolbar()
	self:_buildPopovers()
	self.settingsMenu = SettingsMenu.new(root, {
		state = self.state,
		view = view,
		device = self.device,
		onClose = function()
			self:closeAll()
		end,
		onShortcuts = function()
			self:openPopover("help")
		end,
	})
	if self.device.touch and opts.input then
		opts.input:touchControls(root)
	end
	self:_buildPhoto(parent)

	self.startScreen = StartScreen.new(parent, {
		state = self.state,
		setVehicle = function(id, color)
			app.setVehicle(id, color)
			self:refresh()
		end,
		onStart = function(autodrive)
			self:start(autodrive)
		end,
		seed = opts.seed,
		device = self.device,
	})

	-- Esc opens the Roblox menu; bring the interface back from photo mode
	GuiService.MenuOpened:Connect(function()
		self:setPhoto(false)
	end)
	self:refresh()
	return self
end

---------------------------------------------------------------------------
-- Toolbar
---------------------------------------------------------------------------
function App:_buildToolbar()
	local app = self.app
	local keys = (self.device.keyboard and Options.Keys) or {}
	local function tip(key: string, text: () -> string)
		return function()
			local k = keys[key]
			return k and (text() .. "   " .. k) or text()
		end
	end
	local function popover(id: string)
		return function()
			self:togglePopover(id)
		end
	end
	local items = {
		{
			id = "autodrive",
			label = "Autodrive",
			icon = "🛣️",
			tip = tip("autodrive", function()
				return app.get("autodrive") and "Autodrive is on" or "Autodrive"
			end),
			onClick = function()
				self.state.set("autodrive", not app.get("autodrive"))
			end,
		},
		{
			id = "camera",
			label = "Camera",
			icon = "🎥",
			tip = tip("camera", function()
				return "Camera: " .. app.get("camera")
			end),
			onClick = popover("camera"),
		},
		{
			id = "vehicle",
			label = "Vehicle",
			icon = Options.vehicleIcon(app.get("vehicle")),
			tip = tip("vehicle", function()
				return "Vehicle: " .. Vehicles.get(app.get("vehicle")).name
			end),
			onClick = popover("vehicle"),
		},
		"|",
		{
			id = "season",
			label = "Season",
			icon = "🍁",
			tip = tip("season", function()
				return "Season: " .. self:_autoText("season", "seasonNow")
			end),
			onClick = popover("season"),
		},
		{
			id = "weather",
			label = "Weather",
			icon = "☀️",
			tip = tip("weather", function()
				return "Weather: " .. self:_autoText("weather", "weatherNow")
			end),
			onClick = popover("weather"),
		},
		{
			id = "time",
			label = "Time",
			icon = "🌤️",
			tip = tip("time", function()
				return "Time of day: " .. Options.clockText(app.get("clock"))
			end),
			onClick = popover("time"),
		},
		"|",
		{
			id = "reset",
			label = "Reset",
			icon = "🔄",
			tip = tip("reset", function()
				return "Put the vehicle back on the road"
			end),
			onClick = function()
				app.reset()
			end,
		},
		{
			id = "photo",
			label = "Photo",
			icon = "📷",
			tip = tip("photo", function()
				return "Photo mode: hide the interface"
			end),
			onClick = function()
				self:setPhoto(true)
			end,
		},
		{
			id = "settings",
			label = "Settings",
			icon = "⚙️",
			tip = tip("settings", function()
				return "Settings"
			end),
			onClick = function()
				self:toggleSettings()
			end,
		},
	}
	self.toolbar = Toolbar.new(self.root, items, {
		tooltips = not self.device.touch,
		canTip = function()
			return self.openId == nil
		end,
	})

	-- "?" left of the toolbar: keyboard and gamepad shortcuts
	if self.device.keyboard or self.device.gamepad then
		local size = 36
		local help = Kit.button(self.toolbar.frame, {
			Name = "Help",
			Text = "?",
			Font = Theme.FontBold,
			TextSize = 17,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(0, -10, 0.5, 0),
			Size = UDim2.fromOffset(size, size),
		}, function()
			self:togglePopover("help")
		end)
		help:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
		Kit.tooltip(help, function()
			return "Keyboard and gamepad shortcuts"
		end, function()
			return self.openId == nil
		end)
		self.helpButton = help
		self.helpX = -(self.toolbar.width / 2 + 10 + size / 2)
	end
end

-- "Auto (Summer)" or "Summer"
function App:_autoText(key: string, nowKey: string): string
	local mode, now = self.app.get(key), self.app.get(nowKey)
	return mode == "Auto" and ("Auto (" .. tostring(now) .. ")") or tostring(now)
end

---------------------------------------------------------------------------
-- Popovers
---------------------------------------------------------------------------

--[[
	Registers a popover. build(panel) adds its content; statusText (optional)
	returns the grey text beside the title; fit(maxHeight) (optional) sizes
	scrolling content to the space above the toolbar.
]]
function App:_popover(id: string, title: string, width: number, build: (Frame) -> (), statusText: (() -> string)?, fit: ((number) -> ())?)
	local panel, status = Kit.popover(self.root, "Popover" .. id, title, width)
	build(panel)
	self.popovers[id] = {
		panel = panel,
		width = width,
		status = status,
		statusText = statusText,
		fit = fit,
		scale = Kit.new("UIScale", { Parent = panel }),
	}
end

function App:_buildPopovers()
	local state, app = self.state, self.app
	local function add(widget)
		table.insert(self.widgets, widget)
		return widget
	end

	self:_popover("camera", "Camera", 380, function(panel)
		add(Controls.camera(panel, state))
	end)

	self:_popover("season", "Season", 440, function(panel)
		add(Controls.season(panel, state))
	end, function()
		return "Now: " .. tostring(app.get("seasonNow"))
	end)

	self:_popover("weather", "Weather", 420, function(panel)
		add(Controls.weather(panel, state))
	end, function()
		return "Now: " .. tostring(app.get("weatherNow"))
	end)

	self:_popover("time", "Time of day", 380, function(panel)
		add(Controls.time(panel, state, 1))
		add(Controls.dayCycle(panel, state, 2))
	end, function()
		return Options.clockText(app.get("clock"))
	end)

	local vehicleScroll, pickerHeight = nil, 0
	self:_popover("vehicle", "Vehicle", PICKER_W + Theme.Pad * 2, function(panel)
		vehicleScroll = Kit.scroll(panel, { Name = "Scroll", LayoutOrder = 1 })
		local picker = add(VehiclePicker.new(vehicleScroll, {
			width = PICKER_W,
			get = function()
				return app.get("vehicle"), app.get("color")
			end,
			set = function(id, color)
				app.setVehicle(id, color)
				self:refresh()
			end,
		}))
		pickerHeight = picker.height
		vehicleScroll.Size = UDim2.new(1, 0, 0, pickerHeight)
	end, function()
		return Vehicles.get(app.get("vehicle")).name
	end, function(maxHeight)
		vehicleScroll.Size = UDim2.new(1, 0, 0, math.min(pickerHeight, maxHeight))
	end)

	local helpScroll, helpHeight = nil, 0
	self:_popover("help", "Shortcuts", 440, function(panel)
		helpScroll = Kit.scroll(panel, { Name = "Scroll", LayoutOrder = 1 })
		Kit.list(helpScroll, false, 4)
		local rows = { { "", "Keyboard", "Gamepad" } }
		for _, row in Options.Shortcuts do
			table.insert(rows, row)
		end
		for i, row in rows do
			self:_shortcutRow(helpScroll, i, row, i == 1)
		end
		helpHeight = #rows * 26 - 4
		helpScroll.Size = UDim2.new(1, 0, 0, helpHeight)
	end, nil, function(maxHeight)
		helpScroll.Size = UDim2.new(1, 0, 0, math.min(helpHeight, maxHeight))
	end)
end

function App:_shortcutRow(parent: Instance, order: number, row, heading: boolean)
	local frame = Kit.new("Frame", {
		Name = "Row" .. order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.text(frame, {
		Name = "Action",
		Text = row[1],
		Font = Theme.FontLight,
		TextSize = 13,
		TextXAlignment = LEFT,
		Size = UDim2.fromScale(0.42, 1),
	})
	for column = 2, 3 do
		local text = row[column]
		local cell = Kit.new("Frame", {
			Name = column == 2 and "Keyboard" or "Gamepad",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(column == 2 and 0.42 or 0.71, 0),
			Size = UDim2.fromScale(0.29, 1),
			Parent = frame,
		})
		if heading then
			Kit.caption(cell, text).Size = UDim2.fromScale(1, 1)
		elseif text ~= "" then
			local key = Kit.text(cell, {
				Name = "Key",
				Text = text,
				TextSize = 12,
				BackgroundColor3 = Theme.Surface,
				BackgroundTransparency = 0,
				Size = UDim2.fromOffset(0, 22),
				AutomaticSize = Enum.AutomaticSize.X,
			})
			Kit.corner(key, 5)
			Kit.padding(key, 0, 7)
			Kit.stroke(key)
		end
	end
end

function App:openPopover(id: string)
	local pop = self.popovers[id]
	if not pop then
		return
	end
	self:closeAll()
	local x = id == "help" and (self.helpX or 0) or self.toolbar:offset(id)
	local half = math.max(0, self.view.width / 2 - pop.width / 2 - Theme.Margin)
	pop.panel.Position = UDim2.new(0.5, math.clamp(x, -half, half), 1, -Theme.ToolbarReserve)
	if pop.fit then
		pop.fit(self.view.height - Theme.ToolbarReserve - Theme.Margin * 2 - Theme.Pad * 2 - 30)
	end
	pop.panel.Visible = true
	pop.scale.Scale = 0.94
	Kit.tween(pop.scale, { Scale = 1 }, Theme.Fast)
	self.openId = id
	self.toolbar:setOpen(id, true)
	self.scrim.Visible = true
	self:refresh()
end

function App:togglePopover(id: string)
	if self.openId == id then
		self:closeAll()
	else
		self:openPopover(id)
	end
end

-- Close any popover and the settings panel.
function App:closeAll()
	if self.openId then
		self.popovers[self.openId].panel.Visible = false
		self.toolbar:setOpen(self.openId, false)
		self.openId = nil
	end
	if self.settingsMenu.visible then
		self.settingsMenu:close()
		self.toolbar:setOpen("settings", false)
	end
	self.scrim.Visible = false
end

function App:toggleSettings()
	if self.settingsMenu.visible then
		self:closeAll()
		return
	end
	self:closeAll()
	self.settingsMenu:open()
	self.toolbar:setOpen("settings", true)
	self.scrim.Visible = true
	self:refresh()
end

---------------------------------------------------------------------------
-- Photo mode: hide everything; a click, tap or Esc brings it back
---------------------------------------------------------------------------
function App:_buildPhoto(parent: Instance)
	local gui, root = Kit.screen(parent, "InfiniteRoadPhoto", 9, true)
	gui.Enabled = false
	local exit = Kit.new("TextButton", {
		Name = "Exit",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	exit.Activated:Connect(function()
		self:setPhoto(false)
	end)
	local hint = Kit.panel(root, {
		Name = "Hint",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 28),
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
	})
	Kit.padding(hint, 0, 18)
	Kit.text(hint, {
		Name = "Text",
		Text = self.device.touch and "📷  Photo mode  ·  tap anywhere to bring the interface back"
			or "📷  Photo mode  ·  click anywhere or press Esc to bring the interface back",
		TextSize = 14,
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
	})
	self.photoGui, self.photoHint = gui, hint
end

function App:setPhoto(on: boolean)
	if on == self.photoOn or (on and not self.started) then
		return
	end
	self.photoOn = on
	if on then
		self:closeAll()
		self.gui.Enabled = false
		if self.hud then
			self.hud:setVisible(false)
		end
		self.photoGui.Enabled = true
		Kit.fade(self.photoHint, true)
		local token = {}
		self.photoToken = token
		task.delay(2.5, function()
			if self.photoToken == token and self.photoOn then
				Kit.fade(self.photoHint, false, Theme.Slow)
			end
		end)
	else
		self.photoToken = nil
		self.photoGui.Enabled = false
		self.gui.Enabled = true
		if self.hud then
			self.hud:setVisible(true)
		end
	end
end

function App:togglePhoto()
	self:setPhoto(not self.photoOn)
end

---------------------------------------------------------------------------
-- Start, keys, refresh
---------------------------------------------------------------------------

-- Leave the start screen and show the toolbar.
function App:start(autodrive: boolean?)
	if self.started then
		return
	end
	self.started = true
	self.app.start(autodrive == true)
	if self.startScreen then
		self.startScreen:close()
		self.startScreen = nil
	end
	self.gui.Enabled = true
	self.toolbar:slideIn()
	self:refresh()
end

-- Enter: start driving from the start screen.
function App:confirm()
	if not self.started then
		self:start(false)
	end
end

-- Esc: leave photo mode or close what is open. Returns whether it did.
function App:back(): boolean
	if self.photoOn then
		self:setPhoto(false)
		return true
	elseif self.openId or self.settingsMenu.visible then
		self:closeAll()
		return true
	end
	return false
end

function App:refresh()
	local get = self.app.get
	local toolbar = self.toolbar
	toolbar:setActive("autodrive", get("autodrive") == true)
	toolbar:setIcon("vehicle", Options.vehicleIcon(get("vehicle")))
	toolbar:setIcon("season", Options.SeasonIcons[get("seasonNow")] or "🍁")
	toolbar:setIcon("weather", Options.WeatherIcons[get("weatherNow")] or "☀️")
	local t = Options.nearestTime(get("clock"))
	toolbar:setIcon("time", t and t.icon or "🌤️")
	for _, widget in self.widgets do
		widget:refresh()
	end
	for _, pop in self.popovers do
		if pop.statusText then
			local text = pop.statusText()
			if pop.status.Text ~= text then
				pop.status.Text = text
			end
		end
	end
	self.settingsMenu:refresh()
	if self.startScreen then
		self.startScreen:refresh()
	end
end

return App
