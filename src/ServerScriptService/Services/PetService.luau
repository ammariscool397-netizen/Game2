--[[
	PetService - pets (see Config.Pets). Eggs cost cash and hatch a random pet;
	equipped pets follow you and add a permanent income bonus (DataService
	counts them in the multiplier). Everything is decided here: the client only
	asks. Pets are saved with the player.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local PC = Config.Pets

local PetService = {}
local S

local lastAction: { [Player]: number } = {}

local function rebirthsOf(player: Player): number
	local data = S.DataService:Get(player)
	return data and data.Rebirths or 0
end

-- equip slots: by rebirths, +1 with the "+1 Pet Slot" pass
function PetService:_slots(player: Player, data): number
	return Config.PetSlots(data.Rebirths) + (S.MonetizationService:HasPass(player, "PetSlot") and 1 or 0)
end

function PetService:GetEggCost(player: Player, egg): number
	local wallet = S.DataService:GetWallet(player)
	local rebirths = wallet and wallet.Rebirths or 0
	return math.floor(math.max(egg.MinCash * (1 + rebirths), S.TycoonService:GetIncome(player) * egg.IncomeSeconds))
end

function PetService:GetSellValue(player: Player, petId: string): number
	local pet = Config.PetById[petId]
	return pet and math.floor(PC.Rarities[pet.Rarity].SellCash * (1 + rebirthsOf(player))) or 0
end

local function findOwned(data, uid: any)
	for index, pet in data.Pets.Owned do
		if pet.Uid == uid then
			return pet, index
		end
	end
	return nil, nil
end

local function equippedIndex(data, uid: number): number?
	for index, equipped in data.Pets.Equipped do
		if equipped == uid then
			return index
		end
	end
	return nil
end

-- picks a pet from an egg: first a rarity by the egg's weights, then a pet of it
function PetService:_roll(egg, lucky: boolean?)
	local weights = {}
	local first = true
	for _, name in PC.RarityOrder do
		local weight = egg.Weights[name]
		if weight then
			-- Lucky Hatch: everything except the most common rarity is 1.6x likelier
			weights[name] = (lucky and not first) and weight * 1.6 or weight
			first = false
		end
	end
	local total = 0
	for _, weight in weights do
		total += weight
	end
	local roll = math.random() * total
	local rarity
	for _, name in PC.RarityOrder do
		local weight = weights[name]
		if weight then
			rarity = name
			roll -= weight
			if roll < 0 then
				break
			end
		end
	end
	local options = {}
	for _, pet in PC.List do
		if pet.Rarity == rarity and pet.Event == egg.Event then
			table.insert(options, pet)
		end
	end
	return options[math.random(1, #options)]
end

-- the client's view: the pets, the slots and what the eggs cost right now
function PetService:_state(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return nil
	end
	local eggs = {}
	for _, egg in PC.Eggs do
		table.insert(eggs, { Id = egg.Id, Cost = self:GetEggCost(player, egg), Active = egg.Event == nil or S.EventService:IsActive(egg.Event) })
	end
	local owned = {}
	for _, pet in data.Pets.Owned do
		table.insert(owned, { Uid = pet.Uid, Id = pet.Id, Sell = self:GetSellValue(player, pet.Id) })
	end
	return { Owned = owned, Equipped = data.Pets.Equipped, Slots = self:_slots(player, data), Eggs = eggs, Bonus = Config.PetsBonus(data.Pets) }
end

-- everyone sees equipped pets (attribute), the owner gets the full list
function PetService:_sync(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local ids = {}
	local byUid = {}
	for _, pet in data.Pets.Owned do
		byUid[pet.Uid] = pet
	end
	for _, uid in data.Pets.Equipped do
		if byUid[uid] then
			table.insert(ids, byUid[uid].Id)
		end
	end
	player:SetAttribute("Pets", table.concat(ids, ","))
	S.DataService:RefreshMultiplier(player)
	if player.Parent then
		Remotes.PetUpdate:FireClient(player, self:_state(player))
	end
end

-- drops equipped pets that don't exist or don't fit the slots (e.g. after a data edit)
function PetService:_clean(data)
	local seen, kept = {}, {}
	local slots = Config.PetSlots(data.Rebirths) + 1 -- (the pass's slot is checked when equipping)
	for _, uid in data.Pets.Equipped do
		if not seen[uid] and findOwned(data, uid) and #kept < slots then
			seen[uid] = true
			table.insert(kept, uid)
		end
	end
	data.Pets.Equipped = kept
end

-- gives pets (hatching and the admin command); returns how many fit
-- re-send the pets and refresh the income after another service changed them (trading)
function PetService:Resync(player: Player)
	self:_sync(player)
end

function PetService:Give(player: Player, petId: string, count: number?): number
	local data = S.DataService:Get(player)
	if not data or not Config.PetById[petId] then
		return 0
	end
	local given = 0
	for _ = 1, count or 1 do
		if #data.Pets.Owned >= PC.MaxOwned then
			break
		end
		table.insert(data.Pets.Owned, { Uid = data.Pets.NextUid, Id = petId })
		data.Pets.NextUid += 1
		given += 1
	end
	self:_sync(player)
	return given
end

function PetService:Hatch(player: Player, eggId: any): (boolean, string)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Data still loading..."
	end
	local egg
	for _, candidate in PC.Eggs do
		if candidate.Id == eggId then
			egg = candidate
		end
	end
	if not egg then
		return false, "Unknown egg."
	end
	if egg.Event and not S.EventService:IsActive(egg.Event) then
		return false, egg.Name .. " is only on sale during its event!"
	end
	if #data.Pets.Owned >= PC.MaxOwned then
		return false, "Your pet storage is full (" .. PC.MaxOwned .. ") - sell some pets!"
	end
	local cost = self:GetEggCost(player, egg)
	if not S.DataService:SpendCash(player, cost) then
		return false, "You need " .. Util.Money(cost) .. " for a " .. egg.Name .. "!"
	end
	local pet = self:_roll(egg, S.MonetizationService:HasPass(player, "PetLuck"))
	self:Give(player, pet.Id, 1)
	data.Pets.Hatched += 1
	if S.ProgressService then
		S.ProgressService:Record(player, "Hatch")
	end
	if S.QuestService then
		S.QuestService:Progress(player, "Hatch", 1)
	end
	local rarity = PC.Rarities[pet.Rarity]
	if rarity.Bonus >= 1 then
		Remotes.VFX:FireClient(player, "Confetti", {})
		if rarity.Bonus >= 2 then
			Remotes.Announce:FireAllClients({
				Title = "🥚 " .. player.DisplayName .. " hatched a MYTHIC!",
				Text = pet.Icon .. " " .. pet.Name .. " (+" .. rarity.Bonus .. "x income)",
				Color = rarity.Color,
			})
		end
	end
	return true, ("%s You hatched a %s %s! (%s, +%sx income)"):format(pet.Icon, pet.Rarity, pet.Name, pet.Rarity, tostring(rarity.Bonus))
end

function PetService:Equip(player: Player, uid: any): (boolean, string)
	local data = S.DataService:Get(player)
	local pet = data and findOwned(data, uid)
	if not data or not pet then
		return false, "You don't have that pet."
	end
	if equippedIndex(data, pet.Uid) then
		return false, "Already equipped."
	end
	local slots = self:_slots(player, data)
	if #data.Pets.Equipped >= slots then
		return false, "All " .. slots .. " pet slots are used - unequip one first. (More slots at " .. table.concat(PC.SlotRebirths, " and ") .. " rebirths.)"
	end
	table.insert(data.Pets.Equipped, pet.Uid)
	self:_sync(player)
	return true, "Equipped " .. Config.PetById[pet.Id].Name .. "!"
end

function PetService:Unequip(player: Player, uid: any): (boolean, string)
	local data = S.DataService:Get(player)
	local index = data and type(uid) == "number" and equippedIndex(data, uid)
	if not data or not index then
		return false, "That pet isn't equipped."
	end
	table.remove(data.Pets.Equipped, index)
	self:_sync(player)
	return true, "Unequipped."
end

function PetService:Sell(player: Player, uid: any): (boolean, string)
	local data = S.DataService:Get(player)
	local pet, index = nil, nil
	if data then
		pet, index = findOwned(data, uid)
	end
	if not data or not pet or not index then
		return false, "You don't have that pet."
	end
	local value = self:GetSellValue(player, pet.Id)
	local equipped = equippedIndex(data, pet.Uid)
	if equipped then
		table.remove(data.Pets.Equipped, equipped)
	end
	table.remove(data.Pets.Owned, index)
	S.DataService:AddCash(player, value, false)
	self:_sync(player)
	return true, "Sold " .. Config.PetById[pet.Id].Name .. " for " .. Util.Money(value) .. "."
end

-- the best pets (by bonus) fill the slots
function PetService:EquipBest(player: Player): (boolean, string)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Data still loading..."
	end
	local sorted = table.clone(data.Pets.Owned)
	table.sort(sorted, function(a, b)
		local ba, bb = Config.PetBonus(a.Id), Config.PetBonus(b.Id)
		if ba ~= bb then
			return ba > bb
		end
		return a.Uid < b.Uid
	end)
	data.Pets.Equipped = {}
	for _, pet in sorted do
		if #data.Pets.Equipped < self:_slots(player, data) then
			table.insert(data.Pets.Equipped, pet.Uid)
		end
	end
	self:_sync(player)
	return true, "Equipped your best pets (+" .. tostring(Config.PetsBonus(data.Pets)) .. "x income)."
end

function PetService:Init(services)
	S = services
	Remotes.PetAction.OnServerInvoke = function(player, action, arg)
		if not PC.Enabled then
			return false, "Pets are turned off."
		end
		if lastAction[player] and os.clock() - lastAction[player] < 0.25 then
			return false, "Slow down!"
		end
		lastAction[player] = os.clock()
		if action == "Hatch" then
			return self:Hatch(player, arg)
		elseif action == "Equip" then
			return self:Equip(player, arg)
		elseif action == "Unequip" then
			return self:Unequip(player, arg)
		elseif action == "Sell" then
			return self:Sell(player, arg)
		elseif action == "EquipBest" then
			return self:EquipBest(player)
		elseif action == "Refresh" then
			self:_sync(player)
			return true, ""
		end
		return false, "Unknown action."
	end
	S.DataService.PlayerLoaded:Connect(function(player, data)
		self:_clean(data)
		self:_sync(player)
	end)
	-- a rebirth can't remove slots, but a data edit could: keep the list valid
	S.DataService.BeforeSave:Connect(function(_, data)
		self:_clean(data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return PetService
