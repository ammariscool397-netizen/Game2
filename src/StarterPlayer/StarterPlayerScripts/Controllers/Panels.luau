--[[ Panels - Rebirth, Daily Rewards, Codes and Settings menus ]]
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

local Panels = {}
local C

---------------------------------------------------------------------------
local function buildRebirth()
	local _, content = C.UI:MakePanel("Rebirth", "🔄 REBIRTH", Theme.Purple, 560, 440)
	UIKit.List(content, 12)
	local current = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, ZIndex = 7, Parent = content })
	local arrow = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2, TextColor3 = Color3.fromRGB(120, 255, 150), ZIndex = 7, Parent = content })
	UIKit.new("TextLabel", {
		Text = "Rebirthing resets your cash and tycoon, but gives you a PERMANENT cash multiplier.",
		Size = UDim2.new(1, -20, 0, 44),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 16,
		Font = Theme.BodyFont,
		TextColor3 = Theme.SubText,
		LayoutOrder = 3,
		ZIndex = 7,
		Parent = content,
	})
	local barBack = UIKit.new("Frame", { Size = UDim2.new(0.9, 0, 0, 34), BackgroundColor3 = Theme.Background, LayoutOrder = 4, ZIndex = 7, Parent = content })
	UIKit.Corner(barBack, 10)
	UIKit.Stroke(barBack, Color3.new(0, 0, 0), 2)
	local barFill = UIKit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Purple, ZIndex = 8, Parent = barBack })
	UIKit.Corner(barFill, 10)
	UIKit.Gradient(barFill, Color3.fromRGB(220, 160, 255), Theme.Purple, 90)
	local barText = UIKit.Label({ Text = "", Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), ZIndex = 9, Parent = barBack })

	local confirming = false
	local button
	button = UIKit.Button({
		Text = "REBIRTH",
		Color = Theme.Purple,
		Size = UDim2.fromOffset(240, 56),
		LayoutOrder = 5,
		ZIndex = 7,
		Parent = content,
		Callback = function()
			local cash = player:GetAttribute("Cash") or 0
			local cost = player:GetAttribute("RebirthCost") or math.huge
			if cash < cost then
				C.Notifications:Toast("You need " .. Util.Money(cost - cash) .. " more!", "error")
				return
			end
			if not confirming then
				confirming = true
				button.Text = "ARE YOU SURE?"
				task.delay(3, function()
					confirming = false
					button.Text = "REBIRTH"
				end)
				return
			end
			confirming = false
			button.Text = "REBIRTH"
			Remotes.RequestRebirth:FireServer()
			C.UI:Close()
		end,
	})

	local function refresh()
		local rebirths = player:GetAttribute("Rebirths") or 0
		local per = Config.Rebirth.MultiplierPerRebirth
		local cost = player:GetAttribute("RebirthCost") or Config.GetRebirthCost(rebirths)
		local cash = player:GetAttribute("Cash") or 0
		current.Text = "Rebirths: " .. rebirths
		arrow.Text = string.format("x%s  ➜  x%s rebirth bonus", tostring(1 + rebirths * per), tostring(1 + (rebirths + 1) * per))
		local alpha = math.clamp(cash / cost, 0, 1)
		TweenService:Create(barFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(alpha, 1) }):Play()
		barText.Text = Util.Money(cash) .. " / " .. Util.Money(cost)
		button.BackgroundColor3 = alpha >= 1 and Theme.Purple or Color3.fromRGB(90, 90, 110)
	end
	player:GetAttributeChangedSignal("Cash"):Connect(refresh)
	player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
	C.UI.Panels.Rebirth.OnOpen = refresh
	refresh()
end

