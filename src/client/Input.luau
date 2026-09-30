--[[
	Input
	-----
	Driving input from keyboard, gamepad and touch, merged into
	throttle (-1..1), steer (-1..1) and handbrake. Everything else can be
	clicked in the interface (UI/App.luau); these keys are optional
	shortcuts for the same actions.

	Keyboard: W/S or arrows drive, A/D or arrows steer, Space handbrake,
	          F autodrive, C camera, R reset car, T time of day,
	          H photo mode, V next vehicle, N season, G weather,
	          M settings, F3 stats overlay, Enter start driving,
	          Esc close menus or leave photo mode.
	Gamepad:  RT/LT throttle/brake, left stick steer, A handbrake,
	          X autodrive, Y camera, B reset, D-pad up time of day,
	          D-pad down photo mode, D-pad left vehicle, D-pad right
	          weather, Select settings.
	Touch:    on-screen steering and pedals (Input:touchControls).
]]

local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.UI.Theme)
local Kit = require(script.Parent.UI.Kit)

local Input = {}
Input.__index = Input

local K = Enum.KeyCode

-- key name -> action name passed to the handlers registered with Input:on
local SHORTCUTS = {
	F = "autodrive",
	ButtonX = "autodrive",
	C = "camera",
	ButtonY = "camera",
	R = "reset",
	ButtonB = "reset",
	T = "time",
	DPadUp = "time",
	H = "photo",
	DPadDown = "photo",
	F3 = "stats",
	V = "vehicle",
	DPadLeft = "vehicle",
	N = "season",
	G = "weather",
	DPadRight = "weather",
	M = "menu",
	ButtonSelect = "menu",
	Return = "confirm",
	KeypadEnter = "confirm",
	Escape = "back",
}

function Input.new()
	local self = setmetatable({}, Input)
	self.handlers = {}
	self.gamepad = { throttle = 0, brake = 0, steer = 0 }
	self.touch = { gas = false, brake = false, left = false, right = false }
	self.holds = {}
	self.touchFrame = nil

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local action = SHORTCUTS[input.KeyCode.Name]
		if action then
			self:_fire(action)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		local kc = input.KeyCode
		if kc == K.ButtonR2 then
			self.gamepad.throttle = input.Position.Z
		elseif kc == K.ButtonL2 then
			self.gamepad.brake = input.Position.Z
		elseif kc == K.Thumbstick1 then
			local x = input.Position.X
			self.gamepad.steer = math.abs(x) > 0.12 and x or 0
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local kc = input.KeyCode
		if kc == K.ButtonR2 then
			self.gamepad.throttle = 0
		elseif kc == K.ButtonL2 then
			self.gamepad.brake = 0
		elseif kc == K.Thumbstick1 then
			self.gamepad.steer = 0
		end
	end)
	return self
end

function Input:on(name: string, fn)
	self.handlers[name] = fn
end

function Input:_fire(name: string)
	local fn = self.handlers[name]
	if fn then
		fn()
	end
end

--[[
	On-screen steering (bottom left) and pedals (bottom right) for touch
	screens, built into `parent` (the interface's scaled root). They sit
	above Theme.ToolbarReserve, so they never cover the toolbar.
]]
function Input:touchControls(parent: Instance): Frame
	local frame = Kit.new("Frame", {
		Name = "TouchControls",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = parent,
	})
	local size, gap, m = 88, 12, Theme.Margin
	local bottom = -Theme.ToolbarReserve
	local buttons = {
		{ name = "Left", text = "◀", field = "left", anchor = Vector2.new(0, 1), position = UDim2.new(0, m, 1, bottom), height = size },
		{ name = "Right", text = "▶", field = "right", anchor = Vector2.new(0, 1), position = UDim2.new(0, m + size + gap, 1, bottom), height = size },
		{ name = "Brake", text = "BRAKE", field = "brake", anchor = Vector2.new(1, 1), position = UDim2.new(1, -(m + size + gap), 1, bottom), height = size },
		{ name = "Gas", text = "GAS", field = "gas", anchor = Vector2.new(1, 1), position = UDim2.new(1, -m, 1, bottom), height = size + 32 },
	}
	for _, b in buttons do
		local button = Kit.new("TextButton", {
			Name = b.name,
			AutoButtonColor = false,
			AnchorPoint = b.anchor,
			Position = b.position,
			Size = UDim2.fromOffset(size, b.height),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Font = Theme.FontBold,
			TextSize = utf8.len(b.text) > 1 and 15 or 24,
			TextColor3 = Theme.Text,
			Text = b.text,
			Parent = frame,
		})
		Kit.corner(button, 18)
		Kit.stroke(button, nil, 0.8)
		self:_hold(button, b.field)
	end
	-- a finger lifted after sliding off its button still lets go
	UserInputService.TouchEnded:Connect(function(touch)
		self:_release(touch)
	end)
	self.touchFrame = frame
	return frame
end

-- Hold `button` to set self.touch[field]; several fingers can hold it.
function Input:_hold(button: TextButton, field: string)
	local touches = {}
	local function update()
		local held = next(touches) ~= nil
		self.touch[field] = held
		Kit.tween(button, {
			BackgroundColor3 = held and Theme.Accent or Theme.Panel,
			TextColor3 = held and Theme.OnAccent or Theme.Text,
		}, 0.06)
	end
	button.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
			touches[input] = true
			update()
		end
	end)
	button.InputEnded:Connect(function(input)
		if touches[input] then
			touches[input] = nil
			update()
		end
	end)
	table.insert(self.holds, { touches = touches, update = update })
end

function Input:_release(input)
	for _, hold in self.holds do
		if hold.touches[input] then
			hold.touches[input] = nil
			hold.update()
		end
	end
end

-- Current driving input.
function Input:read(): (number, number, boolean)
	local throttle, steer = 0, 0
	local kb = UserInputService:GetFocusedTextBox() == nil
	if kb then
		if UserInputService:IsKeyDown(K.W) or UserInputService:IsKeyDown(K.Up) then
			throttle += 1
		end
		if UserInputService:IsKeyDown(K.S) or UserInputService:IsKeyDown(K.Down) then
			throttle -= 1
		end
		if UserInputService:IsKeyDown(K.D) or UserInputService:IsKeyDown(K.Right) then
			steer += 1
		end
		if UserInputService:IsKeyDown(K.A) or UserInputService:IsKeyDown(K.Left) then
			steer -= 1
		end
	end
	local gp = self.gamepad
	throttle += gp.throttle - gp.brake
	steer += gp.steer
	local t = self.touch
	if t.gas then
		throttle += 1
	end
	if t.brake then
		throttle -= 1
	end
	if t.right then
		steer += 1
	end
	if t.left then
		steer -= 1
	end
	local handbrake = (kb and UserInputService:IsKeyDown(K.Space)) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, K.ButtonA)
	return math.clamp(throttle, -1, 1), math.clamp(steer, -1, 1), handbrake
end

return Input
