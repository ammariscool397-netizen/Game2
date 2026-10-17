--[[
	GiftService - playtime gifts (see Config.Gifts). The longer you play today,
	the more gifts unlock; each pays minutes of your income and the last one
	also gives a 2x boost. Time played and the gifts opened are SAVED, so
	leaving and rejoining doesn't restart the wait. A new UTC day starts over.
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

-- when this visit's playtime was last added to the saved total
local sessions: { [Player]: { Start: number } } = {}

local function today(): number
	return os.time() // 86400
end

-- adds the time played since the last call to the saved total (and starts a new day over)
function GiftService:_bank(player: Player)
	local session = sessions[player]
	local data = S.DataService:Get(player)
	if not session or not data then
		return
	end
	local gifts = data.Gifts
	local now = os.time()
	if gifts.Day ~= today() then
		gifts.Day, gifts.Index, gifts.Played = today(), 1, 0
		session.Start = now
		return
	end
	gifts.Played += math.max(0, now - session.Start)
	session.Start = now
end

function GiftService:GetState(player: Player)
	local data = S.DataService:Get(player)
	if not data or not sessions[player] then
		return nil
	end
	self:_bank(player)
	local gifts = data.Gifts
	local total = #GC.Minutes
	if gifts.Index > total then
		return { Index = gifts.Index, Total = total, ReadyIn = -1 }
	end
	return { Index = gifts.Index, Total = total, ReadyIn = math.max(0, GC.Minutes[gifts.Index] * 60 - gifts.Played) }
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
	local cash = math.max(GC.MinCash[index] * (1 + rebirths), S.TycoonService:GetIncome(player) * GC.IncomeMinutes[index] * 60)
	return math.floor(cash * (1 + Config.RebirthPerk(rebirths, "Gift") + (S.MonetizationService:HasPass(player, "GiftBoost") and 0.5 or 0)))
end

function GiftService:Claim(player: Player): (boolean, string)
	local state = self:GetState(player)
	if not state then
		return false, "Data still loading..."
	end
	local data = S.DataService:Get(player)
	if state.ReadyIn < 0 then
		return false, "You opened every gift today! Come back tomorrow."
	end
	if state.ReadyIn > 0 then
		return false, "Your next gift opens in " .. Util.FormatTime(state.ReadyIn)
	end
	local index = state.Index
	data.Gifts.Index += 1
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
		sessions[player] = { Start = os.time() }
		self:_bank(player) -- (starts a new day over)
		self:_send(player)
	end)
	-- the time played so far is saved with the rest of the data
	S.DataService.BeforeSave:Connect(function(player)
		self:_bank(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
end

-- a new day while someone is playing: their gifts start over
function GiftService:Start()
	if not GC.Enabled then
		return
	end
	while true do
		task.wait(30)
		for player in sessions do
			local data = S.DataService:Get(player)
			if data and data.Gifts.Day ~= today() then
				Util.Try("Gifts", self._send, self, player)
			end
		end
	end
end

return GiftService
