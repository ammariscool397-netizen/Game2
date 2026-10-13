--[[
	LeaderboardService - global "Top Earners" board in the lobby
	(OrderedDataStore, refreshes every 2 minutes).
]]
local Players = game:GetService("Players")

local LeaderboardService = {}
local S

local nameCache: { [number]: string } = {}
local REFRESH = 120

local function nameFor(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = ok and name or ("User " .. userId)
	return nameCache[userId]
end

local function abbreviate(n: number): string
	return require(game:GetService("ReplicatedStorage").Shared.Util).Money(n)
end

function LeaderboardService:Init(services)
	S = services
end

function LeaderboardService:_render(rows)
	local body = S.WorldBuilder.LeaderboardBody
	if not body then
		return
	end
	body:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body
	if #rows == 0 then
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 60)
		label.BackgroundTransparency = 1
		label.Text = "Leaderboard loads in the live game\n(publish + enable API access)"
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(200, 200, 220)
		label.Parent = body
		return
	end
	local medal = { "🥇", "🥈", "🥉" }
	for i, row in rows do
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(1, 0, 0, 40)
		frame.BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(40, 42, 60) or Color3.fromRGB(32, 34, 50)
		frame.LayoutOrder = i
		frame.Parent = body
		local rank = Instance.new("TextLabel")
		rank.Size = UDim2.new(0.15, 0, 1, 0)
		rank.BackgroundTransparency = 1
		rank.Text = medal[i] or ("#" .. i)
		rank.TextScaled = true
		rank.Font = Enum.Font.FredokaOne
		rank.TextColor3 = Color3.new(1, 1, 1)
		rank.Parent = frame
		local name = Instance.new("TextLabel")
		name.Size = UDim2.new(0.5, 0, 1, 0)
		name.Position = UDim2.new(0.15, 0, 0, 0)
		name.BackgroundTransparency = 1
		name.Text = row.Name
		name.TextScaled = true
		name.Font = Enum.Font.GothamBold
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Parent = frame
		local value = Instance.new("TextLabel")
		value.Size = UDim2.new(0.33, 0, 1, 0)
		value.Position = UDim2.new(0.66, 0, 0, 0)
		value.BackgroundTransparency = 1
		value.Text = abbreviate(row.Value)
		value.TextScaled = true
		value.Font = Enum.Font.FredokaOne
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.TextColor3 = Color3.fromRGB(120, 255, 150)
		value.Parent = frame
	end
end

function LeaderboardService:Refresh()
	local store = S.DataService:GetEarnedStore()
	local rows = {}
	if store then
		local ok, pages = pcall(function()
			return store:GetSortedAsync(false, 10)
		end)
		if ok and pages then
			for _, entry in pages:GetCurrentPage() do
				local userId = tonumber(entry.key)
				if userId then
					table.insert(rows, { Name = nameFor(userId), Value = S.DataService.DecodeEarned(entry.value) })
				end
			end
		end
	end
	self:_render(rows)
end

function LeaderboardService:Start()
	task.wait(5)
	while true do
		self:Refresh()
		task.wait(REFRESH)
	end
end

return LeaderboardService
