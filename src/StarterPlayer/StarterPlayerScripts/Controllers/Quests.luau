--[[ Quests (client) - the quest tracker in the bottom-right corner ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Quests = {}
Quests.List = {}
Quests.Claimed = 0
local C

local ICONS = {
	Buy = "🏗️", Earn = "💵", Collect = "🏦", Floor = "🏢", Secret = "🕵️",
	Obby = "🏃", Minigame = "🎮", Survive = "🛡️", Hatch = "🥚",
}
local ROW_HEIGHT = 58

local tracker: Frame
local title: TextLabel
local rowsFrame: Frame
local collapsed = false

local function claim(quest, button: TextButton)
	if button.Text == "..." then
		return -- already claiming
	end
	button.Text = "..."
	-- by type, not slot: slots shift when another quest is claimed first
	local ok, message = Remotes.ClaimQuest:InvokeServer(quest.Type)
	C.Notifications:Toast(tostring(message), ok and "success" or "error")
	if not ok then
		button.Text = "CLAIM"
	end
end

local function render()
	for _, child in rowsFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local ready = 0
	for i, quest in Quests.List do
		if quest.Done then
			ready += 1
		end
		local row = UIKit.new("Frame", {
			Name = "Quest" .. i,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundColor3 = quest.Done and Color3.fromRGB(40, 70, 45) or Theme.Panel,
			BackgroundTransparency = 0.1,
			LayoutOrder = i,
			Parent = rowsFrame,
		})
		UIKit.Corner(row, 10)
		UIKit.Stroke(row, quest.Done and Theme.Green or Color3.new(0, 0, 0), 2, 0.2)
		UIKit.Label({ Text = ICONS[quest.Type] or "📜", Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(6, 6), Parent = row })
		UIKit.new("TextLabel", {
			Text = quest.Text,
			Size = UDim2.new(1, quest.Done and -132 or -48, 0, 22),
			Position = UDim2.fromOffset(40, 5),
			BackgroundTransparency = 1,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.BodyFont,
			TextColor3 = Theme.Text,
			Parent = row,
		})
		local rewardText = "🎁 " .. Util.Money(quest.Reward) .. (quest.Boost and " + 2x" or "")
		if quest.Done then
			UIKit.Button({
				Name = "Claim",
				Text = "CLAIM",
				Color = Theme.Green,
				Size = UDim2.fromOffset(84, 40),
				Position = UDim2.new(1, -90, 0, 9),
				Parent = row,
				Callback = function()
					claim(quest, row:FindFirstChild("Claim") :: TextButton)
				end,
			})
			UIKit.Label({ Text = rewardText, Size = UDim2.new(1, -132, 0, 18), Position = UDim2.fromOffset(40, 32), Font = Theme.BodyFont, TextColor3 = Color3.fromRGB(150, 255, 160), TextXAlignment = Enum.TextXAlignment.Left, Stroke = false, Parent = row })
		else
			local back = UIKit.new("Frame", { Size = UDim2.new(1, -150, 0, 14), Position = UDim2.fromOffset(40, 34), BackgroundColor3 = Theme.Background, Parent = row })
			UIKit.Corner(back, 7)
			local alpha = quest.Target > 0 and math.clamp(quest.Progress / quest.Target, 0, 1) or 0
			local fill = UIKit.new("Frame", { Size = UDim2.fromScale(alpha, 1), BackgroundColor3 = Theme.Accent, Parent = back })
			UIKit.Corner(fill, 7)
			local progressText = quest.Target > 1 and (Util.Abbreviate(quest.Progress) .. "/" .. Util.Abbreviate(quest.Target)) or ""
			UIKit.Label({ Text = progressText, Size = UDim2.new(1, 0, 1, 0), Font = Theme.BodyFont, Stroke = false, Parent = back })
			UIKit.Label({ Text = rewardText, Size = UDim2.fromOffset(104, 18), Position = UDim2.new(1, -108, 0, 32), Font = Theme.BodyFont, TextColor3 = Color3.fromRGB(150, 255, 160), TextXAlignment = Enum.TextXAlignment.Right, Stroke = false, Parent = row })
		end
	end
	title.Text = (collapsed and "▸ " or "▾ ") .. "📜 QUESTS" .. (ready > 0 and ("  (" .. ready .. " ready!)") or "")
	tracker.Visible = #Quests.List > 0 and not player:GetAttribute("InMinigame")
	rowsFrame.Visible = not collapsed
	local height = 30 + (collapsed and 0 or (#Quests.List * (ROW_HEIGHT + 6)))
	TweenService:Create(tracker, TweenInfo.new(0.2), { Size = UDim2.fromOffset(300, height) }):Play()
	if C.HUD and C.HUD.SetBadge then
		C.HUD:SetBadge("Quests", ready > 0, tostring(ready))
	end
end

function Quests:ReadyCount(): number
	local n = 0
	for _, quest in self.List do
		if quest.Done then
			n += 1
		end
	end
	return n
end

function Quests:Init(controllers)
	C = controllers
	local gui = C.UI.Gui
	tracker = UIKit.new("Frame", {
		Name = "QuestTracker",
		Size = UDim2.fromOffset(300, 30),
		Position = UDim2.new(1, -12, 1, -76),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local scale = UIKit.new("UIScale", { Parent = tracker })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(vp.Y / 860, 0.6, 1.1)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	local header = UIKit.new("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Text = "",
		Parent = tracker,
	})
	title = UIKit.Label({ Text = "📜 QUESTS", Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = header })
	header.Activated:Connect(function()
		collapsed = not collapsed
		UIKit.PlaySound("Click", 0.4)
		render()
	end)
	rowsFrame = UIKit.new("Frame", { Name = "Rows", Size = UDim2.new(1, 0, 1, -30), Position = UDim2.fromOffset(0, 30), BackgroundTransparency = 1, Parent = tracker })
	UIKit.List(rowsFrame, 6)

	Remotes.QuestUpdate.OnClientEvent:Connect(function(list, claimed)
		if type(list) == "table" then
			self.List = list
			self.Claimed = tonumber(claimed) or self.Claimed
			render()
		end
	end)
	-- out of the way during minigames
	player:GetAttributeChangedSignal("InMinigame"):Connect(function()
		tracker.Visible = #self.List > 0 and not player:GetAttribute("InMinigame")
	end)
	render()
end

return Quests
