--[[
	ProgressService - one place to say "the player just did X".
	Services call ProgressService:Record(player, event). It counts the few things
	that aren't saved anywhere else (Stats), gives Season XP, and asks the
	achievements to re-check.

	Events: Upgrade Quest Hatch Survive Minigame Rebirth Chest Daily Spin Trade Gift Achievement
]]
local ProgressService = {}
local S

-- event -> the counter in data.Stats it increases
local COUNTERS = {
	Upgrade = "Upgrades",
	Survive = "Survived",
	Chest = "Chests",
	Quest = "Quests",
	Trade = "Trades",
	Gift = "GiftsSent",
}

function ProgressService:Record(player: Player, event: string, amount: number?)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local counter = COUNTERS[event]
	if counter then
		data.Stats[counter] = (data.Stats[counter] or 0) + (amount or 1)
	end
	if S.SeasonService then
		S.SeasonService:AddXp(player, event, amount)
	end
	if S.AchievementService then
		S.AchievementService:Dirty(player)
	end
end

function ProgressService:Init(services)
	S = services
end

return ProgressService