---------------------------------------------------------------------------
local function buildDaily()
	local _, content = C.UI:MakePanel("Daily", "🎁 DAILY REWARDS", Color3.fromRGB(255, 90, 120), 760, 420)
	local row = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 170), BackgroundTransparency = 1, ZIndex = 6, Parent = content })
	local layout = UIKit.List(row, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	local cards = {}
	for day, amount in Config.Daily.Rewards do
		local cardFrame = UIKit.new("Frame", { Size = UDim2.new(1 / #Config.Daily.Rewards, -8, 0, 150), BackgroundColor3 = Theme.PanelLight, LayoutOrder = day, ZIndex = 7, Parent = row })
		UIKit.Corner(cardFrame, 12)
		local stroke = UIKit.Stroke(cardFrame, Theme.Background, 3)
		UIKit.Label({ Text = "Day " .. day, Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 6), ZIndex = 8, Parent = cardFrame })
		UIKit.Label({ Text = day == #Config.Daily.Rewards and "💎" or "💵", Size = UDim2.new(1, 0, 0, 50), Position = UDim2.fromOffset(0, 36), ZIndex = 8, Parent = cardFrame })
		UIKit.Label({ Text = Util.Money(amount), Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 100), TextColor3 = Color3.fromRGB(120, 255, 150), ZIndex = 8, Parent = cardFrame })
		cards[day] = { Frame = cardFrame, Stroke = stroke }
	end
	local status = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 184), Font = Theme.BodyFont, ZIndex = 7, Parent = content })
	UIKit.Label({
		Text = "Rewards scale with your rebirths. VIP gets double!",
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 216),
		Font = Theme.BodyFont,
		TextColor3 = Theme.SubText,
		ZIndex = 7,
		Parent = content,
	})
	local claim = UIKit.Button({
		Text = "CLAIM",
		Color = Theme.Green,
		Size = UDim2.fromOffset(240, 56),
		Position = UDim2.new(0.5, 0, 0, 250),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 7,
		Parent = content,
		Callback = function()
			local ok, message = Remotes.ClaimDaily:InvokeServer()
			C.Notifications:Toast(message, ok and "success" or "error")
		end,
	})

	local function refresh()
		local streak = player:GetAttribute("DailyStreak") or 0
		local last = player:GetAttribute("LastDaily") or 0
		local since = os.time() - last
		local available = since >= Config.Daily.Cooldown
		local nextDay = streak
		if available then
			nextDay = since > Config.Daily.StreakResetAfter and 1 or streak + 1
		end
		local highlight = ((math.max(nextDay, 1) - 1) % #Config.Daily.Rewards) + 1
		for day, cardInfo in cards do
			cardInfo.Stroke.Color = day == highlight and Theme.Accent or Theme.Background
			cardInfo.Frame.BackgroundColor3 = day == highlight and Color3.fromRGB(70, 60, 30) or Theme.PanelLight
		end
		if available then
			status.Text = "Your reward is ready! 🎉"
			claim.Text = "CLAIM"
			claim.BackgroundColor3 = Theme.Green
		else
			status.Text = "Streak: " .. streak .. " days"
			claim.Text = Util.FormatTime(Config.Daily.Cooldown - since)
			claim.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
		end
	end
	C.UI.Panels.Daily.OnOpen = function()
		while C.UI.Current == "Daily" do
			refresh()
			task.wait(1)
		end
	end
	refresh()
end

---------------------------------------------------------------------------
local function buildCodes()
	local _, content = C.UI:MakePanel("Codes", "🎟️ CODES", Theme.Accent2, 520, 340)
	UIKit.List(content, 14)
	UIKit.Label({ Text = "Enter a code for free rewards!", Size = UDim2.new(1, 0, 0, 30), Font = Theme.BodyFont, LayoutOrder = 1, ZIndex = 7, Parent = content })
	local box = UIKit.TextBox({ Placeholder = "Type code here...", Size = UDim2.new(0.85, 0, 0, 50), LayoutOrder = 2, ZIndex = 7, Parent = content })
	local result = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 26), Font = Theme.BodyFont, LayoutOrder = 4, ZIndex = 7, Parent = content })
	UIKit.Button({
		Text = "REDEEM",
		Color = Theme.Accent2,
		Size = UDim2.fromOffset(220, 52),
		LayoutOrder = 3,
		ZIndex = 7,
		Parent = content,
		Callback = function()
			if box.Text == "" then
				return
			end
			local ok, message = Remotes.RedeemCode:InvokeServer(box.Text)
			result.Text = message
			result.TextColor3 = ok and Theme.Green or Theme.Red
			if ok then
				box.Text = ""
			end
		end,
	})
	UIKit.Label({ Text = "Follow the game for new codes!", Size = UDim2.new(1, 0, 0, 20), Font = Theme.BodyFont, TextColor3 = Theme.SubText, LayoutOrder = 5, ZIndex = 7, Parent = content })
