--[[
	RewardService - daily rewards (with streaks), codes and settings saving.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local RewardService = {}
local S

local codeCooldown: { [Player]: number } = {}

function RewardService:Init(services)
	S = services

	Remotes.ClaimDaily.OnServerInvoke = function(player)
		return self:ClaimDaily(player)
	end
	Remotes.RedeemCode.OnServerInvoke = function(player, code)
		return self:Redeem(player, code)
	end
	Remotes.SaveSettings.OnServerEvent:Connect(function(player, settings)
		local data = S.DataService:Get(player)
		if not data or type(settings) ~= "table" then
			return
		end
		if Util.IsFinite(settings.MusicVolume) then
			data.Settings.MusicVolume = math.clamp(settings.MusicVolume, 0, 1)
		end
		if type(settings.SFX) == "boolean" then
			data.Settings.SFX = settings.SFX
		end
		if type(settings.LowGraphics) == "boolean" then
			data.Settings.LowGraphics = settings.LowGraphics
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		codeCooldown[player] = nil
	end)
end

local function incomeCash(player: Player, minutes: number, minimum: number): number
	return math.max(minimum * (1 + (player:GetAttribute("Rebirths") or 0)), S.TycoonService:GetIncome(player) * minutes * 60)
end

function RewardService:GetDailyReward(player: Player, streak: number): number
	local rewards = Config.Daily.Rewards
	local index = ((streak - 1) % #rewards) + 1
	local amount = incomeCash(player, Config.Daily.IncomeMinutes[index] or 1, rewards[index])
	if S.MonetizationService:HasPass(player, "VIP") then
		amount *= 2
	end
	return amount
end

function RewardService:ClaimDaily(player: Player): (boolean, string)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Data still loading..."
	end
	local now = os.time()
	local since = now - data.LastDaily
	if since < Config.Daily.Cooldown then
		return false, "Come back in " .. Util.FormatTime(Config.Daily.Cooldown - since)
	end
	if since > Config.Daily.StreakResetAfter then
		data.DailyStreak = 0
	end
	data.DailyStreak += 1
	data.LastDaily = now
	local amount = self:GetDailyReward(player, data.DailyStreak)
	S.DataService:AddCash(player, amount, false)
	S.DataService:Sync(player)
	Remotes.VFX:FireClient(player, "Confetti", {})
	Remotes.VFX:FireClient(player, "CashBurst", { Amount = amount })
	return true, "Day " .. data.DailyStreak .. " reward: +" .. Util.Money(amount) .. "!"
end

function RewardService:Redeem(player: Player, code: any): (boolean, string)
	if type(code) ~= "string" then
		return false, "Invalid code"
	end
	if codeCooldown[player] and os.clock() - codeCooldown[player] < 2 then
		return false, "Slow down!"
	end
	codeCooldown[player] = os.clock()
	local data = S.DataService:Get(player)
	if not data then
		return false, "Data still loading..."
	end
	code = code:upper():gsub("%s", "")
	local reward = Config.Codes[code]
	if not reward or reward.Expired then
		return false, "That code doesn't exist or expired."
	end
	if data.RedeemedCodes[code] then
		return false, "You already redeemed this code!"
	end
	data.RedeemedCodes[code] = true
	local parts = {}
	if reward.Cash then
		local amount = incomeCash(player, reward.IncomeMinutes or 0, reward.Cash)
		S.DataService:AddCash(player, amount, false)
		table.insert(parts, "+" .. Util.Money(amount))
		Remotes.VFX:FireClient(player, "CashBurst", { Amount = amount })
	end
	if reward.BoostSeconds then
		S.DataService:AddBoost(player, reward.BoostSeconds)
		table.insert(parts, "2x Boost for " .. Util.FormatTime(reward.BoostSeconds))
	end
	Remotes.VFX:FireClient(player, "Confetti", {})
	return true, "Code redeemed! " .. table.concat(parts, " & ")
end

return RewardService
