--[[ Notifications - toast messages (top right) + big announcement banners ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local Theme = UIKit.Theme

local Notifications = {}
local C
local holder: Frame
local bannerQueue = {}
local bannerBusy = false

local TYPE_COLORS = {
	success = Theme.Green,
	error = Theme.Red,
	info = Theme.Accent2,
	warning = Theme.Accent,
}
local TYPE_ICONS = {
	success = "✅",
	error = "❌",
	info = "💬",
	warning = "⚠️",
}

function Notifications:Init(controllers)
	C = controllers
	holder = UIKit.new("Frame", {
		Name = "Toasts",
		Size = UDim2.new(0, 340, 1, -80),
		Position = UDim2.new(1, -16, 0, 70),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = C.UI.FX,
	})
	local layout = UIKit.List(holder, 8, Enum.FillDirection.Vertical, Enum.HorizontalAlignment.Right)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top

	Remotes.Notify.OnClientEvent:Connect(function(data)
		self:Toast(data.Text, data.Type, data.Duration)
	end)
	Remotes.Announce.OnClientEvent:Connect(function(data)
		self:Banner(data.Title, data.Text, data.Color)
	end)
end

local order = 0
function Notifications:Toast(text: string, kind: string?, duration: number?)
	kind = kind or "info"
	order += 1
	local color = TYPE_COLORS[kind] or Theme.Accent2
	local frame = UIKit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		LayoutOrder = order,
		Parent = holder,
	})
	UIKit.Corner(frame, 10)
	UIKit.Stroke(frame, color, 2.5)
	UIKit.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = frame })
	UIKit.new("Frame", { Size = UDim2.new(0, 5, 1, 0), Position = UDim2.new(0, -8, 0, 0), BackgroundColor3 = color, BorderSizePixel = 0, Parent = frame })
	local label = UIKit.new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = (TYPE_ICONS[kind] or "") .. "  " .. tostring(text),
		TextWrapped = true,
		TextSize = 17,
		Font = Theme.BodyFont,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	local scale = UIKit.new("UIScale", { Scale = 0.5, Parent = frame })
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	UIKit.PlaySound(kind == "error" and "Error" or "Notify", kind == "error" and 0.3 or 0.25)

	-- keep the list short
	local toasts = {}
	for _, child in holder:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 5 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end

	task.delay(duration or 4, function()
		if not frame.Parent then
			return
		end
		TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 }):Play()
		TweenService:Create(frame, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		task.wait(0.25)
		frame:Destroy()
	end)
end

function Notifications:Banner(title: string, text: string?, color: Color3?)
	table.insert(bannerQueue, { title, text, color })
	if bannerBusy then
		return
	end
	bannerBusy = true
	while #bannerQueue > 0 do
		local item = table.remove(bannerQueue, 1)
		self:_showBanner(item[1], item[2], item[3])
	end
	bannerBusy = false
end

function Notifications:_showBanner(title: string, text: string?, color: Color3?)
	color = color or Theme.Accent
	local frame = UIKit.new("Frame", {
		Size = UDim2.new(0.6, 0, 0, 96),
		Position = UDim2.new(0.5, 0, 0, -120),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Panel,
		Parent = C.UI.FX,
	})
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(720, 96), MinSize = Vector2.new(300, 80), Parent = frame })
	UIKit.Corner(frame, 16)
	UIKit.Stroke(frame, color :: Color3, 3)
	UIKit.Gradient(frame, Theme.PanelLight, Theme.Panel, 90)
	local shine = UIKit.new("Frame", { Size = UDim2.new(0.25, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, BorderSizePixel = 0, Parent = frame })
	UIKit.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) }), Parent = shine })
	frame.ClipsDescendants = true
	UIKit.Label({ Text = title, Size = UDim2.new(1, -24, 0, 44), Position = UDim2.fromOffset(12, 8), TextColor3 = color, Parent = frame })
	UIKit.Label({ Text = text or "", Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 54), Font = Theme.BodyFont, TextColor3 = Theme.Text, Parent = frame })
	UIKit.PlaySound("Notify", 0.4, 0.8)

	TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	shine.Position = UDim2.new(-0.3, 0, 0, 0)
	TweenService:Create(shine, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Position = UDim2.new(1.1, 0, 0, 0) }):Play()
	task.wait(4.5)
	local out = TweenService:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -130) })
	out:Play()
	out.Completed:Wait()
	frame:Destroy()
end

return Notifications
