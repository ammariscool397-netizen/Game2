--[[
	AchievementService - achievements (Config.Achievements) and the stats page.
	Stats are read from the saved data; an achievement pays its reward once, the
	moment its stat reaches the target (checked shortly after anything happens,
	and every few seconds).
]]
local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local TycoonItems = require(Shared.TycoonItems)

local AchievementService = {}
local S

local dirty: { [Player]: boolean } = {}

local function count(map: any): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- the value of one stat for a player's data
function AchievementService:GetStat(player: Player, data, stat: string): number
	if stat == "Upgrades" then
		-- bought in total (a rebirth resets what you own), never less than what you own now
		local n = 0
		for id in data.Purchased do
			local item = TycoonItems.ById[id]
			if item and item.Kind ~= "Secret" then
				n += 1
			end
		end
		data.Stats.Upgrades = math.max(data.Stats.Upgrades or 0, n)
		return data.Stats.Upgrades
	elseif stat == "Rebirths" then
		return data.Rebirths
	elseif stat == "Earned" then
		return data.TotalEarned
	elseif stat == "Hatched" then
		return data.Pets.Hatched
	elseif stat == "Quests" then
		return data.Stats.Quests or 0
	elseif stat == "Spins" then
		return data.Wheel.Spins
	elseif stat == "Survived" then
		return data.Stats.Survived or 0
	elseif stat == "MinigameWins" then
		return data.MinigameWins
	elseif stat == "Secrets" then
		return count(data.Secrets)
	elseif stat == "Chests" then
		return data.Stats.Chests or 0
	elseif stat == "Trades" then
		return data.Stats.Trades or 0
	elseif stat == "GiftsSent" then
		return data.Stats.GiftsSent or 0
	elseif stat == "Hours" then
		return data.PlayTime / 3600
	elseif stat == "Floors" then
		local top = 1
		for id in data.Purchased do
			local item = TycoonItems.ById[id]
			if item and item.Kind == "Unlock" and item.Floor > top then
				top = item.Floor
			end
		end
		data.Stats.Floors = math.max(data.Stats.Floors or 1, top)
		return data.Stats.Floors
	elseif stat == "Cosmetics" then
		return count(data.Cosmetics.Owned)
	elseif stat == "SeasonLevel" then
		return S.SeasonService and S.SeasonService:GetLevel(player) or 0
	end
	return 0
end

function AchievementService:Dirty(player: Player)
	dirty[player] = true
end

function AchievementService:_reward(player: Player, data, achievement)
	local reward = achievement.Reward
	local parts = {}
	if reward.Minutes then
		local cash = math.floor(math.max((reward.MinCash or 0) * (1 + data.Rebirths), S.TycoonService:GetIncome(player) * reward.Minutes * 60))
		S.DataService:AddCash(player, cash, false)
		table.insert(parts, "+" .. Util.Money(cash))
	end
	if reward.Boost then
		S.DataService:AddBoost(player, reward.Boost)
		table.insert(parts, "2x for " .. Util.FormatTime(reward.Boost))
	end
	if reward.Cosmetic and S.CosmeticService then
		local cosmetic = Config.Cosmetics.ById[reward.Cosmetic]
		S.CosmeticService:Give(player, reward.Cosmetic, true)
		table.insert(parts, (cosmetic and cosmetic.Icon or "✨") .. " " .. (cosmetic and cosmetic.Name or reward.Cosmetic))
	end
	return table.concat(parts, "  ")
end

-- checks every achievement; rewards the ones that are done now
function AchievementService:Check(player: Player)
	local data = S.DataService:Get(player)
	if not data or not Config.Achievements.Enabled then
		return
	end
	local values = {}
	for _, achievement in Config.Achievements.List do
		if not data.Achievements[achievement.Id] then
			local value = values[achievement.Stat]
			if value == nil then
				value = self:GetStat(player, data, achievement.Stat)
				values[achievement.Stat] = value
			end
			if value >= achievement.Target then
				data.Achievements[achievement.Id] = true
				local text = self:_reward(player, data, achievement)
				Remotes.Notify:FireClient(player, { Text = "🏆 Achievement: " .. achievement.Name .. "  " .. text, Type = "success", Duration = 7 })
				Remotes.VFX:FireClient(player, "Confetti", {})
				local badge = Config.Achievements.Badges[achievement.Id]
				if badge and badge ~= 0 then
					task.spawn(function()
						pcall(BadgeService.AwardBadge, BadgeService, player.UserId, badge)
					end)
				end
				if S.ProgressService then
					S.ProgressService:Record(player, "Achievement")
				end
			end
		end
	end
	player:SetAttribute("Achievements", count(data.Achievements))
