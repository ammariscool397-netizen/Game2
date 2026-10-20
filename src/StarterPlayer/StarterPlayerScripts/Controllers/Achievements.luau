--[[ Achievements (client) - the achievements panel: one row per group with the next goal ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Achievements = {}
local C

local summary: TextLabel
local setOverall: (number) -> ()
local list: ScrollingFrame

local function amount(stat: string, value: number): string
	if stat == "Earned" then
		return Util.Money(value)
	elseif stat == "Hours" then
		return string.format("%.1f", value)
	end
	return Util.Abbreviate(math.floor(value))
end

local function rewardText(reward): string
	local parts = {}
	if reward.Minutes then
		table.insert(parts, "💵 " .. reward.Minutes .. " min of income")
	end
	if reward.Boost then
		table.insert(parts, "⚡ 2x " .. Util.FormatTime(reward.Boost))
	end
	if reward.Cosmetic then
		local cosmetic = Config.Cosmetics.ById[reward.Cosmetic]
		table.insert(parts, (cosmetic and cosmetic.Icon or "✨") .. " " .. (cosmetic and cosmetic.Name or reward.Cosmetic))
	end
	return table.concat(parts, "  ")
end

local function render(state)
	UIKit.Clear(list)
	summary.Text = string.format("🏆 %d / %d unlocked", state.DoneCount, state.Total)
	setOverall(state.DoneCount / math.max(state.Total, 1))
	local groups, order = {}, {}
	for _, achievement in Config.Achievements.List do
		if not groups[achievement.Group] then
			groups[achievement.Group] = {}
			table.insert(order, achievement.Group)
		end
		table.insert(groups[achievement.Group], achievement)
	end
	for index, group in order do
		local tiers = groups[group]
		local current, doneCount = nil, 0
		for _, achievement in tiers do
			if state.Done[achievement.Id] then
				doneCount += 1
			elseif not current then
				current = achievement
			end
		end
		local row = UIKit.Row(list, index, 74)
		local shown = current or tiers[#tiers]
		UIKit.Label({ Text = shown.Icon, Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(8, 12), ZIndex = 8, Parent = row })
		UIKit.Label({ Text = shown.Name .. (current == nil and "  ✓" or ""), Size = UDim2.new(0.45, -60, 0, 24), Position = UDim2.fromOffset(64, 6), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = current and Theme.Text or Theme.Green, ZIndex = 8, Parent = row })
		UIKit.Label({ Text = shown.Text:format(amount(shown.Stat, shown.Target)), Size = UDim2.new(0.45, -60, 0, 18), Position = UDim2.fromOffset(64, 30), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, TextColor3 = Theme.SubText, Stroke = false, ZIndex = 8, Parent = row })
		local dots = {}
		for _, achievement in tiers do
			table.insert(dots, state.Done[achievement.Id] and "●" or "○")
		end
		UIKit.Label({ Text = table.concat(dots, " "), Size = UDim2.new(0.45, -60, 0, 16), Position = UDim2.fromOffset(64, 50), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, TextColor3 = Theme.Accent, Stroke = false, ZIndex = 8, Parent = row })
		if current then
			local value = state.Stats[current.Stat] or 0
			local _, set = UIKit.Bar(row, UDim2.new(0.4, 0, 0, 18), UDim2.new(0.55, 0, 0, 14), Theme.Green)
			set(value / current.Target)
			UIKit.Label({ Text = amount(current.Stat, value) .. " / " .. amount(current.Stat, current.Target), Size = UDim2.new(0.4, 0, 0, 16), Position = UDim2.new(0.55, 0, 0, 14), Font = Theme.BodyFont, ZIndex = 10, Parent = row })
			UIKit.Label({ Text = rewardText(current.Reward), Size = UDim2.new(0.4, 0, 0, 18), Position = UDim2.new(0.55, 0, 0, 40), Font = Theme.BodyFont, TextColor3 = Theme.Accent, Stroke = false, ZIndex = 8, Parent = row })
		else
			UIKit.Label({ Text = "COMPLETE", Size = UDim2.new(0.35, 0, 0, 30), Position = UDim2.new(0.6, 0, 0.5, -15), TextColor3 = Theme.Green, ZIndex = 8, Parent = row })
		end
	end
end

local function refresh()
	local state = Remotes.AchievementsGet:InvokeServer()
	if state then
		render(state)
	end
end

function Achievements:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Achievements", "🏆 ACHIEVEMENTS", Theme.Accent, 760, 580, refresh)
	summary = UIKit.Label({ Text = "", Size = UDim2.new(0.5, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = content })
	local bar, set = UIKit.Bar(content, UDim2.new(0.5, -10, 0, 18), UDim2.new(0.5, 10, 0, 4), Theme.Accent)
	bar.ZIndex = 7
	setOverall = set
	list = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 36), Parent = content })
	UIKit.List(list, 6)
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = list })
	player:GetAttributeChangedSignal("Achievements"):Connect(function()
		if C.UI.Current == "Achievements" then
			task.spawn(refresh)
		end
	end)
end

return Achievements
