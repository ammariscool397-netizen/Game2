--[[
	WheelService - the Lucky Wheel (see Config.Wheel): a free spin every
	CooldownMinutes. The server picks the prize; the client only animates it.
	The time of the last spin is saved, so the wait also counts while offline.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local WC = Config.Wheel

local WheelService = {}
local S

-- picks a segment index by weight
function WheelService:_pick(): number
	local total = 0
	for _, segment in WC.Segments do
		total += segment.Weight
	end
	local roll = math.random() * total
	for i, segment in WC.Segments do
		roll -= segment.Weight
		if roll < 0 then
			return i
		end
	end
	return #WC.Segments
end

-- (cash, boost seconds) a segment pays this player
function WheelService:GetPrize(player: Player, segment): (number, number)
	local wallet = S.DataService:GetWallet(player)
	local rebirths = wallet and wallet.Rebirths or 0
	local cash = 0
	if segment.Minutes then
		cash = math.floor(math.max((segment.MinCash or 0) * (1 + rebirths), S.TycoonService:GetIncome(player) * segment.Minutes * 60))
	end
	return cash, segment.BoostSeconds or 0
end

function WheelService:_sync(player: Player)
	local data = S.DataService:Get(player)
	if data then
		player:SetAttribute("WheelReadyAt", data.Wheel.Last + WC.CooldownMinutes * 60)
	end
end

function WheelService:Spin(player: Player): (boolean, number, string)
	local data = S.DataService:Get(player)
	if not data then
		return false, 0, "Data still loading..."
	end
	local readyAt = data.Wheel.Last + WC.CooldownMinutes * 60
	if os.time() < readyAt then
		return false, 0, "Your next free spin is in " .. Util.FormatTime(readyAt - os.time())
	end
	local index = self:_pick()
	local segment = WC.Segments[index]
	local cash, boost = self:GetPrize(player, segment)
	data.Wheel.Last = os.time()
	data.Wheel.Spins += 1
	self:_sync(player)
	if cash > 0 then
		S.DataService:AddCash(player, cash, false)
	end
	if boost > 0 then
		S.DataService:AddBoost(player, boost)
	end
	local text = segment.Icon .. " " .. segment.Name .. ": "
	if cash > 0 then
		text ..= "+" .. Util.Money(cash)
	else
		text ..= "2x cash for " .. Util.FormatTime(boost)
	end
	-- the effects wait until the client's reel has stopped
	task.delay(WC.SpinSeconds, function()
		if player.Parent then
			if cash > 0 then
				Remotes.VFX:FireClient(player, "CashBurst", { Amount = cash })
			end
			Remotes.VFX:FireClient(player, "Confetti", {})
		end
		if segment.Weight <= 3 then
			Remotes.Announce:FireAllClients({
				Title = "🎰 " .. player.DisplayName .. " won " .. segment.Name .. "!",
				Text = text,
				Color = segment.Color,
			})
		end
	end)
	return true, index, text
end

function WheelService:Init(services)
	S = services
	Remotes.SpinWheel.OnServerInvoke = function(player)
		if not WC.Enabled then
			return false, 0, "The wheel is turned off."
		end
		return self:Spin(player)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		self:_sync(player)
	end)
end

return WheelService
