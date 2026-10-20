--[[
	TutorialService - pays the reward of the first-time tutorial. The client
	shows the steps; the server checks them from the saved data before paying
	(buy a few upgrades, spin the wheel, claim the daily reward), once per account.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local TC = Config.Tutorial

local TutorialService = {}
local S

local function owned(data): number
	local n = 0
	for _ in data.Purchased do
		n += 1
	end
	return n
end

function TutorialService:Claim(player: Player)
	local data = S.DataService:Get(player)
	if not TC.Enabled or not data or data.Tutorial.Done then
		return
	end
	local boughtEnough = math.max(owned(data) - 1, data.Stats.Upgrades or 0) >= TC.BuyUpgrades
	if not boughtEnough or data.Wheel.Spins < 1 or data.DailyStreak < 1 then
		return -- the client is wrong or cheating: nothing happens
	end
	data.Tutorial.Done = true
	player:SetAttribute("TutorialDone", true)
	local cash = math.floor(math.max(TC.Reward.MinCash * (1 + data.Rebirths), S.TycoonService:GetIncome(player) * TC.Reward.Minutes * 60))
	S.DataService:AddCash(player, cash, false)
	Remotes.Notify:FireClient(player, { Text = "🎓 Tutorial complete! +" .. Util.Money(cash), Type = "success", Duration = 7 })
	Remotes.VFX:FireClient(player, "Confetti", {})
	Remotes.VFX:FireClient(player, "CashBurst", { Amount = cash })
end

function TutorialService:Init(services)
	S = services
	Remotes.TutorialClaim.OnServerEvent:Connect(function(player)
		self:Claim(player)
	end)
	S.DataService.PlayerLoaded:Connect(function(player, data)
		-- players who already got far don't need the tutorial
		if not data.Tutorial.Done and (data.Wheel.Spins > 0 and data.DailyStreak > 0 and owned(data) > TC.BuyUpgrades) then
			data.Tutorial.Done = true
		end
		player:SetAttribute("TutorialDone", data.Tutorial.Done or not TC.Enabled)
	end)
end

return TutorialService
