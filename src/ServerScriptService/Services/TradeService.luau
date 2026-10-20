--[[
	TradeService - trade pets with another player in the same server.
	Flow: Invite -> the other player Responds (accept) -> both Add pets -> both
	press Accept -> the pets swap. Any change to either offer resets both accepts
	and the Accept button waits Config.Trading.ConfirmDelay seconds again (so
	nobody can swap an offer at the last moment). Cash can't be traded.
	The swap happens in one step on the server; both saves follow right away.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local TC = Config.Trading

local TradeService = {}
local S

type Trade = {
	A: Player,
	B: Player,
	Offer: { [Player]: { number } }, -- pet uids
	Accepted: { [Player]: boolean },
	ReadyAt: number, -- os.clock when Accept is allowed
	ReadyAtServer: number, -- the same, as server unix time (for the clients' countdown)
	Started: number,
}

local trades: { [Player]: Trade } = {} -- both players point at the same trade
local invites: { [Player]: { From: Player, Expires: number } } = {} -- by the invited player
local lastAction: { [Player]: number } = {}
local lastCounted: { [Player]: number } = {}

local function findOwned(data, uid: number)
	for index, pet in data.Pets.Owned do
		if pet.Uid == uid then
			return pet, index
		end
	end
	return nil, nil
end

local function other(trade: Trade, player: Player): Player
	return trade.A == player and trade.B or trade.A
end

function TradeService:_view(trade: Trade, player: Player)
	local partner = other(trade, player)
	local function list(owner: Player)
		local data = S.DataService:Get(owner)
		local pets = {}
		for _, uid in trade.Offer[owner] do
			local pet = data and findOwned(data, uid)
			if pet then
				table.insert(pets, { Uid = pet.Uid, Id = pet.Id })
			end
		end
		return pets
	end
	return {
		Partner = { Name = partner.DisplayName, UserId = partner.UserId },
		Mine = list(player),
		Theirs = list(partner),
		MyAccepted = trade.Accepted[player] == true,
		TheirAccepted = trade.Accepted[partner] == true,
		ReadyAt = trade.ReadyAtServer,
		MaxPets = TC.MaxPets,
	}
end

function TradeService:_send(trade: Trade)
	for _, player in { trade.A, trade.B } do
		if player.Parent then
			Remotes.TradeUpdate:FireClient(player, self:_view(trade, player))
		end
	end
end

-- ends a trade; `reason` is shown to both
function TradeService:_end(trade: Trade, reason: string?, kind: string?)
	trades[trade.A], trades[trade.B] = nil, nil
	for _, player in { trade.A, trade.B } do
		if player.Parent then
			Remotes.TradeUpdate:FireClient(player, nil)
			if reason then
				Remotes.Notify:FireClient(player, { Text = reason, Type = kind or "info", Duration = 5 })
			end
		end
	end
end

function TradeService:_changed(trade: Trade)
	trade.Accepted = {}
	trade.ReadyAt = os.clock() + TC.ConfirmDelay
	trade.ReadyAtServer = os.time() + TC.ConfirmDelay
	self:_send(trade)
end

function TradeService:Invite(player: Player, targetUserId: any): (boolean, string)
	if type(targetUserId) ~= "number" then
		return false, "Pick a player."
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player then
		return false, "That player isn't here."
	end
	if not S.DataService:IsLoaded(player) or not S.DataService:IsLoaded(target) then
		return false, "Data still loading..."
	end
	if not S.DataService:CanSave(player) or not S.DataService:CanSave(target) then
		return false, "Trading isn't available right now."
	end
	if trades[player] then
		return false, "Finish your current trade first."
	end
	if trades[target] then
		return false, target.DisplayName .. " is already trading."
	end
	invites[target] = { From = player, Expires = os.clock() + TC.InviteTimeout }
	Remotes.TradeInvited:FireClient(target, { FromName = player.DisplayName, FromUserId = player.UserId, Timeout = TC.InviteTimeout })
	return true, "Trade request sent to " .. target.DisplayName .. "."
end

function TradeService:Respond(player: Player, accept: any): (boolean, string)
	local invite = invites[player]
	invites[player] = nil
	if not invite or invite.Expires < os.clock() or not invite.From.Parent then
		return false, "That request has expired."
	end
	local from = invite.From
	if accept ~= true then
		Remotes.Notify:FireClient(from, { Text = player.DisplayName .. " declined your trade.", Type = "info" })
		return true, "Declined."
	end
	if trades[from] or trades[player] then
		return false, "One of you is already trading."
	end
	local trade: Trade = {
		A = from,
		B = player,
		Offer = { [from] = {}, [player] = {} },
		Accepted = {},
		ReadyAt = os.clock() + TC.ConfirmDelay,
		ReadyAtServer = os.time() + TC.ConfirmDelay,
		Started = os.clock(),
	}
	trades[from], trades[player] = trade, trade
	self:_send(trade)
	return true, "Trading with " .. from.DisplayName .. "!"
end

function TradeService:Add(player: Player, uid: any): (boolean, string)
	local trade = trades[player]
	local data = S.DataService:Get(player)
	if not trade or not data or type(uid) ~= "number" then
		return false, "You're not trading."
	end
	if not findOwned(data, uid) then
		return false, "You don't have that pet."
	end
	local offer = trade.Offer[player]
	if table.find(offer, uid) then
		return false, "Already in the trade."
	end
	if #offer >= TC.MaxPets then
		return false, "You can offer up to " .. TC.MaxPets .. " pets."
	end
	table.insert(offer, uid)
	self:_changed(trade)
	return true, ""
end

function TradeService:Remove(player: Player, uid: any): (boolean, string)
	local trade = trades[player]
	local index = trade and type(uid) == "number" and table.find(trade.Offer[player], uid)
	if not trade or not index then
		return false, "That pet isn't in the trade."
	end
	table.remove(trade.Offer[player], index)
	self:_changed(trade)
	return true, ""
end

function TradeService:Accept(player: Player): (boolean, string)
	local trade = trades[player]
	if not trade then
		return false, "You're not trading."
	end
	if #trade.Offer[trade.A] + #trade.Offer[trade.B] == 0 then
		return false, "Add a pet first."
	end
	if os.clock() < trade.ReadyAt then
		return false, "Wait a moment and check the offer carefully!"
	end
	trade.Accepted[player] = true
	if trade.Accepted[trade.A] and trade.Accepted[trade.B] then
		return self:_execute(trade)
	end
	self:_send(trade)
	return true, "Waiting for " .. other(trade, player).DisplayName .. "..."
end

function TradeService:_execute(trade: Trade): (boolean, string)
	local a, b = trade.A, trade.B
	local dataA, dataB = S.DataService:Get(a), S.DataService:Get(b)
	if not dataA or not dataB or not S.DataService:CanSave(a) or not S.DataService:CanSave(b) then
		self:_end(trade, "The trade was cancelled.", "error")
		return false, "Trade cancelled."
	end
	-- everything must still be true right now
	local movingA, movingB = {}, {}
	for _, uid in trade.Offer[a] do
		local pet = findOwned(dataA, uid)
		if not pet then
			self:_end(trade, "The trade was cancelled: a pet is gone.", "error")
			return false, "Trade cancelled."
		end
		table.insert(movingA, pet)
	end
	for _, uid in trade.Offer[b] do
		local pet = findOwned(dataB, uid)
		if not pet then
			self:_end(trade, "The trade was cancelled: a pet is gone.", "error")
			return false, "Trade cancelled."
		end
		table.insert(movingB, pet)
	end
	local maxOwned = Config.Pets.MaxOwned
	if #dataA.Pets.Owned - #movingA + #movingB > maxOwned or #dataB.Pets.Owned - #movingB + #movingA > maxOwned then
		self:_end(trade, "The trade was cancelled: someone's pet storage would be full.", "error")
		return false, "Trade cancelled."
	end

	local function take(data, moving)
		for _, pet in moving do
			local _, index = findOwned(data, pet.Uid)
			if index then
				table.remove(data.Pets.Owned, index)
			end
			local equipped = table.find(data.Pets.Equipped, pet.Uid)
			if equipped then
				table.remove(data.Pets.Equipped, equipped)
			end
		end
	end
	local function receive(data, moving)
		for _, pet in moving do
			table.insert(data.Pets.Owned, { Uid = data.Pets.NextUid, Id = pet.Id })
			data.Pets.NextUid += 1
		end
	end
	-- copy the ids first (take() removes the records)
	local idsA, idsB = {}, {}
	for _, pet in movingA do
		table.insert(idsA, { Id = pet.Id, Uid = pet.Uid })
	end
	for _, pet in movingB do
		table.insert(idsB, { Id = pet.Id, Uid = pet.Uid })
	end
	take(dataA, idsA)
	take(dataB, idsB)
	receive(dataA, idsB)
	receive(dataB, idsA)

	trades[a], trades[b] = nil, nil
	for _, player in { a, b } do
		Remotes.TradeUpdate:FireClient(player, nil)
		Remotes.Notify:FireClient(player, { Text = "🤝 Trade complete with " .. other(trade, player).DisplayName .. "!", Type = "success", Duration = 6 })
		Remotes.VFX:FireClient(player, "Confetti", {})
		S.PetService:Resync(player)
		-- trades count for achievements at most every 10 minutes (no farming with a second account)
		if S.ProgressService and (not lastCounted[player] or os.clock() - lastCounted[player] >= 600) then
			lastCounted[player] = os.clock()
			S.ProgressService:Record(player, "Trade")
		end
	end
	-- save both right away so a crash can't duplicate or lose pets
	task.spawn(function()
		for _, player in { a, b } do
			if player.Parent and not S.DataService:Save(player) then
				warn("[Trade] could not save " .. player.Name .. " after a trade")
			end
		end
	end)
	return true, "Trade complete!"
end

function TradeService:Cancel(player: Player): (boolean, string)
	local trade = trades[player]
	if not trade then
		return false, "You're not trading."
	end
	self:_end(trade, "❌ " .. player.DisplayName .. " cancelled the trade.", "info")
	return true, "Trade cancelled."
end

function TradeService:Init(services)
	S = services
	Remotes.TradeAction.OnServerInvoke = function(player, action, arg)
		if not TC.Enabled then
			return false, "Trading is turned off."
		end
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < 0.2 then
			return false, "Slow down!"
		end
		lastAction[player] = now
		if action == "Invite" then
			return self:Invite(player, arg)
		elseif action == "Respond" then
			return self:Respond(player, arg)
		elseif action == "Add" then
			return self:Add(player, arg)
		elseif action == "Remove" then
			return self:Remove(player, arg)
		elseif action == "Accept" then
			return self:Accept(player)
		elseif action == "Cancel" then
			return self:Cancel(player)
		end
		return false, "Unknown action."
	end
	Players.PlayerRemoving:Connect(function(player)
		local trade = trades[player]
		if trade then
			self:_end(trade, "❌ " .. player.DisplayName .. " left - the trade was cancelled.", "info")
		end
		invites[player] = nil
		lastAction[player] = nil
		lastCounted[player] = nil
		for target, invite in invites do
			if invite.From == player then
				invites[target] = nil
			end
		end
	end)
end

function TradeService:Start()
	while true do
		task.wait(5)
		local seen = {}
		for _, trade in trades do
			if not seen[trade] then
				seen[trade] = true
				if os.clock() - trade.Started > TC.TradeTimeout then
					self:_end(trade, "⌛ The trade timed out.", "info")
				end
			end
		end
		for target, invite in invites do
			if invite.Expires < os.clock() then
				invites[target] = nil
			end
		end
	end
end

return TradeService
