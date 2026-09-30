--[[
	Theme
	-----
	Colours, fonts, sizes and timings shared by every screen, so the HUD,
	toolbar, popovers and menus look like one piece: dark semi-transparent
	panels, rounded corners, a faint outline and one accent colour.

	Sizes are in "base" pixels. Every screen sits under a UIScale that fits
	a RefWidth x RefHeight layout onto the real screen (see Kit.screen).
]]

local rgb = Color3.fromRGB

local Theme = {}

-- colours
Theme.Accent = rgb(255, 186, 66)
Theme.OnAccent = rgb(28, 24, 18) -- text on the accent colour
Theme.Panel = rgb(14, 17, 22)
Theme.PanelTransparency = 0.2
Theme.Surface = rgb(40, 45, 55) -- chips, cards and buttons on a panel
Theme.SurfaceHover = rgb(58, 64, 77)
Theme.Stroke = rgb(255, 255, 255)
Theme.StrokeTransparency = 0.88
Theme.Text = rgb(242, 244, 247)
Theme.TextDim = rgb(160, 168, 181)
Theme.Backdrop = rgb(10, 12, 16) -- loading screen and start screen dimming

-- fonts
Theme.FontBold = Enum.Font.GothamBold
Theme.Font = Enum.Font.GothamMedium
Theme.FontLight = Enum.Font.Gotham
Theme.FontMono = Enum.Font.RobotoMono

-- spacing
Theme.Radius = 12
Theme.RadiusSmall = 8
Theme.Pad = 14
Theme.Gap = 8
Theme.Margin = 16

-- tween times (seconds)
Theme.Fast = 0.12
Theme.Normal = 0.2
Theme.Slow = 0.45

-- screen fitting: phones and tablets keep a larger minimum so text and
-- buttons stay big enough for fingers; MinViewWidth always fits the toolbar
Theme.RefWidth = 1100
Theme.RefHeight = 660
Theme.MinScale = 0.65
Theme.TouchMinScale = 0.8
Theme.MaxScale = 1.25
Theme.MinViewWidth = 780

-- bottom toolbar; other bottom UI (toasts, touch pedals, popovers) stays
-- above ToolbarReserve
Theme.ToolbarButtonWidth = 74
Theme.ToolbarButtonHeight = 60
Theme.ToolbarPad = 6
Theme.ToolbarBottom = 12
Theme.ToolbarHeight = Theme.ToolbarButtonHeight + Theme.ToolbarPad * 2
Theme.ToolbarReserve = Theme.ToolbarBottom + Theme.ToolbarHeight + 10

-- chips and rows
Theme.ChipHeight = 36
Theme.ToggleHeight = 44
Theme.LabelHeight = 16

return Theme
