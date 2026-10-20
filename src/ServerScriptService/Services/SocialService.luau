--[[
	SocialService - the free reward for joining the game's Roblox group
	(Config.Social.GroupId) and the private-server info. The group check runs on
	the server, and the reward can only be claimed once per account.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local SC = Config.Social

local SocialService = {}
local S

local function inGroup(player: Player): boolean
	if SC.GroupId == 0 then
		return false
	end
	local ok, result = pcall(player.IsInGroup, player, SC.GroupId)
	return ok and result == true
end

function SocialService:GetState(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return nil
	end
	return {
		GroupId = SC.GroupId,
		GroupLink = SC.GroupLink,
		InGroup = inGroup(player),
		Claimed = data.Social.Group,
		Reward = SC.GroupReward,
		Private = game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0,
		PrivateBonus = SC.PrivateServerBonus,
	}
end

function SocialService:ClaimGroup(player: Player): (boolean, string)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Data still loading..."
	end
	if SC.GroupId == 0 then
		return false, "There's no group reward set up."
	end
	if data.Social.Group then
		return false, "You already claimed the group reward."
	end
	if not inGroup(player) then
		return false, "Join the group first, then press Claim again!"
	end
	data.Social.Group = true
	local reward = SC.GroupReward
	local cash = math.floor(math.max(reward.MinCash * (1 + data.Rebirths), S.TycoonService:GetIncome(player) * reward.Minutes * 60))
	S.DataService:AddCash(player, cash, false)
	if reward.BoostSeconds then
		S.DataService:AddBoost(player, reward.BoostSeconds)
	end
	Remotes.VFX:FireClient(player, "Confetti", {})
	Remotes.VFX:FireClient(player, "CashBurst", { Amount = cash })
	return true, "Thanks for joining! +" .. Util.Money(cash) .. (reward.BoostSeconds and (" & 2x for " .. Util.FormatTime(reward.BoostSeconds)) or "")
end

function SocialService:Init(services)
	S = services
	Remotes.SocialGet.OnServerInvoke = function(player)
		return self:GetState(player)
	end
	Remotes.SocialAction.OnServerInvoke = function(player, action)
		if action == "ClaimGroup" then
			return self:ClaimGroup(player)
		end
		return false, "Unknown action."
	end
end

return SocialService
