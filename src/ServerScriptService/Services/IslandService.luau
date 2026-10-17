--[[
	IslandService - the far islands (see Config.Islands): travelling there and
	the treasure chests. Each chest closes for Cooldown seconds after YOU open
	it; the time is saved with your data, so rejoining doesn't reopen it.
	Players get attributes the Travel panel shows:
	  ChestsReady_<island>  chests you can open now
	  ChestNext_<island>    when your next closed chest opens (epoch, 0 = none)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local BuildKit = require(script.Parent.BuildKit)

local IC = Config.Islands

local IslandService = {}
local S

local islandById = {}
for _, island in IC.List do
	islandById[island.Id] = island
end

local lastTravel: { [Player]: number } = {}
local lastChestNote: { [Player]: { [string]: number } } = {}

-- seconds a chest stays closed for this player (half with the Island Express pass)
function IslandService:_cooldown(player: Player): number
	return S.MonetizationService:HasPass(player, "IslandExpress") and IC.Cooldown / 2 or IC.Cooldown
end

function IslandService:_unlocked(player: Player, island): boolean
	local data = S.DataService:Get(player)
	return data ~= nil and data.Rebirths >= island.Rebirths
end

-- (ready now, the earliest time a closed chest opens or 0)
function IslandService:_status(player: Player, islandId: string): (number, number)
	local data = S.DataService:Get(player)
	local ready, nextAt = 0, 0
	if not data then
		return 0, 0
	end
	for _, entry in S.WorldBuilder.Chests do
		if entry.Island == islandId then
			local openAt = (data.Chests[entry.Id] or 0) + self:_cooldown(player)
			if os.time() >= openAt then
				ready += 1
			elseif nextAt == 0 or openAt < nextAt then
				nextAt = openAt
			end
		end
	end
	return ready, nextAt
end

function IslandService:_sync(player: Player)
	local total = 0
	for _, island in IC.List do
		local ready, nextAt = self:_status(player, island.Id)
		player:SetAttribute("ChestsReady_" .. island.Id, ready)
		player:SetAttribute("ChestNext_" .. island.Id, nextAt)
		if self:_unlocked(player, island) then
			total += ready
		end
	end
	player:SetAttribute("ChestsReady", total)
end

function IslandService:OpenChest(player: Player, entry)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local island = islandById[entry.Island]
	local openAt = (data.Chests[entry.Id] or 0) + self:_cooldown(player)
	if os.time() < openAt then
		-- say it once in a while, not every touch
		local notes = lastChestNote[player] or {}
		lastChestNote[player] = notes
		if not notes[entry.Id] or os.clock() - notes[entry.Id] > 6 then
			notes[entry.Id] = os.clock()
			Remotes.Notify:FireClient(player, { Text = "🔒 This chest opens again in " .. Util.FormatTime(openAt - os.time()), Type = "info" })
		end
		return
	end
	data.Chests[entry.Id] = os.time()
	local wallet = S.DataService:GetWallet(player)
	local rebirths = wallet and wallet.Rebirths or 0
	local cash = math.floor(math.max(island.MinCash * (1 + rebirths), S.TycoonService:GetIncome(player) * island.IncomeSeconds))
	S.DataService:AddCash(player, cash, false)
	Remotes.VFX:FireClient(player, "CashBurst", { Amount = cash })
	Remotes.VFX:FireClient(player, "PurchaseSound", {})
	Remotes.Notify:FireClient(player, { Text = "💰 " .. island.Name .. " chest: +" .. Util.Money(cash) .. "!", Type = "success" })
	self:_sync(player)
end

-- ("Plaza" or an island id) -> ok, message
function IslandService:Travel(player: Player, destination: any): (boolean, string)
	local data = S.DataService:Get(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not character or not humanoid or humanoid.Health <= 0 then
		return false, "You can't travel right now."
	end
	if player:GetAttribute("InMinigame") then
		return false, "Finish the minigame first!"
	end
	if lastTravel[player] and os.clock() - lastTravel[player] < IC.TravelDelay then
		return false, "Slow down - wait a moment between trips."
	end
	local target, text
	if destination == "Plaza" then
		target, text = IC.Plaza, "🏠 Back on the main island!"
	else
		local island = type(destination) == "string" and islandById[destination]
		local info = island and S.WorldBuilder.Islands[destination]
		if not island or not info then
			return false, "Unknown destination."
		end
		if not self:_unlocked(player, island) then
			return false, island.Name .. " unlocks at " .. island.Rebirths .. " rebirths."
		end
		target, text = info.Spawn, island.Icon .. " Welcome to " .. island.Name .. "!"
	end
	lastTravel[player] = os.clock()
	character:PivotTo(CFrame.new(target))
	return true, text
end

function IslandService:Init(services)
	S = services
	Remotes.Travel.OnServerInvoke = function(player, destination)
		if not IC.Enabled then
			return false, "Travel is turned off."
		end
		return self:Travel(player, destination)
	end
	-- the chests
	for _, entry in S.WorldBuilder.Chests do
		entry.Part.Touched:Connect(function(hit)
			local player = BuildKit.PlayerFromHit(hit)
			if player and BuildKit.IsNear(player, entry.Part) then
				self:OpenChest(player, entry)
			end
		end)
	end
	-- the pads back to the plaza
	for _, pad in S.WorldBuilder.ReturnPads do
		pad.Part.Touched:Connect(function(hit)
			local player = BuildKit.PlayerFromHit(hit)
			if player and BuildKit.IsNear(player, pad.Part) then
				self:Travel(player, "Plaza")
			end
		end)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		self:_sync(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastTravel[player], lastChestNote[player] = nil, nil
	end)
end

-- the "chests ready" numbers change as the cooldowns run out
function IslandService:Start()
	while true do
		task.wait(5)
		for _, player in Players:GetPlayers() do
			if S.DataService:Get(player) then
				Util.Try("Islands", self._sync, self, player)
			end
		end
	end
end

return IslandService
