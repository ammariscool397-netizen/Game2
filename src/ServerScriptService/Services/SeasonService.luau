--[[
	SeasonService - the Season (battle pass), see Config.Season. XP comes from
	playing (ProgressService events + a little every minute); levels unlock
	rewards on the free track and the premium track (Season Pass owners).
	A new season starts every Config.Season.Days days and resets everyone's XP.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local SC = Config.Season

local SeasonService = {}
local S

-- the player's season data, started fresh when a new season began
function SeasonService:_season(data)
	local number = Config.CurrentSeason(os.time())
	if data.Season.Id ~= number then
		data.Season = { Id = number, XP = 0, Free = {}, Premium = {} }
	end
	return data.Season
end

-- (level, xp into the level, xp the next level needs)
function SeasonService:LevelOf(xp: number): (number, number, number)
	local level, remaining = 0, xp
	while level < SC.Levels do
		local need = Config.SeasonXpForLevel(level + 1)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return SC.Levels, 0, 0
end

function SeasonService:GetLevel(player: Player): number
	local data = S.DataService:Get(player)
	if not data then
		return 0
	end
	return (self:LevelOf(self:_season(data).XP))
end

function SeasonService:HasPremium(player: Player): boolean
	return S.MonetizationService:HasPass(player, SC.PremiumPass)
end

-- rewards waiting to be claimed
function SeasonService:Sync(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local season = self:_season(data)
	local level = self:LevelOf(season.XP)
	local ready = 0
	for l = 1, level do
		if SC.Free[l] and not season.Free[tostring(l)] then
			ready += 1
		end
		if SC.Premium[l] and not season.Premium[tostring(l)] and self:HasPremium(player) then
			ready += 1
		end
	end
	player:SetAttribute("SeasonLevel", level)
	player:SetAttribute("SeasonReady", ready)
end

function SeasonService:AddXp(player: Player, event: string, amount: number?)
	local perEvent = SC.Xp[event]
	local data = S.DataService:Get(player)
	if not SC.Enabled or not perEvent or not data then
		return
	end
	local season = self:_season(data)
	local before = self:LevelOf(season.XP)
	season.XP += perEvent * (amount or 1)
	local after = self:LevelOf(season.XP)
	if after > before then
		Remotes.Notify:FireClient(player, { Text = "🎫 Season level " .. after .. "! New rewards are waiting.", Type = "success", Duration = 5 })
	end
	self:Sync(player)
end

function SeasonService:GetState(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return nil
	end
	local season = self:_season(data)
	local number, _, ends, name = Config.CurrentSeason(os.time())
	local level, into, need = self:LevelOf(season.XP)
	return {
		Number = number,
		Name = name,
		EndsAt = ends,
		XP = season.XP,
		Level = level,
		Into = into,
		Need = need,
		Premium = self:HasPremium(player),
		Free = season.Free,
		PremiumClaimed = season.Premium,
	}
end

function SeasonService:_give(player: Player, data, reward): string
	if reward.Kind == "Cash" then
		local cash = math.floor(math.max((reward.MinCash or 0) * (1 + data.Rebirths), S.TycoonService:GetIncome(player) * reward.Minutes * 60))
		S.DataService:AddCash(player, cash, false)
		Remotes.VFX:FireClient(player, "CashBurst", { Amount = cash })
		return "+" .. Util.Money(cash)
	elseif reward.Kind == "Boost" then
		S.DataService:AddBoost(player, reward.Seconds)
		return "2x cash for " .. Util.FormatTime(reward.Seconds)
	elseif reward.Kind == "Pet" then
		local pet = Config.PetById[reward.Id]
		if S.PetService:Give(player, reward.Id, 1) > 0 then
			return pet.Icon .. " " .. pet.Name
		end
		-- storage full: pay what the pet is worth instead
		local value = S.PetService:GetSellValue(player, reward.Id)
		S.DataService:AddCash(player, value, false)
		return "(pets full) +" .. Util.Money(value) .. " instead of " .. pet.Name
	elseif reward.Kind == "Cosmetic" then
		local cosmetic = Config.Cosmetics.ById[reward.Id]
		S.CosmeticService:Give(player, reward.Id, true)
		return cosmetic.Icon .. " " .. cosmetic.Name
	end
	return ""
end

function SeasonService:Claim(player: Player, track: any, level: any): (boolean, string)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Data still loading..."
	end
	if (track ~= "Free" and track ~= "Premium") or type(level) ~= "number" or level ~= math.floor(level) then
		return false, "Unknown reward."
	end
	local reward = SC[track][level]
	if not reward then
		return false, "Unknown reward."
	end
	local season = self:_season(data)
	if self:LevelOf(season.XP) < level then
		return false, "Reach season level " .. level .. " first!"
	end
	if track == "Premium" and not self:HasPremium(player) then
		return false, "The premium track needs the Season Pass."
	end
	local claimed = track == "Free" and season.Free or season.Premium
	if claimed[tostring(level)] then
		return false, "Already claimed."
	end
	claimed[tostring(level)] = true
	local text = self:_give(player, data, reward)
	Remotes.VFX:FireClient(player, "Confetti", {})
	self:Sync(player)
	return true, "🎫 Level " .. level .. ": " .. text
end

function SeasonService:Init(services)
	S = services
	Remotes.SeasonGet.OnServerInvoke = function(player)
		return self:GetState(player)
	end
	Remotes.SeasonClaim.OnServerInvoke = function(player, track, level)
		if not SC.Enabled then
			return false, "The season is paused."
		end
		return self:Claim(player, track, level)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		self:Sync(player)
	end)
end

function SeasonService:Start()
	while true do
		task.wait(60)
		for _, player in Players:GetPlayers() do
			Util.Try("Season minute", self.AddXp, self, player, "Minute")
		end
	end
end

return SeasonService
