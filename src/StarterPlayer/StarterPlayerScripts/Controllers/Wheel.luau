--[[
	Wheel (client) - the Lucky Wheel panel. A reel of prize cards scrolls past
	a pointer and slows down on the prize the server picked.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme
local WC = Config.Wheel

local Wheel = {}
Wheel.Spinning = false
local C

local CARD_W = 120
local CARDS = 40
local WIN_AT = 34 -- the card that stops under the pointer

local reel: Frame
local strip: Frame
local spinButton: TextButton
local infoLabel: TextLabel

-- a random segment, weighted like the server's pick (for the filler cards)
local function randomSegment()
	local total = 0
	for _, segment in WC.Segments do
		total += segment.Weight
	end
	local roll = math.random() * total
	for _, segment in WC.Segments do
		roll -= segment.Weight
		if roll < 0 then
			return segment
		end
	end
	return WC.Segments[1]
end

local function buildStrip(winIndex: number)
	strip:ClearAllChildren()
	for i = 1, CARDS do
		local segment = i == WIN_AT and WC.Segments[winIndex] or randomSegment()
		local card = UIKit.new("Frame", {
			Name = "Card" .. i,
			Size = UDim2.new(0, CARD_W - 8, 1, -16),
			Position = UDim2.fromOffset((i - 1) * CARD_W + 4, 8),
			BackgroundColor3 = segment.Color,
			Parent = strip,
		})
		UIKit.Corner(card, 10)
		UIKit.Stroke(card, Color3.new(0, 0, 0), 2, 0.3)
		UIKit.Label({ Text = segment.Icon, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 8), Parent = card })
		UIKit.Label({ Text = segment.Name, Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 62), Font = Theme.BodyFont, Parent = card })
	end
	strip.Position = UDim2.fromOffset(0, 0)
end

function Wheel:IsReady(): boolean
	return Util.ServerNow() >= (player:GetAttribute("WheelReadyAt") or math.huge)
end

local function refresh()
	local readyAt = player:GetAttribute("WheelReadyAt")
	if not readyAt then
		spinButton.Text = "..."
		return
	end
	local left = readyAt - Util.ServerNow()
	if Wheel.Spinning then
		spinButton.Text = "SPINNING..."
		spinButton.BackgroundColor3 = Theme.PanelLight
	elseif left <= 0 then
		spinButton.Text = "🎰 SPIN!"
		spinButton.BackgroundColor3 = Theme.Green
		infoLabel.Text = "Your free spin is ready!"
	else
		spinButton.Text = "Next spin in " .. Util.Clock(left)
		spinButton.BackgroundColor3 = Theme.PanelLight
		infoLabel.Text = "A free spin every " .. (player:GetAttribute("Pass_WheelPlus") and WC.CooldownMinutes / 2 or WC.CooldownMinutes) .. " minutes - it keeps counting while you're away."
	end
	if C.HUD and C.HUD.SetBadge then
		C.HUD:SetBadge("Wheel", left <= 0 and not Wheel.Spinning)
	end
end

local function spin()
	if Wheel.Spinning then
		return
	end
	if not Wheel:IsReady() then
		C.Notifications:Toast("Your next free spin isn't ready yet!", "error")
		return
	end
	Wheel.Spinning = true
	refresh()
	local ok, index, message = Remotes.SpinWheel:InvokeServer()
	if not ok or not WC.Segments[index] then
		Wheel.Spinning = false
		C.Notifications:Toast(tostring(message), "error")
		refresh()
		return
	end
	buildStrip(index)
	-- stop somewhere inside the winning card
	local stopAt = reel.AbsoluteSize.X / 2 - ((WIN_AT - 1) * CARD_W + CARD_W / 2) + math.random(-30, 30)
	UIKit.PlaySound("Notify", 0.5, 0.8)
	TweenService:Create(strip, TweenInfo.new(WC.SpinSeconds, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(stopAt, 0) }):Play()
	task.delay(WC.SpinSeconds, function()
		Wheel.Spinning = false
		UIKit.PlaySound("Notify", 0.7, 1.4)
		C.Notifications:Toast(tostring(message), "success")
		refresh()
	end)
end

function Wheel:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Wheel", "🎰 LUCKY WHEEL", Color3.fromRGB(255, 120, 60), 600, 400)
	UIKit.List(content, 14)
	infoLabel = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 34), Font = Theme.BodyFont, TextColor3 = Theme.SubText, LayoutOrder = 1, ZIndex = 7, Parent = content })
	reel = UIKit.new("Frame", { Name = "Reel", Size = UDim2.new(1, -10, 0, 120), BackgroundColor3 = Theme.Background, ClipsDescendants = true, LayoutOrder = 2, ZIndex = 7, Parent = content })
	UIKit.Corner(reel, 12)
	UIKit.Stroke(reel, Color3.new(0, 0, 0), 3)
	strip = UIKit.new("Frame", { Name = "Strip", Size = UDim2.fromOffset(CARD_W * CARDS, 120), BackgroundTransparency = 1, ZIndex = 8, Parent = reel })
	UIKit.new("Frame", { Name = "Pointer", Size = UDim2.new(0, 4, 1, 0), Position = UDim2.fromScale(0.5, 0), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Theme.Accent, ZIndex = 12, Parent = reel })
	buildStrip(1)
	spinButton = UIKit.Button({
		Name = "SpinButton",
		Text = "...",
		Color = Theme.Green,
		Size = UDim2.fromOffset(300, 56),
		LayoutOrder = 3,
		ZIndex = 7,
		Parent = content,
		Callback = spin,
	})
	-- the prizes
	local prizes = {}
	for _, segment in WC.Segments do
		table.insert(prizes, segment.Icon .. " " .. segment.Name)
	end
	UIKit.new("TextLabel", {
		Text = "Prizes: " .. table.concat(prizes, "  ·  "),
		Size = UDim2.new(1, -20, 0, 44),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 14,
		Font = Theme.BodyFont,
		TextColor3 = Theme.SubText,
		LayoutOrder = 4,
		ZIndex = 7,
		Parent = content,
	})
	player:GetAttributeChangedSignal("WheelReadyAt"):Connect(refresh)
	refresh()
end

function Wheel:Start()
	while true do
		task.wait(1)
		Util.Try("Wheel", refresh)
	end
end

return Wheel
