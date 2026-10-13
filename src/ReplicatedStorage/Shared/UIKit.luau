--[[
	UIKit - tiny helper library for building good-looking UI from code.
	Client only.
]]
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Config = require(script.Parent.Config)

local UIKit = {}

UIKit.Theme = {
	Background = Color3.fromRGB(22, 24, 36),
	Panel = Color3.fromRGB(32, 35, 52),
	PanelLight = Color3.fromRGB(46, 50, 74),
	Accent = Color3.fromRGB(255, 196, 0),
	Accent2 = Color3.fromRGB(0, 200, 255),
	Green = Color3.fromRGB(60, 210, 100),
	Red = Color3.fromRGB(235, 70, 70),
	Purple = Color3.fromRGB(150, 80, 255),
	Text = Color3.fromRGB(255, 255, 255),
	SubText = Color3.fromRGB(180, 185, 210),
	Font = Enum.Font.FredokaOne,
	BodyFont = Enum.Font.GothamBold,
}

local soundCache: { [string]: Sound } = {}

function UIKit.PlaySound(name: string, volume: number?, pitch: number?)
	local id = Config.Sounds[name] or name
	if not id or id == "" then
		return
	end
	local key = id .. tostring(pitch or 1)
	local sound = soundCache[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = volume or 0.5
		sound.PlaybackSpeed = pitch or 1
		sound.Parent = SoundService
		soundCache[key] = sound
	end
	if UIKit.SFXEnabled == false then
		return
	end
	sound.Volume = volume or 0.5
	SoundService:PlayLocalSound(sound)
end

UIKit.SFXEnabled = true

function UIKit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function UIKit.Corner(parent: Instance, radius: number?)
	return UIKit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12), Parent = parent })
end

function UIKit.Stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return UIKit.new("UIStroke", {
		Color = color or Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function UIKit.TextStroke(parent: Instance, thickness: number?)
	return UIKit.new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
end

function UIKit.Gradient(parent: Instance, a: Color3, b: Color3, rotation: number?)
	return UIKit.new("UIGradient", {
		Color = ColorSequence.new(a, b),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

function UIKit.Padding(parent: Instance, px: number)
	return UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function UIKit.List(parent: Instance, padding: number?, direction: Enum.FillDirection?, align: Enum.HorizontalAlignment?)
	return UIKit.new("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = direction or Enum.FillDirection.Vertical,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function UIKit.Label(props: { [string]: any })
	local label = UIKit.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = UIKit.Theme.Font,
		TextColor3 = UIKit.Theme.Text,
		TextScaled = true,
		Text = "",
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "Stroke" then
			label[k] = v
		end
	end
	if props.Stroke ~= false then
		UIKit.TextStroke(label, 1.5)
	end
	label.Parent = props.Parent
	return label
end

-- A chunky "game style" button with hover + press animation and click sound
function UIKit.Button(props: { [string]: any })
	local color: Color3 = props.Color or UIKit.Theme.Accent
	local button = UIKit.new("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(160, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = props.Text or "",
		Font = UIKit.Theme.Font,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = true,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
	})
	UIKit.Corner(button, props.Radius or 10)
	UIKit.Stroke(button, Color3.new(0, 0, 0), 2.5, 0.2)
	UIKit.TextStroke(button, 1.5)
	local h, s, v = color:ToHSV()
	UIKit.Gradient(button, Color3.fromHSV(h, s * 0.7, math.min(v * 1.15, 1)), Color3.fromHSV(h, s, v * 0.8), 90)
	UIKit.new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = button,
	})
	local scale = UIKit.new("UIScale", { Parent = button })
	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, info, { Scale = 1.06 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, info, { Scale = 0.94 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, info, { Scale = 1.06 }):Play()
	end)
	if props.Callback then
		button.Activated:Connect(function()
			UIKit.PlaySound("Click", 0.5)
			props.Callback()
		end)
	end
	button.Parent = props.Parent
	return button
end

-- Centered popup panel with title + close button. Returns (frame, content)
function UIKit.Panel(props: { [string]: any })
	local frame = UIKit.new("Frame", {
		Name = props.Name or "Panel",
		Size = props.Size or UDim2.fromOffset(520, 420),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UIKit.Theme.Panel,
		Visible = false,
		ZIndex = 5,
	})
	UIKit.Corner(frame, 18)
	UIKit.Stroke(frame, Color3.new(0, 0, 0), 4, 0.1)
	UIKit.Gradient(frame, UIKit.Theme.PanelLight, UIKit.Theme.Panel, 90)
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(props.MaxWidth or 900, 800), Parent = frame })
	UIKit.new("UIScale", { Name = "PopScale", Parent = frame })

	local header = UIKit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = props.Color or UIKit.Theme.Accent,
		ZIndex = 6,
		Parent = frame,
	})
	UIKit.Corner(header, 18)
	local hcolor: Color3 = props.Color or UIKit.Theme.Accent
	local h, s, v = hcolor:ToHSV()
	UIKit.Gradient(header, Color3.fromHSV(h, s * 0.6, math.min(1, v * 1.2)), hcolor, 90)
	-- square off the bottom corners of the header
	UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 1, -18),
		BackgroundColor3 = hcolor,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = header,
	})
	UIKit.Label({
		Text = props.Title or "Panel",
		Size = UDim2.new(1, -120, 0, 40),
		Position = UDim2.fromOffset(20, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = header,
	})
	local close = UIKit.Button({
		Name = "Close",
		Text = "X",
		Color = UIKit.Theme.Red,
		Size = UDim2.fromOffset(42, 42),
		Position = UDim2.new(1, -50, 0, 7),
		ZIndex = 7,
		Parent = header,
	})

	local content = UIKit.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -24, 1, -72),
		Position = UDim2.fromOffset(12, 64),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = frame,
	})
	frame.Parent = props.Parent
	return frame, content, close
end

function UIKit.Scroll(props: { [string]: any })
	local scroll = UIKit.new("ScrollingFrame", {
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = UIKit.Theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ZIndex = props.ZIndex or 6,
	})
	scroll.Parent = props.Parent
	return scroll
end

function UIKit.TextBox(props: { [string]: any })
	local box = UIKit.new("TextBox", {
		Size = props.Size or UDim2.fromOffset(200, 40),
		Position = props.Position or UDim2.new(),
		BackgroundColor3 = UIKit.Theme.Background,
		PlaceholderText = props.Placeholder or "",
		PlaceholderColor3 = UIKit.Theme.SubText,
		Text = props.Text or "",
		Font = UIKit.Theme.BodyFont,
		TextColor3 = UIKit.Theme.Text,
		TextScaled = true,
		ClearTextOnFocus = props.ClearTextOnFocus or false,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 6,
	})
	UIKit.Corner(box, 8)
	UIKit.Stroke(box, UIKit.Theme.PanelLight, 2)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = box })
	box.Parent = props.Parent
	return box
end

-- Pop a panel open / closed with a bouncy tween
function UIKit.Open(frame: GuiObject)
	local scale = frame:FindFirstChild("PopScale") :: UIScale?
	frame.Visible = true
	if scale then
		scale.Scale = 0.6
		TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	UIKit.PlaySound("Whoosh", 0.25, 1.4)
end

function UIKit.Close(frame: GuiObject)
	local scale = frame:FindFirstChild("PopScale") :: UIScale?
	if scale then
		local tween = TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.6 })
		tween:Play()
		tween.Completed:Once(function()
			if scale.Scale <= 0.61 then
				frame.Visible = false
			end
		end)
	else
		frame.Visible = false
	end
end

return UIKit
