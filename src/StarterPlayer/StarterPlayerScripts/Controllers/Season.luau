--[[ Season (client) - the season pass panel: a free and a premium reward for every level ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme
local SC = Config.Season

local Season = {}
local C

local titleLabel: TextLabel
local levelLabel: TextLabel
local setXp: (number) -> ()
local passButton: TextButton
local list: ScrollingFrame
local lastState

local function rewardText(reward): string
	if reward.Kind == "Cash" then
		return "💵 " .. string.format("%g", reward.Minutes) .. " min income"
	elseif reward.Kind == "Boost" then
		return "⚡ 2x " .. Util.FormatTime(reward.Seconds)
	elseif reward.Kind == "Pet" then
		local pet = Config.PetById[reward.Id]
		return pet.Icon .. " " .. pet.Name
	elseif reward.Kind == "Cosmetic" then
		local cosmetic = Config.Cosmetics.ById[reward.Id]
		return cosmetic.Icon .. " " .. cosmetic.Name
	end
	return "?"
end

local render

local function claim(track: string, level: number)
	local ok, message = Remotes.SeasonClaim:InvokeServer(track, level)
	C.Notifications:Toast(tostring(message), ok and "success" or "error", 4)
	local state = Remotes.SeasonGet:InvokeServer()
	if state then
		render(state)
	end
end

-- one reward cell
local function cell(row: Frame, track: string, level: number, state, x: number)
	local reward = SC[track][level]
	local holder = UIKit.new("Frame", { Size = UDim2.new(0.38, 0, 1, -8), Position = UDim2.new(x, 0, 0, 4), BackgroundTransparency = 1, ZIndex = 8, Parent = row })
	if not reward then
		UIKit.Label({ Text = "-", Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.25), TextColor3 = Theme.SubText, ZIndex = 8, Parent = holder })
		return
	end
	local claimedSet = track == "Free" and state.Free or state.PremiumClaimed
	local claimed = claimedSet[tostring(level)] == true
	UIKit.Label({ Text = rewardText(reward), Size = UDim2.new(1, -92, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, ZIndex = 8, Parent = holder })
	local text, color, active = "CLAIM", Theme.Green, true
	if claimed then
		text, color, active = "✓", Theme.SubText, false
	elseif state.Level < level then
		text, color, active = "🔒 " .. level, Color3.fromRGB(70, 72, 96), false
	elseif track == "Premium" and not state.Premium then
		text, color, active = "🎫", Color3.fromRGB(150, 90, 30), false
	end
	UIKit.Button({ Text = text, Color = color, Size = UDim2.fromOffset(84, 36), Position = UDim2.new(1, -86, 0.5, -18), ZIndex = 9, Parent = holder, Callback = function()
		if active then
			claim(track, level)
		end
	end })
end

render = function(state)
	lastState = state
	titleLabel.Text = "🎫 " .. state.Name .. "   ⏳ " .. Util.FormatTime(math.max(0, state.EndsAt - Util.ServerNow()))
	if state.Level >= SC.Levels then
		levelLabel.Text = "Level " .. SC.Levels .. " - MAX!"
		setXp(1)
	else
		levelLabel.Text = string.format("Level %d   %d / %d XP", state.Level, state.Into, state.Need)
		setXp(state.Into / state.Need)
	end
	passButton.Visible = not state.Premium
	UIKit.Clear(list)
	for level = 1, SC.Levels do
		local row = UIKit.Row(list, level, 50)
		UIKit.Label({ Text = tostring(level), Size = UDim2.new(0.1, 0, 1, 0), TextColor3 = state.Level >= level and Theme.Accent or Theme.SubText, ZIndex = 8, Parent = row })
		cell(row, "Free", level, state, 0.1)
		cell(row, "Premium", level, state, 0.5)
	end
end

local function refresh()
	local state = Remotes.SeasonGet:InvokeServer()
	if state then
		render(state)
	end
end

function Season:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Season", "🎫 SEASON", Color3.fromRGB(255, 140, 40), 820, 600, refresh)
	titleLabel = UIKit.Label({ Text = "", Size = UDim2.new(0.62, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = content })
	levelLabel = UIKit.Label({ Text = "", Size = UDim2.new(0.62, 0, 0, 20), Position = UDim2.fromOffset(0, 30), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, ZIndex = 7, Parent = content })
	local bar, set = UIKit.Bar(content, UDim2.new(0.62, 0, 0, 14), UDim2.fromOffset(0, 54), Theme.Accent2)
	bar.ZIndex = 7
	setXp = set
	passButton = UIKit.Button({ Text = "🎫 GET SEASON PASS", Color = Color3.fromRGB(255, 140, 40), Size = UDim2.new(0.36, 0, 0, 44), Position = UDim2.new(0.64, 0, 0, 8), ZIndex = 8, Parent = content, Callback = function()
		Remotes.BuyPass:FireServer(SC.PremiumPass)
	end })
	UIKit.Label({ Text = "LEVEL", Size = UDim2.new(0.1, 0, 0, 18), Position = UDim2.fromOffset(0, 74), Font = Theme.BodyFont, TextColor3 = Theme.SubText, ZIndex = 7, Parent = content })
	UIKit.Label({ Text = "FREE", Size = UDim2.new(0.38, 0, 0, 18), Position = UDim2.new(0.1, 0, 0, 74), Font = Theme.BodyFont, TextColor3 = Theme.Green, ZIndex = 7, Parent = content })
	UIKit.Label({ Text = "PREMIUM 🎫", Size = UDim2.new(0.38, 0, 0, 18), Position = UDim2.new(0.5, 0, 0, 74), Font = Theme.BodyFont, TextColor3 = Theme.Accent, ZIndex = 7, Parent = content })
	list = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -98), Position = UDim2.fromOffset(0, 96), Parent = content })
	UIKit.List(list, 5)
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = list })
	for _, attr in { "SeasonLevel", "Pass_" .. SC.PremiumPass } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if C.UI.Current == "Season" then
				task.spawn(refresh)
			end
		end)
	end
end

function Season:Start()
	-- the badge on the menu: rewards waiting
	local function badge()
		if C.HUD and C.HUD.SetBadge then
			local ready = player:GetAttribute("SeasonReady") or 0
			C.HUD:SetBadge("Season", ready > 0, tostring(ready))
		end
	end
	player:GetAttributeChangedSignal("SeasonReady"):Connect(badge)
	badge()
	-- the countdown
	while true do
		task.wait(1)
		if C.UI.Current == "Season" and lastState then
			titleLabel.Text = "🎫 " .. lastState.Name .. "   ⏳ " .. Util.FormatTime(math.max(0, lastState.EndsAt - Util.ServerNow()))
		end
	end
end

return Season
