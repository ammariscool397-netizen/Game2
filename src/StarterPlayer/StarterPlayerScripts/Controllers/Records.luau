--[[ Records (client) - the Stats page and the global Leaderboards panel ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Records = {}
local C

local statsList: ScrollingFrame
local boardList: ScrollingFrame
local boardTabs: { [string]: TextButton } = {}
local boardData
local currentBoard = "Earned"

local BOARDS = {
	{ Id = "Earned", Name = "💰 RICHEST", Money = true },
	{ Id = "Rebirths", Name = "🔄 REBIRTHS" },
	{ Id = "Hatched", Name = "🥚 EGGS HATCHED" },
}

local function refreshStats()
	local lines = Remotes.StatsGet:InvokeServer()
	UIKit.Clear(statsList)
	for i, line in lines or {} do
		local row = UIKit.Row(statsList, i, 44)
		UIKit.Label({ Text = line.Label, Size = UDim2.new(0.6, -12, 1, -10), Position = UDim2.fromOffset(12, 5), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = row })
		UIKit.Label({ Text = line.Value, Size = UDim2.new(0.4, -12, 1, -10), Position = UDim2.new(0.6, 0, 0, 5), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Accent, ZIndex = 8, Parent = row })
	end
end

local function renderBoard()
	if not boardData then
		return
	end
	for id, button in boardTabs do
		button.BackgroundColor3 = id == currentBoard and Theme.Accent or Theme.PanelLight
	end
	UIKit.Clear(boardList)
	local rows = boardData[currentBoard] or {}
	local money = currentBoard == "Earned"
	local medals = { "🥇", "🥈", "🥉" }
	for i, entry in rows do
		local row = UIKit.Row(boardList, i, 42)
		if entry.UserId == player.UserId then
			UIKit.Stroke(row, Theme.Green, 2)
		end
		UIKit.Label({ Text = medals[i] or ("#" .. i), Size = UDim2.new(0.14, 0, 1, -8), Position = UDim2.fromOffset(4, 4), ZIndex = 8, Parent = row })
		UIKit.Label({ Text = entry.Name, Size = UDim2.new(0.5, 0, 1, -8), Position = UDim2.new(0.14, 0, 0, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = row })
		UIKit.Label({ Text = money and Util.Money(entry.Value) or Util.Abbreviate(entry.Value), Size = UDim2.new(0.34, -8, 1, -8), Position = UDim2.new(0.66, 0, 0, 4), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Theme.Green, ZIndex = 8, Parent = row })
	end
	if #rows == 0 then
		UIKit.Label({ Text = "No scores yet - be the first!", Size = UDim2.new(1, -10, 0, 40), Font = Theme.BodyFont, TextColor3 = Theme.SubText, ZIndex = 8, Parent = boardList })
	end
end

local function refreshBoards()
	boardData = Remotes.BoardsGet:InvokeServer()
	renderBoard()
end

function Records:Init(controllers)
	C = controllers
	local _, stats = C.UI:MakePanel("Stats", "📊 YOUR STATS", Color3.fromRGB(90, 160, 255), 560, 580, refreshStats)
	statsList = UIKit.Scroll({ Size = UDim2.fromScale(1, 1), Parent = stats })
	UIKit.List(statsList, 5)
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = statsList })

	local _, boards = C.UI:MakePanel("Boards", "🏅 LEADERBOARDS", Color3.fromRGB(255, 190, 40), 620, 600, refreshBoards)
	local tabs = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 6, Parent = boards })
	UIKit.List(tabs, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	for i, board in BOARDS do
		boardTabs[board.Id] = UIKit.Button({ Text = board.Name, Color = Theme.PanelLight, Size = UDim2.new(0.32, 0, 0, 40), LayoutOrder = i, ZIndex = 7, Parent = tabs, Callback = function()
			currentBoard = board.Id
			renderBoard()
		end })
	end
	boardList = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 50), Parent = boards })
	UIKit.List(boardList, 5)
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = boardList })
end

return Records
