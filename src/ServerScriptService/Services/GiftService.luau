--[[
	GiftService - playtime gifts (see Config.Gifts). The longer you stay in
	the server, the more gifts unlock; each pays minutes of your income and
	the last one also gives a 2x boost. Counts per session (not saved).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local GC = Config.Gifts

local GiftService = {}
local S

local sessions: { [Player]: { Start: number, Index: number } } = {}

function GiftService:GetState(player: Player)
	local session = sessions[player]
	if not session then
		return nil
	end
	local total = #GC.Minutes
	if session.Index > total then
		return { Index = session.Index, Total = total, ReadyIn = -1 }
	end
	local readyAt = session.Start + GC.Minutes[session.Index] * 60
	return { Index = session.Index, Total = total, ReadyIn = math.max(0, readyAt - os.time()) }
end

function GiftService:_send(player: Player)
	local state = self:GetState(player)
	if state and player.Parent then
		Remotes.GiftUpdate:FireClient(player, state)
	end
end

function GiftService:GetReward(player: Player, index: number): number
	local wallet = S.DataService:GetWallet(player)
	local rebirths = wallet and wallet.Rebirths or 0
	return math.floor(math.max(GC.MinCash[index] * (1 + rebirths), S.TycoonService:GetIncome(player) * GC.IncomeMinutes[index] * 60))
end

function GiftService:Claim(player: Player): (boolean, string)
	local session = sessions[player]
	if not session or not S.DataService:IsLoaded(player) then
		return false, "Data still loading..."
	end
	local index = session.Index
	if index > #GC.Minutes then
		return false, "You opened every gift this session!"
	end
	local readyAt = session.Start + GC.Minutes[index] * 60
	if os.time() < readyAt then
		return false, "Your next gift opens in " .. Util.FormatTime(readyAt - os.time())
	end
	session.Index += 1
	local cash = self:GetReward(player, index)
	S.DataService:AddCash(player, cash, false)
	local text = "🎁 Gift " .. index .. "/" .. #GC.Minutes .. ": +" .. Util.Money(cash)
	if index == #GC.Minutes and GC.FinalBoostSeconds then
		S.DataService:AddBoost(player, GC.FinalBoostSeconds)
		text ..= " & 2x Boost!"
	end
	Remotes.VFX:FireClient(player, "CashBurst", { Amount = cash })
	Remotes.VFX:FireClient(player, "Confetti", {})
	self:_send(player)
	return true, text
end

function GiftService:Init(services)
	S = services
	if not GC.Enabled then
		return
	end
	Remotes.ClaimGift.OnServerInvoke = function(player)
		return self:Claim(player)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		sessions[player] = { Start = os.time(), Index = 1 }
		self:_send(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

return GiftService
