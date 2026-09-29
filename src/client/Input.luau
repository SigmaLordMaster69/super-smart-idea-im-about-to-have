--[[
	Input
	-----
	Driving input from keyboard, gamepad and touch, merged into
	throttle (-1..1), steer (-1..1) and handbrake.

	Keyboard: W/S or arrows drive, A/D or arrows steer, Space handbrake,
	          F autodrive, C camera, R reset car, T time of day, H hide HUD.
	Gamepad:  RT/LT throttle/brake, left stick steer, A handbrake,
	          X autodrive, Y camera, B reset.
	Touch:    on-screen buttons.
]]

local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Input = {}
Input.__index = Input

local K = Enum.KeyCode

function Input.new()
	local self = setmetatable({}, Input)
	self.handlers = {}
	self.gamepad = { throttle = 0, brake = 0, steer = 0 }
	self.touch = { gas = false, brake = false, left = false, right = false }

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local kc = input.KeyCode
		if kc == K.F or kc == K.ButtonX then
			self:_fire("autodrive")
		elseif kc == K.C or kc == K.ButtonY then
			self:_fire("camera")
		elseif kc == K.R or kc == K.ButtonB then
			self:_fire("reset")
		elseif kc == K.T or kc == K.DPadUp then
			self:_fire("time")
		elseif kc == K.H or kc == K.DPadDown then
			self:_fire("hud")
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

	if UserInputService.TouchEnabled then
		self:_touchButtons()
	end
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

function Input:_touchButtons()
	local function hold(field)
		return function(_, state)
			self.touch[field] = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
			return Enum.ContextActionResult.Sink
		end
	end
	local function tap(event)
		return function(_, state)
			if state == Enum.UserInputState.Begin then
				self:_fire(event)
			end
			return Enum.ContextActionResult.Sink
		end
	end
	local buttons = {
		{ "IR_Gas", hold("gas"), "GAS", UDim2.new(1, -95, 1, -120) },
		{ "IR_Brake", hold("brake"), "BRAKE", UDim2.new(1, -190, 1, -95) },
		{ "IR_Left", hold("left"), "<", UDim2.new(0, 30, 1, -110) },
		{ "IR_Right", hold("right"), ">", UDim2.new(0, 125, 1, -110) },
		{ "IR_Auto", tap("autodrive"), "AUTO", UDim2.new(1, -95, 1, -215) },
		{ "IR_Cam", tap("camera"), "CAM", UDim2.new(1, -190, 1, -190) },
		{ "IR_Reset", tap("reset"), "RESET", UDim2.new(1, -95, 0, 70) },
	}
	for _, b in buttons do
		ContextActionService:BindAction(b[1], b[2], true)
		ContextActionService:SetTitle(b[1], b[3])
		ContextActionService:SetPosition(b[1], b[4])
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