end

-- for the Achievements panel: every stat value and which achievements are done
function AchievementService:GetState(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return nil
	end
	local stats = {}
	for _, achievement in Config.Achievements.List do
		if stats[achievement.Stat] == nil then
			stats[achievement.Stat] = self:GetStat(player, data, achievement.Stat)
		end
	end
	local done = {}
	for id in data.Achievements do
		done[id] = true
	end
	return { Stats = stats, Done = done, DoneCount = count(done), Total = #Config.Achievements.List }
end

-- for the Stats page
function AchievementService:GetStatsPage(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return nil
	end
	local function stat(name: string): number
		return self:GetStat(player, data, name)
	end
	local joined = player:GetAttribute("JoinedAt")
	local played = data.PlayTime + (type(joined) == "number" and math.max(0, os.time() - joined) or 0)
	local season = S.SeasonService and S.SeasonService:GetLevel(player) or 0
	return {
		{ Label = "⏱️ Time played", Value = Util.FormatTime(played) },
		{ Label = "💰 Total earned", Value = Util.Money(stat("Earned")) },
		{ Label = "🏗️ Upgrades bought", Value = tostring(stat("Upgrades")) .. " / " .. tostring(TycoonItems.BuyableCount) },
		{ Label = "🏢 Highest floor", Value = tostring(stat("Floors")) },
		{ Label = "🔄 Rebirths", Value = tostring(stat("Rebirths")) },
		{ Label = "🥚 Eggs hatched", Value = tostring(stat("Hatched")) },
		{ Label = "🐾 Pets owned", Value = tostring(#data.Pets.Owned) .. " / " .. tostring(Config.Pets.MaxOwned) },
		{ Label = "📜 Quests claimed", Value = tostring(stat("Quests")) },
		{ Label = "🎰 Wheel spins", Value = tostring(stat("Spins")) },
		{ Label = "🛡️ Disasters survived", Value = tostring(stat("Survived")) },
		{ Label = "🎮 Minigames won", Value = tostring(stat("MinigameWins")) },
		{ Label = "🕵️ Secrets found", Value = tostring(stat("Secrets")) .. " / " .. tostring(#Config.Secrets) },
		{ Label = "🏝️ Chests opened", Value = tostring(stat("Chests")) },
		{ Label = "🤝 Trades", Value = tostring(stat("Trades")) },
		{ Label = "✨ Cosmetics", Value = tostring(stat("Cosmetics")) .. " / " .. tostring(#Config.Cosmetics.List) },
		{ Label = "🎫 Season level", Value = tostring(season) .. " / " .. tostring(Config.Season.Levels) },
		{ Label = "🏆 Achievements", Value = tostring(count(data.Achievements)) .. " / " .. tostring(#Config.Achievements.List) },
	}
end

function AchievementService:Init(services)
	S = services
	Remotes.AchievementsGet.OnServerInvoke = function(player)
		return self:GetState(player)
	end
	Remotes.StatsGet.OnServerInvoke = function(player)
		return self:GetStatsPage(player)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		player:SetAttribute("JoinedAt", os.time())
		dirty[player] = true
	end)
	Players.PlayerRemoving:Connect(function(player)
		dirty[player] = nil
	end)
end

function AchievementService:Start()
	local tick = 0
	while true do
		task.wait(2)
		tick += 1
		for _, player in Players:GetPlayers() do
			-- derived stats (earnings, time played) change without an event: re-check now and then
			if dirty[player] or tick % 10 == 0 then
				dirty[player] = nil
				Util.Try("Achievements", self.Check, self, player)
			end
		end
	end
end

return AchievementService