end

---------------------------------------------------------------------------
local function buildSettings()
	local _, content = C.UI:MakePanel("Settings", "⚙️ SETTINGS", Color3.fromRGB(130, 140, 160), 520, 420)
	UIKit.List(content, 12)

	local function row(order: number, text: string)
		local frame = UIKit.new("Frame", { Size = UDim2.new(1, -20, 0, 52), BackgroundColor3 = Theme.PanelLight, LayoutOrder = order, ZIndex = 7, Parent = content })
		UIKit.Corner(frame, 10)
		UIKit.Label({ Text = text, Size = UDim2.new(0.5, 0, 1, -16), Position = UDim2.fromOffset(14, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = frame })
		return frame
	end

	-- music volume
	local volRow = row(1, "🎵 Music Volume")
	local volLabel = UIKit.Label({ Text = "", Size = UDim2.fromOffset(60, 30), Position = UDim2.new(1, -150, 0, 11), ZIndex = 8, Parent = volRow })
	local function updateVol()
		volLabel.Text = math.floor(C.Music:GetVolume() * 100 + 0.5) .. "%"
	end
	UIKit.Button({ Text = "-", Color = Theme.Red, Size = UDim2.fromOffset(40, 36), Position = UDim2.new(1, -196, 0, 8), ZIndex = 8, Parent = volRow, Callback = function()
		C.Music:SetVolume(C.Music:GetVolume() - 0.1)
		updateVol()
	end })
	UIKit.Button({ Text = "+", Color = Theme.Green, Size = UDim2.fromOffset(40, 36), Position = UDim2.new(1, -84, 0, 8), ZIndex = 8, Parent = volRow, Callback = function()
		C.Music:SetVolume(C.Music:GetVolume() + 0.1)
		updateVol()
	end })
	updateVol()

	local function toggle(order: number, text: string, initial: boolean, onChange: (boolean) -> ())
		local frame = row(order, text)
		local state = initial
		local button
		button = UIKit.Button({
			Text = state and "ON" or "OFF",
			Color = state and Theme.Green or Theme.Red,
			Size = UDim2.fromOffset(90, 36),
			Position = UDim2.new(1, -104, 0, 8),
			ZIndex = 8,
			Parent = frame,
			Callback = function()
				state = not state
				button.Text = state and "ON" or "OFF"
				button.BackgroundColor3 = state and Theme.Green or Theme.Red
				onChange(state)
			end,
		})
		return function(value: boolean)
			state = value
			button.Text = state and "ON" or "OFF"
			button.BackgroundColor3 = state and Theme.Green or Theme.Red
		end
	end

	local setSfx = toggle(2, "🔊 Sound Effects", true, function(on)
		UIKit.SFXEnabled = on
		Remotes.SaveSettings:FireServer({ SFX = on })
	end)
	toggle(3, "🎶 Music Widget", true, function(on)
		C.Music:SetWidgetVisible(on)
	end)
	toggle(4, "🥔 Low Graphics", false, function(on)
		C.Animator:SetLowGraphics(on)
		Remotes.SaveSettings:FireServer({ LowGraphics = on })
	end)

	UIKit.Label({ Text = Config.GameName .. " v" .. Config.Version, Size = UDim2.new(1, 0, 0, 20), Font = Theme.BodyFont, TextColor3 = Theme.SubText, LayoutOrder = 9, ZIndex = 7, Parent = content })

	player:GetAttributeChangedSignal("SFX"):Connect(function()
		local on = player:GetAttribute("SFX") ~= false
		UIKit.SFXEnabled = on
		setSfx(on)
	end)
	C.UI.Panels.Settings.OnOpen = updateVol
end

function Panels:Init(controllers)
	C = controllers
	buildRebirth()
	buildDaily()
	buildCodes()
	buildSettings()
end

function Panels:Start()
	if player:GetAttribute("SFX") == false then
		UIKit.SFXEnabled = false
	end
end

return Panels
