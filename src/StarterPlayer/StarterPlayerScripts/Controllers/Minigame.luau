--[[ Minigame (client) - join popup, countdown, in-game HUD and results ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Minigame = {}
local C

local timerPill: TextLabel
local joinCard: Frame
local joinTitle: TextLabel
local joinDesc: TextLabel
local joinTimer: TextLabel
local joinButton: TextButton
local playBar: Frame
local playText: TextLabel
local countdownLabel: TextLabel
local resultsFrame: Frame
local resultsList: Frame
local lastPhase = nil

local function buildUI()
	local gui = C.UI.Gui

	timerPill = UIKit.Label({
		Text = "",
		Size = UDim2.fromOffset(260, 26),
		Position = UDim2.new(1, -12, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.BodyFont,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = gui,
	})

	-- join card (bottom centre)
	joinCard = UIKit.new("Frame", {
		Size = UDim2.fromOffset(420, 150),
		Position = UDim2.new(0.5, 0, 1, 200),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Theme.Panel,
		Parent = gui,
	})
	UIKit.Corner(joinCard, 16)
	UIKit.Stroke(joinCard, Theme.Purple, 3)
	UIKit.Gradient(joinCard, Theme.PanelLight, Theme.Panel, 90)
	joinTitle = UIKit.Label({ Text = "", Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(10, 8), TextColor3 = Color3.fromRGB(210, 160, 255), Parent = joinCard })
	joinDesc = UIKit.new("TextLabel", {
		Text = "",
		Size = UDim2.new(1, -20, 0, 36),
		Position = UDim2.fromOffset(10, 46),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 15,
		Font = Theme.BodyFont,
		TextColor3 = Theme.SubText,
		Parent = joinCard,
	})
	joinTimer = UIKit.Label({ Text = "", Size = UDim2.fromOffset(120, 40), Position = UDim2.new(0, 14, 1, -52), TextXAlignment = Enum.TextXAlignment.Left, Parent = joinCard })
	joinButton = UIKit.Button({
		Text = "JOIN! 🎮",
		Color = Theme.Green,
		Size = UDim2.fromOffset(200, 48),
		Position = UDim2.new(1, -214, 1, -58),
		Parent = joinCard,
		Callback = function()
			if not player:GetAttribute("MinigameJoined") then
				Remotes.MinigameJoin:FireServer()
			end
		end,
	})
	player:GetAttributeChangedSignal("MinigameJoined"):Connect(function()
		if player:GetAttribute("MinigameJoined") then
			joinButton.Text = "JOINED ✓"
			joinButton.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
		else
			joinButton.Text = "JOIN! 🎮"
			joinButton.BackgroundColor3 = Theme.Green
		end
	end)

	-- in-game bar (top)
	playBar = UIKit.new("Frame", {
		Size = UDim2.fromOffset(420, 40),
		Position = UDim2.new(0.5, 0, 0, 166),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = gui,
	})
	UIKit.Corner(playBar, 12)
	UIKit.Stroke(playBar, Theme.Purple, 2)
	playText = UIKit.Label({ Text = "", Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), Parent = playBar })

	countdownLabel = UIKit.Label({
		Text = "",
		Size = UDim2.fromOffset(400, 180),
		Position = UDim2.fromScale(0.5, 0.4),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = Theme.Accent,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	UIKit.new("UIScale", { Parent = countdownLabel })

	-- results
	resultsFrame = UIKit.new("Frame", {
		Size = UDim2.fromOffset(460, 340),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Panel,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	UIKit.Corner(resultsFrame, 18)
	UIKit.Stroke(resultsFrame, Theme.Purple, 4)
	UIKit.Gradient(resultsFrame, Theme.PanelLight, Theme.Panel, 90)
	UIKit.new("UIScale", { Name = "PopScale", Parent = resultsFrame })
	UIKit.Label({ Name = "Title", Text = "RESULTS", Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 10), TextColor3 = Color3.fromRGB(210, 160, 255), ZIndex = 11, Parent = resultsFrame })
	resultsList = UIKit.new("Frame", { Size = UDim2.new(1, -30, 1, -70), Position = UDim2.fromOffset(15, 60), BackgroundTransparency = 1, ZIndex = 11, Parent = resultsFrame })
	UIKit.List(resultsList, 6)
end

local function showJoin(visible: boolean)
	TweenService:Create(joinCard, TweenInfo.new(0.4, Enum.EasingStyle.Back, visible and Enum.EasingDirection.Out or Enum.EasingDirection.In), {
		Position = visible and UDim2.new(0.5, 0, 1, -20) or UDim2.new(0.5, 0, 1, 200),
	}):Play()
end

local function showResults(state)
	for _, child in resultsList:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	(resultsFrame:FindFirstChild("Title") :: TextLabel).Text = "🏆 " .. state.Name .. " RESULTS"
	local mine = false
	for i, r in state.Results do
		if i > 6 then
			break
		end
		local row = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = r.Winner and Color3.fromRGB(80, 70, 30) or Theme.PanelLight, LayoutOrder = i, ZIndex = 11, Parent = resultsList })
		UIKit.Corner(row, 8)
		UIKit.Label({ Text = (r.Winner and "👑 " or "") .. r.Name, Size = UDim2.new(0.45, 0, 1, -8), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = row })
		UIKit.Label({ Text = tostring(r.Score), Size = UDim2.new(0.2, 0, 1, -8), Position = UDim2.new(0.47, 0, 0, 4), Font = Theme.BodyFont, ZIndex = 12, Parent = row })
		UIKit.Label({ Text = "+" .. Util.Money(r.Reward), Size = UDim2.new(0.3, -10, 1, -8), Position = UDim2.new(0.7, 0, 0, 4), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Green, ZIndex = 12, Parent = row })
		if r.Name == player.DisplayName then
			mine = true
		end
	end
	if not mine then
		return -- don't pop the results for people who didn't play
	end
	UIKit.Open(resultsFrame)
	task.delay(6, function()
		UIKit.Close(resultsFrame)
	end)
end

function Minigame:Init(controllers)
	C = controllers
	buildUI()

	Remotes.MinigameState.OnClientEvent:Connect(function(state)
		local phase = state.Phase
		if phase == "Intermission" then
			timerPill.Text = "🎮 Next minigame: " .. Util.Clock(state.TimeLeft)
			playBar.Visible = false
			if lastPhase == "Join" then
				showJoin(false)
			end
		elseif phase == "Join" then
			timerPill.Text = "🎮 " .. state.Name .. " starting!"
			joinTitle.Text = "🎮 " .. state.Name:upper()
			joinDesc.Text = state.Description
			joinTimer.Text = "⏱ " .. state.TimeLeft .. "s"
			if lastPhase ~= "Join" then
				showJoin(true)
				UIKit.PlaySound("Notify", 0.6, 1.2)
			end
		elseif phase == "Cancelled" then
			showJoin(false)
			C.Notifications:Toast(state.Name .. " cancelled: " .. (state.Text or ""), "info")
		elseif phase == "Countdown" then
			showJoin(false)
			if player:GetAttribute("InMinigame") then
				countdownLabel.Visible = true
				countdownLabel.Text = state.Count > 0 and tostring(state.Count) or "GO!"
				countdownLabel.TextColor3 = state.Count > 0 and Theme.Accent or Theme.Green
				local scale = countdownLabel:FindFirstChildOfClass("UIScale") :: UIScale
				scale.Scale = 2
				TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				UIKit.PlaySound("Countdown", 0.6, state.Count > 0 and 1 or 1.5)
				if state.Count == 0 then
					task.delay(0.8, function()
						countdownLabel.Visible = false
					end)
				end
			end
			timerPill.Text = "🎮 " .. state.Name .. " in progress"
		elseif phase == "Playing" then
			timerPill.Text = "🎮 " .. state.Name .. " in progress"
			if player:GetAttribute("InMinigame") then
				playBar.Visible = true
				local score = player:GetAttribute("MinigameScore")
				local scoreText = (score and score > 0) and ("  •  🪙 " .. score) or ""
				playText.Text = string.format("%s  •  ⏱ %s  •  👥 %d alive%s", state.Name, Util.Clock(state.TimeLeft), state.Alive or 0, scoreText)
			else
				playBar.Visible = false
			end
		elseif phase == "Results" then
			playBar.Visible = false
			showResults(state)
		end
		lastPhase = phase
	end)
end

return Minigame
