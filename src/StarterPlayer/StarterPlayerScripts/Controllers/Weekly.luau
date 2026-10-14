--[[
	Weekly (client) - the weekly rewards panel (opened from the Daily panel):
	the days you joined this week and the milestones you can claim.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local Theme = UIKit.Theme
local WC = Config.Weekly
local DAY_NAMES = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

local Weekly = {}
Weekly.State = nil :: any
local C

local summary: TextLabel
local dayLabels: { TextLabel } = {}
local cards: { [number]: { Frame: Frame, Button: TextButton } } = {}
local resetClock = 0

local function render()
	local state = Weekly.State
	if not state then
		return
	end
	summary.Text = "You joined on " .. state.Days .. " day(s) this week  •  resets in " .. Util.FormatTime(math.max(0, state.ResetsIn - (os.clock() - resetClock)))
	for i, label in dayLabels do
		local joined = state.DayFlags[i]
		label.Text = (joined and "✅ " or "▫️ ") .. DAY_NAMES[i]
		label.TextColor3 = joined and Color3.fromRGB(150, 255, 160) or Theme.SubText
	end
	for index, milestone in WC.Milestones do
		local card = cards[index]
		if card then
			local claimed = state.Claimed[index]
			local unlocked = state.Days >= milestone.Days
			card.Button.Text = claimed and "CLAIMED ✔" or (unlocked and "CLAIM" or ("🔒 " .. milestone.Days .. " days"))
			card.Button.BackgroundColor3 = (unlocked and not claimed) and Theme.Green or Color3.fromRGB(90, 90, 110)
			card.Frame.BackgroundColor3 = (unlocked and not claimed) and Color3.fromRGB(40, 70, 45) or Theme.Panel
		end
	end
end

function Weekly:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Weekly", "📅 WEEKLY REWARDS", Theme.Purple, 700, 480)
	UIKit.List(content, 10)
	summary = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 30), Font = Theme.BodyFont, LayoutOrder = 1, ZIndex = 7, Parent = content })
	local week = UIKit.new("Frame", { Name = "Days", Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 2, ZIndex = 7, Parent = content })
	UIKit.List(week, 4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)
	for i = 1, 7 do
		dayLabels[i] = UIKit.Label({ Text = DAY_NAMES[i], Size = UDim2.new(1 / 7, -4, 1, 0), Font = Theme.BodyFont, LayoutOrder = i, ZIndex = 8, Parent = week })
	end
	for index, milestone in WC.Milestones do
		local frame = UIKit.new("Frame", { Name = "Milestone" .. index, Size = UDim2.new(1, -10, 0, 78), BackgroundColor3 = Theme.Panel, LayoutOrder = 2 + index, ZIndex = 7, Parent = content })
		UIKit.Corner(frame, 10)
		UIKit.Label({ Text = "Join " .. milestone.Days .. " days", Size = UDim2.new(1, -180, 0, 28), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = frame })
		UIKit.new("TextLabel", {
			Text = milestone.Text,
			Size = UDim2.new(1, -180, 0, 36),
			Position = UDim2.fromOffset(12, 36),
			BackgroundTransparency = 1,
			TextWrapped = true,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = Theme.BodyFont,
			TextColor3 = Theme.SubText,
			ZIndex = 8,
			Parent = frame,
		})
		local button = UIKit.Button({
			Name = "ClaimWeekly" .. index,
			Text = "CLAIM",
			Color = Theme.Green,
			Size = UDim2.fromOffset(150, 48),
			Position = UDim2.new(1, -162, 0, 15),
			ZIndex = 8,
			Parent = frame,
			Callback = function()
				local ok, message = Remotes.ClaimWeekly:InvokeServer(index)
				C.Notifications:Toast(tostring(message), ok and "success" or "error")
			end,
		})
		cards[index] = { Frame = frame, Button = button }
	end
	Remotes.WeeklyUpdate.OnClientEvent:Connect(function(state)
		if type(state) == "table" then
			Weekly.State = state
			resetClock = os.clock()
			render()
		end
	end)
end

function Weekly:Start()
	while true do
		task.wait(1)
		Util.Try("Weekly", render)
	end
end

return Weekly
