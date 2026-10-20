--[[
	Tutorial (client) - a short guided start: buy upgrades, spin the wheel, claim
	the daily reward. The banner tells where to click; the server checks the
	steps before it pays the reward (see TutorialService).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme
local TC = Config.Tutorial

local Tutorial = {}
local C

local banner: Frame
local title: TextLabel
local body: TextLabel
local stepDots: TextLabel
local finished = false
local latched: { [number]: boolean } = {} -- steps already done stay done

local function count(map: any): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

local steps = {
	{
		Title = "1/3  Buy upgrades",
		Text = function()
			local bought = math.max(count(C.Build.State.Purchased) - 1, 0)
			return string.format("Walk onto a glowing pad to buy an upgrade! (%d/%d)", math.min(bought, TC.BuyUpgrades), TC.BuyUpgrades)
		end,
		Done = function()
			return count(C.Build.State.Purchased) - 1 >= TC.BuyUpgrades
		end,
	},
	{
		Title = "2/3  Spin the wheel",
		Text = function()
			return "Press ➕ MORE on the left, then 🎰 WHEEL, and spin for a free prize!"
		end,
		Done = function()
			return (player:GetAttribute("WheelReadyAt") or 0) > Util.ServerNow()
		end,
	},
	{
		Title = "3/3  Daily reward",
		Text = function()
			return "Press 🎁 DAILY on the left and claim your daily reward!"
		end,
		Done = function()
			return (player:GetAttribute("LastDaily") or 0) > 0
		end,
	},
}

local function hide()
	banner.Visible = false
end

local function finish()
	if finished then
		return
	end
	finished = true
	title.Text = "🎓 Well done!"
	body.Text = "Tutorial complete - collecting your reward..."
	stepDots.Text = "●●●"
	-- the server checks the steps itself: ask again a few times until it confirms
	task.spawn(function()
		for _ = 1, 4 do
			Remotes.TutorialClaim:FireServer()
			local waited = 0
			while waited < 3 and player:GetAttribute("TutorialDone") ~= true do
				waited += task.wait(0.25)
			end
			if player:GetAttribute("TutorialDone") == true then
				body.Text = "Tutorial complete - your reward has been paid!"
				break
			end
		end
		task.wait(3)
		hide()
	end)
end

function Tutorial:Init(controllers)
	C = controllers
	banner = UIKit.new("Frame", {
		Name = "Tutorial",
		Size = UDim2.new(0.9, 0, 0, 78),
		Position = UDim2.new(0.5, 0, 0, 176),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Panel,
		Visible = false,
		ZIndex = 12,
		Parent = C.UI.Gui,
	})
	UIKit.Corner(banner, 14)
	UIKit.new("UISizeConstraint", { MaxSize = Vector2.new(420, 78), Parent = banner })
	UIKit.Stroke(banner, Theme.Green, 3)
	title = UIKit.Label({ Text = "", Size = UDim2.new(1, -110, 0, 24), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Green, ZIndex = 13, Parent = banner })
	stepDots = UIKit.Label({ Text = "", Size = UDim2.fromOffset(60, 20), Position = UDim2.new(1, -150, 0, 8), TextColor3 = Theme.Accent, ZIndex = 13, Parent = banner })
	body = UIKit.new("TextLabel", { Text = "", Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 32), BackgroundTransparency = 1, TextWrapped = true, TextSize = 15, Font = Theme.BodyFont, TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 13, Parent = banner })
	UIKit.Button({ Text = "SKIP", Color = Color3.fromRGB(90, 92, 120), Size = UDim2.fromOffset(70, 26), Position = UDim2.new(1, -82, 0, 6), ZIndex = 14, Parent = banner, Callback = function()
		finished = true
		hide()
	end })
end

function Tutorial:Start()
	if not TC.Enabled then
		return
	end
	if not player:GetAttribute("DataLoaded") then
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	while not player:GetAttribute("LoadingDone") do
		task.wait(0.5)
	end
	task.wait(2)
	if player:GetAttribute("TutorialDone") == true then
		return
	end
	banner.Visible = true
	while not finished do
		local current
		local doneCount = 0
		for index, step in steps do
			if latched[index] or step.Done() then
				latched[index] = true
				doneCount += 1
			elseif not current then
				current = step
			end
		end
		if not current then
			finish()
			break
		end
		banner.Visible = C.UI.Current == nil -- never cover an open panel
		title.Text = current.Title
		body.Text = current.Text()
		stepDots.Text = string.rep("●", doneCount) .. string.rep("○", #steps - doneCount)
		task.wait(0.4)
	end
end

return Tutorial
