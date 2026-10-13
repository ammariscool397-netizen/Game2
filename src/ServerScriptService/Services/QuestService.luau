--[[
	QuestService - every player has 3 quests (see Config.Quests). Other
	services report what players do (QuestService:Progress / :Reach); when a
	quest is complete the player claims it from the quest tracker and a new
	one takes its place. Quests are saved with the player's data.

	Rewards are paid when claimed, so they scale with the income you have
	then: the bigger of RewardSeconds of income or MinCash x (1 + rebirths).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local TycoonItems = require(Shared.TycoonItems)

local QC = Config.Quests

local QuestService = {}
local S

local dirty: { [Player]: boolean } = {}

local function count(map): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- lowest floor (2..roof) the tower hasn't unlocked yet
local function nextFloor(towerData): number?
	for floor = 2, Config.Tycoon.Floors do
		if not towerData.Purchased[TycoonItems.FloorUnlockId(floor)] then
			return floor
		end
	end
	if not towerData.Purchased.Roof_1 then
		return Config.Tycoon.Floors + 1
	end
	return nil
end

local function highestFloor(towerData): number
	local highest = 1
	for floor = 2, Config.Tycoon.Floors do
		if towerData.Purchased[TycoonItems.FloorUnlockId(floor)] then
			highest = floor
		end
	end
	if towerData.Purchased.Roof_1 then
		highest = Config.Tycoon.Floors + 1
	end
	return highest
end

local function floorName(floor: number): string
	return floor > Config.Tycoon.Floors and "the roof" or ("floor " .. floor)
end

function QuestService:_towerData(player: Player)
	return S.DataService:GetWallet(player) or S.DataService:Get(player)
end

-- can this kind of quest be done right now?
function QuestService:_available(kind: string, player: Player, data): boolean
	local tower = self:_towerData(player)
	if kind == "Floor" then
		return tower ~= nil and nextFloor(tower) ~= nil
	elseif kind == "Secret" then
		return count(data.Secrets) < #Config.Secrets
	elseif kind == "Minigame" then
		return Config.Minigames.Enabled
	elseif kind == "Survive" then
		return Config.Disasters.Enabled
	elseif kind == "Buy" then
		return tower ~= nil and count(tower.Purchased) < TycoonItems.BuyableCount
	elseif kind == "Earn" then
		return S.TycoonService:GetIncome(player) > 0
	end
	return QC.Types[kind] ~= nil
end

function QuestService:_new(player: Player, data, taken: { [string]: boolean })
	local kinds = {}
	for kind in QC.Types do
		if not taken[kind] and self:_available(kind, player, data) then
			table.insert(kinds, kind)
		end
	end
	if #kinds == 0 then
		return nil
	end
	table.sort(kinds) -- stable order, then a random pick
	local kind = kinds[math.random(1, #kinds)]
	local def = QC.Types[kind]
	local quest = { Type = kind, Progress = 0, Target = 1 }
	if def.Targets then
		quest.Target = def.Targets[math.random(1, #def.Targets)]
	elseif kind == "Earn" then
		local seconds = def.IncomeSeconds[math.random(1, #def.IncomeSeconds)]
		quest.Target = math.max(def.MinTarget, Util.Number(math.floor(S.TycoonService:GetIncome(player) * seconds)) or 0)
	elseif kind == "Floor" then
		local tower = self:_towerData(player)
		quest.Target = nextFloor(tower) or Config.Tycoon.Floors + 1
		quest.Progress = highestFloor(tower)
	end
	return quest
end

-- top up to QC.Active quests (and drop ones that can't be done any more)
function QuestService:_fill(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local list = data.Quests.List
	local tower = self:_towerData(player)
	for i = #list, 1, -1 do
		local quest = list[i]
		local def = QC.Types[quest.Type]
		local done = def and quest.Progress >= quest.Target
		local stale = quest.Type == "Floor" and tower and nextFloor(tower) ~= quest.Target -- e.g. after a rebirth
		if not def or (not done and (stale or not self:_available(quest.Type, player, data))) then
			table.remove(list, i)
		end
	end
	local taken = {}
	for _, quest in list do
		taken[quest.Type] = true
	end
	while #list < QC.Active do
		local quest = self:_new(player, data, taken)
		if not quest then
			break
		end
		taken[quest.Type] = true
		table.insert(list, quest)
	end
	dirty[player] = true
end

function QuestService:_reward(player: Player, quest)
	local def = QC.Types[quest.Type]
	local wallet = self:_towerData(player)
	local rebirths = wallet and wallet.Rebirths or 0
	local cash = math.max(def.MinCash * (1 + rebirths), S.TycoonService:GetIncome(player) * def.RewardSeconds)
	return math.floor(cash), def.BoostSeconds
end

function QuestService:_text(quest): string
	local def = QC.Types[quest.Type]
	if quest.Type == "Earn" then
		return string.format(def.Text, Util.Money(quest.Target))
	elseif quest.Type == "Floor" then
		return string.format(def.Text, floorName(quest.Target))
	end
	return (string.format(def.Text, quest.Target))
end

-- what the client shows
function QuestService:GetQuests(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return {}
	end
	local out = {}
	for i, quest in data.Quests.List do
		local cash, boost = self:_reward(player, quest)
		local progress, target = quest.Progress, quest.Target
		if quest.Type == "Floor" then
			-- show "floor 3 of 4" style progress as done / not done
			progress, target = (quest.Progress >= quest.Target) and 1 or 0, 1
		end
		out[i] = {
			Slot = i,
			Type = quest.Type,
			Text = self:_text(quest),
			Progress = math.min(progress, target),
			Target = target,
			Done = quest.Progress >= quest.Target,
			Reward = cash,
			Boost = boost,
		}
	end
	return out
end

function QuestService:_send(player: Player)
	dirty[player] = nil
	if player.Parent then
		Remotes.QuestUpdate:FireClient(player, self:GetQuests(player), (S.DataService:Get(player) or { Quests = { Claimed = 0 } }).Quests.Claimed)
	end
end

-- something happened: add `amount` to every active quest of that kind
function QuestService:Progress(player: Player, kind: string, amount: number?)
	local data = S.DataService:Get(player)
	if not data or not QC.Enabled then
		return
	end
	amount = Util.Number(amount) or 1
	for _, quest in data.Quests.List do
		if quest.Type == kind and quest.Progress < quest.Target then
			quest.Progress = math.min(quest.Target, quest.Progress + amount)
			dirty[player] = true
			if quest.Progress >= quest.Target then
				Remotes.Notify:FireClient(player, { Text = "📜 Quest complete: " .. self:_text(quest) .. "! Claim your reward.", Type = "success" })
				Remotes.VFX:FireClient(player, "PurchaseSound", {})
			end
		end
	end
end

-- progress that's a level, not a count (highest floor reached)
function QuestService:Reach(player: Player, kind: string, value: number)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	for _, quest in data.Quests.List do
		if quest.Type == kind and value > quest.Progress then
			self:Progress(player, kind, math.min(value, quest.Target) - quest.Progress)
		end
	end
end

-- a floor was unlocked in `plot`: counts for everyone building it
function QuestService:FloorUnlocked(plot)
	local tower = plot.Owner and S.DataService:Get(plot.Owner)
	if not tower then
		return
	end
	local highest = highestFloor(tower)
	for _, member in { plot.Owner, plot.Partner } do
		if member then
			self:Reach(member, "Floor", highest)
		end
	end
end

-- re-check the quests (after a rebirth, a duo change...)
function QuestService:Refresh(player: Player)
	self:_fill(player)
	self:_send(player)
end

function QuestService:Claim(player: Player, slot: any): (boolean, string)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Data still loading..."
	end
	slot = Util.Number(slot)
	local quest = slot and data.Quests.List[slot]
	if not quest then
		return false, "That quest doesn't exist."
	end
	if quest.Progress < quest.Target then
		return false, "Finish the quest first!"
	end
	local cash, boost = self:_reward(player, quest)
	table.remove(data.Quests.List, slot)
	data.Quests.Claimed += 1
	S.DataService:AddCash(player, cash, false)
	local text = "+" .. Util.Money(cash)
	if boost then
		S.DataService:AddBoost(player, boost)
		text ..= " & 2x Boost for " .. Util.FormatTime(boost)
	end
	Remotes.VFX:FireClient(player, "CashBurst", { Amount = cash })
	Remotes.VFX:FireClient(player, "Confetti", {})
	self:_fill(player)
	self:_send(player)
	return true, "Quest reward: " .. text .. "!"
end

function QuestService:Init(services)
	S = services
	Remotes.ClaimQuest.OnServerInvoke = function(player, slot)
		return self:Claim(player, slot)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		task.defer(function()
			-- (the tower is assigned on load too; quests depend on it)
			self:_fill(player)
			self:_send(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

function QuestService:Start()
	-- batch updates (income progress changes every second)
	while true do
		task.wait(1)
		for player in dirty do
			Util.Try("Quests", self._send, self, player)
		end
	end
end

return QuestService
