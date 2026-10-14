--[[
	WeeklyService - weekly rewards (see Config.Weekly). Every day you join
	counts toward the week (Monday to Sunday, UTC); at 3, 5 and 7 days you can
	claim a bigger reward, once per week. Everything is saved with the player.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local WC = Config.Weekly

local WeeklyService = {}
local S

local function today(): number
	return os.time() // 86400
end

-- weeks run Monday to Sunday (day 0 of the epoch was a Thursday)
local function weekOf(day: number): number
	return (day + 3) // 7
end

local function weekStart(week: number): number
	return week * 7 - 3
end

local function count(map): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- the saved week: starts over in a new week, and today counts as a day joined
function WeeklyService:Refresh(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local weekly = data.Weekly
	local day = today()
	if weekly.Week ~= weekOf(day) then
		weekly.Week, weekly.Days, weekly.Claimed = weekOf(day), {}, {}
	end
	weekly.Days[tostring(day)] = true
	self:_send(player)
end

function WeeklyService:GetState(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return nil
	end
	local weekly = data.Weekly
	local flags, claimed = {}, {}
	for i = 0, 6 do
		table.insert(flags, weekly.Days[tostring(weekStart(weekly.Week) + i)] == true)
	end
	local days = count(weekly.Days)
	local ready = 0
	for index, milestone in WC.Milestones do
		claimed[index] = weekly.Claimed[tostring(index)] == true
		if not claimed[index] and days >= milestone.Days then
			ready += 1
		end
	end
	return { Days = days, DayFlags = flags, Claimed = claimed, Ready = ready, ResetsIn = math.max(0, weekStart(weekly.Week + 1) * 86400 - os.time()) }
end

function WeeklyService:_send(player: Player)
	local state = self:GetState(player)
	if state and player.Parent then
		player:SetAttribute("WeeklyReady", state.Ready)
		Remotes.WeeklyUpdate:FireClient(player, state)
	end
end

function WeeklyService:Claim(player: Player, index: any): (boolean, string)
	local data = S.DataService:Get(player)
	local milestone = type(index) == "number" and WC.Milestones[index]
	if not data or not milestone then
		return false, "That reward doesn't exist."
	end
	self:Refresh(player)
	local state = self:GetState(player)
	if state.Claimed[index] then
		return false, "You already claimed that this week."
	end
	if state.Days < milestone.Days then
		return false, "Join on " .. (milestone.Days - state.Days) .. " more day(s) this week to unlock it."
	end
	data.Weekly.Claimed[tostring(index)] = true
	local wallet = S.DataService:GetWallet(player)
	local rebirths = wallet and wallet.Rebirths or 0
	local cash = math.floor(math.max(milestone.MinCash * (1 + rebirths), S.TycoonService:GetIncome(player) * milestone.IncomeMinutes * 60))
	S.DataService:AddCash(player, cash, false)
	local text = "📅 Weekly reward: +" .. Util.Money(cash)
	if milestone.BoostSeconds then
		S.DataService:AddBoost(player, milestone.BoostSeconds)
		text ..= " & 2x Boost for " .. Util.FormatTime(milestone.BoostSeconds)
	end
	if milestone.Egg and S.PetService then
		for _, egg in Config.Pets.Eggs do
			if egg.Id == milestone.Egg then
				local pet = S.PetService:_roll(egg)
				S.PetService:Give(player, pet.Id, 1)
				text ..= " & a " .. pet.Rarity .. " " .. pet.Name .. " " .. pet.Icon
			end
		end
	end
	Remotes.VFX:FireClient(player, "CashBurst", { Amount = cash })
	Remotes.VFX:FireClient(player, "Confetti", {})
	self:_send(player)
	return true, text .. "!"
end

function WeeklyService:Init(services)
	S = services
	Remotes.ClaimWeekly.OnServerInvoke = function(player, index)
		if not WC.Enabled then
			return false, "Weekly rewards are turned off."
		end
		return self:Claim(player, index)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		if WC.Enabled then
			self:Refresh(player)
		end
	end)
end

-- a new day or week while you're playing
function WeeklyService:Start()
	if not WC.Enabled then
		return
	end
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			Util.Try("Weekly", self.Refresh, self, player)
		end
	end
end

return WeeklyService
