--[[
	TycoonService - plots, 8-floor towers, purchasing (buttons + Build menu),
	income ticks, vaults, elevators, rebirths, disaster knockouts/repairs,
	shelters and duo plot membership.

	Income is computed on the server from TycoonItems.ComputeIncome (no physics
	drops on the server). Clients render the falling drops locally using the
	attributes set on dropper / upgrader / generator models.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local TycoonItems = require(Shared.TycoonItems)
local BuildKit = require(script.Parent.BuildKit)
local TycoonBuilder = require(script.Parent.TycoonBuilder)

local TycoonService = {}
local S

local TC = Config.Tycoon
local FLOORS = TC.Floors
local PLOT_RADIUS = 270

local plots = {}
local playerPlot: { [Player]: any } = {}

local GREEN = Color3.fromRGB(60, 220, 100)
local RED = Color3.fromRGB(235, 70, 70)

local KNOCKOUT_KINDS = {
	Dropper = true,
	Upgrader = true,
	Generator = true,
	Decor = true,
	Boost = true,
	Conveyor = true,
	Special = true,
	Roof = true,
}

local function isMember(player: Player, plot): boolean
	return plot ~= nil and (plot.Owner == player or plot.Partner == player)
end

local function members(plot): { Player }
	local list = {}
	if plot.Owner then
		table.insert(list, plot.Owner)
	end
	if plot.Partner then
		table.insert(list, plot.Partner)
	end
	return list
end

local function sendUpdate(plot, payload)
	for _, member in members(plot) do
		Remotes.TycoonUpdate:FireClient(member, payload)
	end
end

local function quest(player: Player, kind: string, amount: number?)
	if S.QuestService then
		S.QuestService:Progress(player, kind, amount)
	end
end

local function canKnockOut(item): boolean
	if not KNOCKOUT_KINDS[item.Kind] then
		return false
	end
	if item.Kind == "Special" and item.Effect ~= "Bonus" then
		return false -- bunkers and shields can't be wrecked
	end
	if item.Kind == "Roof" and item.Model == "Helipad" then
		return false -- it's the roof itself
	end
	return true
end

---------------------------------------------------------------------------
function TycoonService:Init(services)
	S = services
	local folder = Instance.new("Folder")
	folder.Name = "Tycoons"
	folder.Parent = workspace

	for index = 1, Config.MaxPlots do
		local angle = math.rad(22.5 + (index - 1) * (360 / Config.MaxPlots))
		local pos = Vector3.new(math.cos(angle) * PLOT_RADIUS, 0, math.sin(angle) * PLOT_RADIUS)
		local cf = CFrame.lookAt(pos, Vector3.new(0, 0, 0))
		local plot = TycoonBuilder.BuildPlot(index, cf, folder)
		plot.Owner = nil
		plot.Partner = nil
		plot.Built = {}
		plot.Extra = {}
		plot.ButtonObjs = {}
		plot.SlotUsed = {}
		plot.Disabled = {}
		plot.RubbleModels = {}
		plot.ItemPos = {}
		plot.Worth = {}
		plot.Income = 0
		plot.Connections = {}
		plot.VaultLabels = {}
		plot.Queue = {}
		plot.LastPad = 0
		plot.Generation = 0
		plots[index] = plot
	end

	S.DataService.PlayerLoaded:Connect(function(player, data)
		self:_assign(player, data)
	end)
	-- offline earnings use the player's OWN tower (also while they're a duo
	-- partner). Computed from data, so it works no matter whether the tower
	-- was already cleared when the leave-save runs.
	S.DataService.BeforeSave:Connect(function(player, data)
		data.LastIncome = self:GetOfflineIncome(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_onLeave(player)
	end)
	Players.PlayerAdded:Connect(function(player)
		self:_hookCharacter(player)
	end)
	for _, player in Players:GetPlayers() do
		self:_hookCharacter(player)
	end

	Remotes.RequestRebirth.OnServerEvent:Connect(function(player)
		self:Rebirth(player)
	end)
	Remotes.GoHome.OnServerEvent:Connect(function(player)
		if player:GetAttribute("InMinigame") then
			return
		end
		player:SetAttribute("ObbyStage", 0)
		self:TeleportHome(player)
	end)
	Remotes.BuyItem.OnServerInvoke = function(player, itemId)
		if type(itemId) ~= "string" then
			return false, "Invalid item"
		end
		return self:TryPurchase(player, itemId)
	end
	Remotes.BuyAll.OnServerEvent:Connect(function(player, floor)
		self:BuyAll(player, type(floor) == "number" and floor or nil)
	end)
	Remotes.TeleportFloor.OnServerEvent:Connect(function(player, plotIndex, floor)
		self:TeleportToFloor(player, plotIndex, floor)
	end)
	Remotes.GetTycoonState.OnServerInvoke = function(player)
		return self:GetState(player)
	end
end

function TycoonService:Start()
	-- build queues: spread big towers over several frames
	RunService.Heartbeat:Connect(function()
		for _, plot in plots do
			if #plot.Queue > 0 then
				local n = 0
				while #plot.Queue > 0 and n < TC.MaxBuildPerTick do
					local job = table.remove(plot.Queue, 1)
					if job.Generation == plot.Generation and plot.Owner then
						local ok, err = pcall(self._buildItem, self, plot, job.Item, false)
						if not ok then
							warn("[Tycoon] Failed to build " .. job.Item.Id .. ": " .. tostring(err))
						end
					end
					n += 1
				end
				if #plot.Queue == 0 then
					self:_afterBulkBuild(plot)
				end
			end
		end
	end)

	-- income tick + repairs (each tower protected on its own: one bug must
	-- never stop everybody's income)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for _, plot in plots do
				Util.Try("Tycoon income", self._tick, self, plot, now)
			end
		end
	end)
end

function TycoonService:_tick(plot, now: number)
	local owner = plot.Owner
	if not owner or not S.DataService:IsLoaded(owner) then
		return
	end
	-- repair wrecked items whose timer ran out
	local due = {}
	for id, untilTime in plot.Disabled do
		if now >= untilTime then
			table.insert(due, id)
		end
	end
	for _, id in due do
		self:_repair(plot, id)
	end
	if #due > 0 then
		self:_recompute(plot)
	end
	-- Auto Builder pass: buys the cheapest affordable upgrade every few seconds
	local data = S.DataService:Get(owner)
	if data and data.Settings.AutoBuild ~= false and S.DataService:TeamHasPass(owner, "AutoBuild") then
		plot.AutoBuildTimer = (plot.AutoBuildTimer or 0) + 1
		if plot.AutoBuildTimer >= Config.AutoBuild.Interval and #plot.Queue == 0 then
			plot.AutoBuildTimer = 0
			local bought = self:_buyCheapest(owner, plot, data, Config.AutoBuild.PerTick)
			if #bought > 0 then
				self:_refreshButtons(plot)
				self:_recompute(plot)
				local last = TycoonItems.ById[bought[#bought]]
				Remotes.VFX:FireAllClients("BuildIn", { Model = plot.Built[last.Id], Position = plot.ItemPos[last.Id], Color = last.Theme and last.Theme.Accent or plot.Color })
			end
		end
	end

	local mult = S.DataService:GetMultiplier(owner)
	local amount = plot.Income * mult
	if amount > 0 then
		if S.DataService:TeamHasPass(owner, "AutoCollect") then
			S.DataService:AddCash(owner, amount)
		else
			S.DataService:AddVault(owner, amount)
		end
	end
	for _, member in members(plot) do
		member:SetAttribute("Income", amount)
		if amount > 0 then
			quest(member, "Earn", amount)
		end
	end
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
function TycoonService:GetPlot(player: Player)
	return playerPlot[player]
end

function TycoonService:GetPlots()
	return plots
end

function TycoonService:IsMember(player: Player, plot): boolean
	return isMember(player, plot)
end

-- current income per second (with all multipliers) of the player's tower
function TycoonService:GetIncome(player: Player): number
	local plot = playerPlot[player]
	if not plot or not plot.Owner then
		return 0
	end
	return plot.Income * S.DataService:GetMultiplier(plot.Owner)
end

-- income per second used for offline earnings: the player's full tower
-- (wrecked items repair while they're away) with permanent multipliers only
function TycoonService:GetOfflineIncome(player: Player): number
	local data = S.DataService:Get(player)
	if not data then
		return 0
	end
	local fast = S.MonetizationService ~= nil and S.MonetizationService:HasPass(player, "FastDroppers")
	local income = TycoonItems.ComputeIncome(data.Purchased, nil, data.Secrets, fast)
	return income * S.DataService:GetMultiplier(player, true)
end

function TycoonService:IsFloorUnlocked(plot, floor: number): boolean
	if not plot.Owner then
		return false
	end
	local data = S.DataService:Get(plot.Owner)
	if not data then
		return false
	end
	if floor == FLOORS + 1 then
		return data.Purchased["Roof_1"] == true
	end
	return data.Purchased[TycoonItems.FloorUnlockId(floor)] == true
end

function TycoonService:GetState(player: Player)
	local plot = playerPlot[player]
	if not plot or not plot.Owner then
		return { Plot = nil }
	end
	local data = S.DataService:Get(plot.Owner)
	if not data then
		return { Plot = nil }
	end
	local purchased = {}
	for id in data.Purchased do
		purchased[id] = true
	end
	local disabled = {}
	for id, untilTime in plot.Disabled do
		disabled[id] = math.max(0, untilTime - os.time())
	end
	local secrets = {}
	for id in data.Secrets do
		secrets[id] = true
	end
	return {
		Plot = plot.Index,
		IsOwner = plot.Owner == player,
		OwnerName = plot.Owner.DisplayName,
		Purchased = purchased,
		Disabled = disabled,
		Secrets = secrets,
		Shielded = plot.Shielded == true,
	}
end

---------------------------------------------------------------------------
-- Assignment
---------------------------------------------------------------------------
function TycoonService:_updateSign(plot)
	local text = "EMPTY PLOT"
	if plot.Owner then
		text = string.upper(plot.Owner.DisplayName) .. "'S TOWER"
		if plot.Partner then
			text = string.upper(plot.Owner.DisplayName) .. " & " .. string.upper(plot.Partner.DisplayName)
		end
	end
	for _, label in plot.SignLabels do
		label.Text = text
	end
end

function TycoonService:_assign(player: Player, data)
	if playerPlot[player] or player:GetAttribute("DuoHost") then
		return
	end
	local plot
	for _, p in plots do
		if not p.Owner then
			plot = p
			break
		end
	end
	if not plot then
		Remotes.Notify:FireClient(player, { Text = "All plots are taken! Ask someone to DUO with you, or play minigames and the obby.", Type = "error", Duration = 8 })
		return
	end
	plot.Owner = player
	plot.Partner = nil
	playerPlot[player] = plot
	player:SetAttribute("Plot", plot.Index)
	player:SetAttribute("PlotCenter", plot.TowerCF.Position)
	self:_updateSign(plot)

	table.insert(plot.Connections, player:GetAttributeChangedSignal("Cash"):Connect(function()
		self:_updateButtonColors(plot)
	end))
	table.insert(plot.Connections, player:GetAttributeChangedSignal("Vault"):Connect(function()
		self:_updateVaultLabels(plot)
	end))
	table.insert(plot.Connections, player:GetAttributeChangedSignal("Multiplier"):Connect(function()
		self:_refreshWorth(plot)
	end))

	self:_queueFullBuild(plot)
	if player.Character then
		self:TeleportHome(player)
	end
	Remotes.Notify:FireClient(player, { Text = "Welcome! Tower #" .. plot.Index .. " is yours. Step on the buttons (or open BUILD) to grow it!", Type = "success", Duration = 6 })
	sendUpdate(plot, { Type = "Reset" })
end

function TycoonService:_queueFullBuild(plot)
	local data = S.DataService:Get(plot.Owner)
	if not data then
		return
	end
	plot.Generation += 1
	plot.Queue = {}
	for _, item in TycoonItems.List do
		local owned = data.Purchased[item.Id] or (item.Kind == "Secret" and data.Secrets[item.SecretId])
		if owned and not plot.Built[item.Id] and not plot.Disabled[item.Id] then
			table.insert(plot.Queue, { Item = item, Generation = plot.Generation })
		end
	end
	if #plot.Queue == 0 then
		self:_afterBulkBuild(plot)
	end
	plot.PendingOffline = true
end

function TycoonService:_afterBulkBuild(plot)
	self:_recompute(plot)
	self:_refreshButtons(plot)
	self:_updateVaultLabels(plot)
	-- offline earnings (once, after the first full build)
	if plot.PendingOffline and plot.Owner then
		plot.PendingOffline = false
		local owner = plot.Owner
		local data = S.DataService:Get(owner)
		local oe = Config.OfflineEarnings
		if data and oe.Enabled and data.LastOnline > 0 and data.LastIncome > 0 and not plot.OfflinePaid then
			plot.OfflinePaid = true
			local away = math.min(os.time() - data.LastOnline, oe.MaxHours * 3600)
			if away > 60 then
				local amount = data.LastIncome * away * (oe.Percent + Config.RebirthPerk(data.Rebirths, "Offline")) * (S.MonetizationService:HasPass(owner, "OfflineBoost") and 2 or 1)
				S.DataService:AddVault(owner, amount)
				Remotes.Notify:FireClient(owner, { Text = "💤 While you were away (" .. Util.FormatTime(away) .. ") your tower made " .. Util.Money(amount) .. "! Collect it at the vault.", Type = "success", Duration = 10 })
			end
		end
	end
end

function TycoonService:_clearPlot(plot)
	plot.Generation += 1
	plot.Queue = {}
	plot.Items:ClearAllChildren()
	plot.Buttons:ClearAllChildren()
	plot.Rubble:ClearAllChildren()
	plot.Built = {}
	plot.Extra = {}
	plot.ButtonObjs = {}
	plot.SlotUsed = {}
	plot.Disabled = {}
	plot.RubbleModels = {}
	plot.ItemPos = {}
	plot.Worth = {}
	plot.Income = 0
	plot.VaultLabels = {}
	plot.Shielded = false
	plot.Shelter = nil
end

function TycoonService:_releaseOwner(player: Player)
	local plot = playerPlot[player]
	if not plot or plot.Owner ~= player then
		return
	end
	self:_clearPlot(plot)
	for _, conn in plot.Connections do
		conn:Disconnect()
	end
	plot.Connections = {}
	plot.Owner = nil
	plot.OfflinePaid = false
	playerPlot[player] = nil
	player:SetAttribute("Plot", nil)
	player:SetAttribute("PlotCenter", nil)
	self:_updateSign(plot)
end

function TycoonService:_onLeave(player: Player)
	local plot = playerPlot[player]
	if not plot then
		return
	end
	if plot.Owner == player then
		local partner = plot.Partner
		if partner then
			self:RemovePartner(plot, false)
		end
		self:_releaseOwner(player)
		-- give the partner their own tower back
		if partner and partner.Parent then
			Remotes.Notify:FireClient(partner, { Text = player.DisplayName .. " left, so your duo ended. Building your own tower...", Type = "info", Duration = 6 })
			task.defer(function()
				local data = S.DataService:Get(partner)
				if data then
					self:_assign(partner, data)
				end
			end)
		end
	elseif plot.Partner == player then
		self:RemovePartner(plot, false)
	end
end

---------------------------------------------------------------------------
-- Duo membership (called by DuoService)
---------------------------------------------------------------------------
function TycoonService:AddPartner(host: Player, partner: Player): boolean
	local plot = playerPlot[host]
	if not plot or plot.Owner ~= host or plot.Partner then
		return false
	end
	if playerPlot[partner] then
		if playerPlot[partner].Owner == partner then
			if playerPlot[partner].Partner then
				return false
			end
			self:_releaseOwner(partner)
		else
			return false
		end
	end
	plot.Partner = partner
	playerPlot[partner] = plot
	partner:SetAttribute("DuoHost", host.UserId)
	host:SetAttribute("DuoPartner", partner.UserId)
	partner:SetAttribute("Plot", plot.Index)
	partner:SetAttribute("PlotCenter", plot.TowerCF.Position)
	self:_updateSign(plot)
	S.DataService:Sync(host)
	self:_recompute(plot)
	sendUpdate(plot, { Type = "Reset" })
	if S.QuestService then
		S.QuestService:Refresh(partner) -- tower quests now follow the host's tower
	end
	if partner.Character then
		partner.Character:PivotTo(plot.SpawnCFrame * CFrame.new(4, 0, 0))
	end
	return true
end

-- removes the partner; reassign = give them their own tower again
function TycoonService:RemovePartner(plot, reassign: boolean)
	local partner = plot.Partner
	if not partner then
		return
	end
	plot.Partner = nil
	playerPlot[partner] = nil
	partner:SetAttribute("DuoHost", nil)
	partner:SetAttribute("Plot", nil)
	partner:SetAttribute("PlotCenter", nil)
	partner:SetAttribute("Income", 0)
	if plot.Owner then
		plot.Owner:SetAttribute("DuoPartner", nil)
		S.DataService:Sync(plot.Owner)
	end
	self:_updateSign(plot)
	if partner.Parent then
		S.DataService:Sync(partner)
		Remotes.TycoonUpdate:FireClient(partner, { Type = "Reset" })
		if reassign then
			local data = S.DataService:Get(partner)
			if data then
				self:_assign(partner, data)
			end
		end
		if S.QuestService then
			S.QuestService:Refresh(partner)
		end
	end
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
function TycoonService:_ownerName(plot): string?
	return plot.Owner and plot.Owner.DisplayName
end

function TycoonService:_buildItem(plot, item, withEffects: boolean)
	if plot.Built[item.Id] or plot.Disabled[item.Id] then
		return
	end
	local model, extra = TycoonBuilder.BuildItem(plot, item, self:_ownerName(plot))
	plot.Built[item.Id] = model
	plot.Extra[item.Id] = extra
	plot.ItemPos[item.Id] = TycoonBuilder.ItemWorldPos(plot, item)
	model:SetAttribute("Plot", plot.Index)
	model:SetAttribute("Floor", item.Floor)
	model:SetAttribute("ItemId", item.Id)

	local kind = item.Kind
	if kind == "Unlock" then
		if extra.VaultPad then
			table.insert(plot.VaultLabels, extra.VaultLabel)
			extra.VaultPad.Touched:Connect(function(hit)
				local player = BuildKit.PlayerFromHit(hit)
				if player and isMember(player, plot) and os.clock() - plot.LastPad > 1 and BuildKit.IsNear(player, extra.VaultPad) then
					plot.LastPad = os.clock()
					self:CollectVault(player)
				end
			end)
		end
		if extra.ElevatorPrompt then
			extra.ElevatorPrompt.Triggered:Connect(function(player)
				Remotes.ClientCommand:FireClient(player, "openfloors", plot.Index)
			end)
		end
	elseif kind == "Dropper" then
		model:SetAttribute("Interval", item.Interval)
		model:SetAttribute("Spout", extra.Spout)
		model:SetAttribute("BeltEnd", extra.BeltEnd)
		model:SetAttribute("BeltSpeed", TC.ConveyorSpeed)
		model:SetAttribute("Tier", item.Slot)
		model:SetAttribute("DropColor", (item.Theme.Primary :: Color3):Lerp(item.Theme.Accent, (item.Slot - 1) / 9))
		model:SetAttribute("DropMaterial", (item.Slot >= 6 and item.Theme.Drop or Enum.Material.SmoothPlastic).Name)
		CollectionService:AddTag(model, "Dropper")
	elseif kind == "Upgrader" then
		model:SetAttribute("BeltPos", extra.BeltPos)
		model:SetAttribute("Color", extra.Color)
		CollectionService:AddTag(model, "Upgrader")
	elseif kind == "Generator" then
		model:SetAttribute("PopPos", extra.PopPos)
		model:SetAttribute("Cycle", item.Cycle)
		CollectionService:AddTag(model, "Generator")
	elseif kind == "Special" then
		if item.Effect == "Shield" then
			plot.Shielded = true
		elseif item.Effect == "Bunker" then
			plot.Shelter = { CFrame = extra.ShelterCF, Size = extra.ShelterSize, Door = extra.Door }
		end
	end

	if withEffects then
		Remotes.VFX:FireAllClients("BuildIn", { Model = model, Position = plot.ItemPos[item.Id], Color = item.Theme and item.Theme.Accent or plot.Color })
	end
end

-- recompute income + per-model worth attributes
function TycoonService:_recompute(plot)
	if not plot.Owner then
		return
	end
	local data = S.DataService:Get(plot.Owner)
	if not data then
		return
	end
	local disabled = {}
	for id in plot.Disabled do
		disabled[id] = true
	end
	local fast = S.DataService:TeamHasPass(plot.Owner, "FastDroppers")
	local income, worth = TycoonItems.ComputeIncome(data.Purchased, disabled, data.Secrets, fast)
	plot.Income = income
	plot.Worth = worth
	self:_refreshWorth(plot)
end

function TycoonService:_refreshWorth(plot)
	if not plot.Owner then
		return
	end
	local mult = S.DataService:GetMultiplier(plot.Owner)
	local fast = S.DataService:TeamHasPass(plot.Owner, "FastDroppers")
	for id, model in plot.Built do
		local worth = plot.Worth[id]
		if worth then
			model:SetAttribute("Worth", worth * mult)
			if model:GetAttribute("Interval") then
				model:SetAttribute("Interval", TC.DropInterval / (fast and 2 or 1))
			end
		end
	end
end

-- called when passes change (Fast Droppers etc.)
function TycoonService:RefreshPlayer(player: Player)
	local plot = playerPlot[player]
	if plot then
		self:_recompute(plot)
		self:_updateVaultLabels(plot)
	end
end

-- what an item costs for this plot's owner (10% less with the Discount pass)
function TycoonService:GetPrice(plot, item): number
	if plot.Owner and S.DataService:TeamHasPass(plot.Owner, "Discount") then
		return math.max(1, math.floor(item.Cost * 0.9))
	end
	return item.Cost
end

function TycoonService:_freeSlot(plot, floor: number): number?
	plot.SlotUsed[floor] = plot.SlotUsed[floor] or {}
	for slot = 1, TC.ButtonSlotsPerFloor do
		if not plot.SlotUsed[floor][slot] then
			return slot
		end
	end
	return nil
end

function TycoonService:_removeButton(plot, id: string)
	local button = plot.ButtonObjs[id]
	if button then
		plot.ButtonObjs[id] = nil
		if button.Slot and plot.SlotUsed[button.Floor] then
			plot.SlotUsed[button.Floor][button.Slot] = nil
		end
		button.Model:Destroy()
	end
end

function TycoonService:_refreshButtons(plot)
	local owner = plot.Owner
	if not owner then
		return
	end
	local data = S.DataService:Get(owner)
	if not data then
		return
	end
	for id in plot.ButtonObjs do
		if data.Purchased[id] then
			self:_removeButton(plot, id)
		end
	end
	-- only the next few upgrades of each floor get a pad (the list is in buying order)
	local shown: { [number]: number } = {}
	for _, button in plot.ButtonObjs do
		shown[button.Floor] = (shown[button.Floor] or 0) + 1
	end
	for _, item in TycoonItems.List do
		if item.ButtonFloor and not plot.ButtonObjs[item.Id] and TycoonItems.IsAvailable(item, data.Purchased) then
			local floor = item.ButtonFloor
			local lane = TycoonItems.ButtonLane(item) ~= nil
			local slot = not lane and self:_freeSlot(plot, floor) or nil
			if (lane or slot) and (shown[floor] or 0) < TC.MaxVisibleButtons then
				shown[floor] = (shown[floor] or 0) + 1
				local button = TycoonBuilder.BuildButton(plot, item, slot, self:GetPrice(plot, item))
				if slot then
					plot.SlotUsed[floor][slot] = item.Id
				end
				plot.ButtonObjs[item.Id] = button
				local lastFail = 0
				local busy = false
				button.Pad.Touched:Connect(function(hit)
					if busy then
						return
					end
					local player = BuildKit.PlayerFromHit(hit)
					if not player or not isMember(player, plot) or not BuildKit.IsNear(player, button.Pad) then
						return
					end
					busy = true
					local ok, reason = self:TryPurchase(player, item.Id)
					if not ok and os.clock() - lastFail > 2 then
						lastFail = os.clock()
						Remotes.Notify:FireClient(player, { Text = reason, Type = "error" })
						Remotes.VFX:FireClient(player, "Error", {})
					end
					task.wait(0.4)
					busy = false
				end)
			end
		end
	end
	self:_updateButtonColors(plot)
end

function TycoonService:_updateButtonColors(plot)
	local owner = plot.Owner
	if not owner then
		return
	end
	local cash = owner:GetAttribute("Cash") or 0
	for id, button in plot.ButtonObjs do
		local item = TycoonItems.ById[id]
		if item and button.Pad.Parent then
			local affordable = cash >= self:GetPrice(plot, item)
			button.Pad.Color = affordable and GREEN or RED
			button.Pillar.Color = affordable and GREEN or RED
			button.Label.TextColor3 = affordable and Color3.fromRGB(180, 255, 190) or Color3.fromRGB(255, 190, 190)
		end
	end
end

function TycoonService:_updateVaultLabels(plot)
	local owner = plot.Owner
	if not owner then
		return
	end
	local text
	if S.DataService:TeamHasPass(owner, "AutoCollect") then
		text = "🧲 AUTO COLLECT ON"
	else
		text = "🏦 VAULT: " .. Util.Money(owner:GetAttribute("Vault") or 0) .. "\nStep here to collect"
	end
	for _, label in plot.VaultLabels do
		label.Text = text
	end
end

function TycoonService:CollectVault(player: Player)
	local amount = S.DataService:CollectVault(player)
	if amount > 0 then
		quest(player, "Collect", 1)
		Remotes.VFX:FireClient(player, "CashBurst", { Amount = amount })
		Remotes.Notify:FireClient(player, { Text = "Collected " .. Util.Money(amount) .. "!", Type = "success" })
	end
end

function TycoonService:TryPurchase(player: Player, itemId: string, silent: boolean?): (boolean, string)
	local plot = playerPlot[player]
	local item = TycoonItems.ById[itemId]
	if not plot or not plot.Owner or not item or item.Kind == "Secret" then
		return false, "Can't buy that right now."
	end
	if #plot.Queue > 0 then
		return false, "Your tower is still loading..."
	end
	local data = S.DataService:Get(plot.Owner)
	if not data then
		return false, "Data still loading..."
	end
	if data.Purchased[itemId] then
		return false, "You already own this!"
	end
	if not TycoonItems.IsAvailable(item, data.Purchased) then
		return false, "Buy the previous upgrades first!"
	end
	local price = item.Cost == 0 and 0 or self:GetPrice(plot, item)
	if data.Cash < price then
		return false, "You need " .. Util.Money(price - data.Cash) .. " more!"
	end
	S.DataService:SpendCash(plot.Owner, price)
	data.Purchased[itemId] = true
	if S.ProgressService then
		S.ProgressService:Record(plot.Owner, "Upgrade")
	end

	local button = plot.ButtonObjs[itemId]
	if button and not silent then
		Remotes.VFX:FireAllClients("ButtonPop", { Position = button.Pad.Position, Color = GREEN })
	end
	self:_removeButton(plot, itemId)
	self:_buildItem(plot, item, not silent)
	if not silent then
		self:_refreshButtons(plot)
		self:_recompute(plot)
		Remotes.VFX:FireClient(player, "PurchaseSound", {})
		if item.Kind == "Unlock" then
			Remotes.Announce:FireAllClients({ Title = "🏢 " .. player.DisplayName .. " unlocked " .. item.Name .. "!", Text = "", Color = item.Theme.Accent })
		elseif item.Kind == "Trophy" then
			Remotes.VFX:FireClient(player, "Confetti", {})
		end
	end
	sendUpdate(plot, { Type = "Bought", Id = itemId })
	quest(player, "Buy", 1)
	if (item.Kind == "Unlock" or itemId == "Roof_1") and S.QuestService then
		S.QuestService:FloorUnlocked(plot)
	end
	return true, "Purchased " .. item.Name .. "!"
end

-- buys up to `max` of the cheapest affordable upgrades (quietly); returns their ids
function TycoonService:_buyCheapest(player: Player, plot, data, max: number, floor: number?): { string }
	local bought = {}
	for _ = 1, max do
		local best
		for _, item in TycoonItems.List do
			if item.Kind ~= "Secret" and (floor == nil or item.Floor == floor) and item.Cost <= data.Cash and TycoonItems.IsAvailable(item, data.Purchased) then
				if not best or item.Cost < best.Cost then
					best = item
				end
			end
		end
		if not best or not self:TryPurchase(player, best.Id, true) then
			break
		end
		table.insert(bought, best.Id)
	end
	return bought
end

-- Buy every affordable upgrade (cheapest first). floor = only that floor
function TycoonService:BuyAll(player: Player, floor: number?)
	local plot = playerPlot[player]
	if not plot or not plot.Owner then
		return
	end
	local data = S.DataService:Get(plot.Owner)
	if not data then
		return
	end
	local spent = data.Cash
	local count = #self:_buyCheapest(player, plot, data, 80, floor)
	spent -= data.Cash
	if count > 0 then
		self:_refreshButtons(plot)
		self:_recompute(plot)
		Remotes.VFX:FireAllClients("Purchase", { Position = plot.TowerCF.Position + Vector3.new(0, 10, 0), Color = plot.Color, Big = true })
		Remotes.Notify:FireClient(player, { Text = "Bought " .. count .. " upgrades for " .. Util.Money(spent) .. "!", Type = "success" })
	else
		Remotes.Notify:FireClient(player, { Text = "Nothing affordable right now.", Type = "info" })
	end
end

-- Admin helper: give every item
function TycoonService:UnlockAll(player: Player, upToFloor: number?)
	local plot = playerPlot[player]
	if not plot or not plot.Owner then
		return
	end
	local data = S.DataService:Get(plot.Owner)
	if not data then
		return
	end
	for _, item in TycoonItems.List do
		if item.Kind ~= "Secret" and (not upToFloor or item.Floor <= upToFloor) then
			data.Purchased[item.Id] = true
		end
	end
	self:Rebuild(plot.Owner)
	if S.QuestService then
		S.QuestService:FloorUnlocked(plot)
	end
end

-- Rebuild the whole tower from data (after reset / rebirth)
function TycoonService:Rebuild(player: Player)
	local plot = playerPlot[player]
	if not plot or not plot.Owner then
		return
	end
	self:_clearPlot(plot)
	self:_queueFullBuild(plot)
	plot.PendingOffline = false
	sendUpdate(plot, { Type = "Reset" })
end

function TycoonService:Rebirth(player: Player, free: boolean?)
	local plot = playerPlot[player]
	if plot and plot.Owner ~= player then
		Remotes.Notify:FireClient(player, { Text = "Only the tower owner can rebirth!", Type = "error" })
		return
	end
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local cost = TycoonItems.GetRebirthCost(data.Rebirths)
	if not free and data.Cash < cost then
		Remotes.Notify:FireClient(player, { Text = "You need " .. Util.Money(cost) .. " to rebirth!", Type = "error" })
		return
	end
	local rankBefore = Config.RebirthRank(data.Rebirths)
	data.Rebirths += 1
	if S.ProgressService then
		S.ProgressService:Record(player, "Rebirth")
	end
	data.Cash = Config.StartingCash + Config.RebirthPerk(data.Rebirths, "Start")
	data.Vault = 0
	data.Purchased = { F1_1 = true }
	S.DataService:Sync(player)
	self:Rebuild(player)
	if S.QuestService then
		S.QuestService:Refresh(player)
		if plot and plot.Partner then
			S.QuestService:Refresh(plot.Partner) -- the tower they build was reset too
		end
	end

	if S.MonetizationService then
		S.MonetizationService:RefreshCharacter(player) -- new rank tag and speed
	end
	local rankIndex, rank = Config.RebirthRank(data.Rebirths)
	if rank and rankIndex ~= rankBefore then
		Remotes.Notify:FireClient(player, { Text = rank.Icon .. " New rank: " .. rank.Name .. "! " .. rank.Text, Type = "success", Duration = 8 })
	end
	Remotes.VFX:FireClient(player, "Rebirth", { Rebirths = data.Rebirths })
	if plot then
		Remotes.VFX:FireAllClients("Shockwave", { Position = plot.TowerCF.Position + Vector3.new(0, 2, 0), Color = Color3.fromRGB(255, 200, 40), Size = 160 })
	end
	Remotes.Announce:FireAllClients({
		Title = "🔄 " .. player.DisplayName .. " REBIRTHED!",
		Text = "Now at Rebirth " .. data.Rebirths .. " (" .. (1 + data.Rebirths * Config.Rebirth.MultiplierPerRebirth) .. "x cash)",
		Color = Color3.fromRGB(255, 200, 40),
	})
	task.spawn(S.DataService.Save, S.DataService, player)
end

-- a secret was found: build its relic in the finder's tower
function TycoonService:OnSecretFound(player: Player, secretId: string)
	local plot = playerPlot[player]
	local item = TycoonItems.ById["Secret_" .. secretId]
	if plot and plot.Owner == player and item then
		self:_buildItem(plot, item, true)
		self:_recompute(plot)
	end
	if plot then
		sendUpdate(plot, { Type = "Secret", Id = secretId })
	end
end

---------------------------------------------------------------------------
-- Disasters: knockouts / repairs / shelters
---------------------------------------------------------------------------
function TycoonService:IsShielded(plot): boolean
	return plot.Owner ~= nil and plot.Shielded == true
end

function TycoonService:KnockOut(plot, id: string, seconds: number): boolean
	local item = TycoonItems.ById[id]
	local model = plot.Built[id]
	if not item or not model or plot.Disabled[id] or not canKnockOut(item) then
		return false
	end
	local pos = plot.ItemPos[id] or model:GetPivot().Position
	model:Destroy()
	plot.Built[id] = nil
	plot.Extra[id] = nil
	plot.Disabled[id] = os.time() + seconds
	plot.RubbleModels[id] = TycoonBuilder.BuildRubble(plot, pos - Vector3.new(0, 2.5, 0), id)
	-- a wrecked dropper takes its Mk II ring with it
	if item.Kind == "Dropper" then
		for _, other in TycoonItems.ByFloor[item.Floor] do
			if other.Kind == "Mk2" and other.Slot == item.Slot and plot.Built[other.Id] then
				plot.Built[other.Id]:Destroy()
				plot.Built[other.Id] = nil
				plot.Disabled[other.Id] = os.time() + seconds
			end
		end
	end
	sendUpdate(plot, { Type = "Disabled", Id = id, Seconds = seconds })
	return true
end

function TycoonService:_repair(plot, id: string)
	plot.Disabled[id] = nil
	local rubble = plot.RubbleModels[id]
	if rubble then
		rubble:Destroy()
		plot.RubbleModels[id] = nil
	end
	local item = TycoonItems.ById[id]
	local data = plot.Owner and S.DataService:Get(plot.Owner)
	if item and data and data.Purchased[id] then
		self:_buildItem(plot, item, true)
	end
	sendUpdate(plot, { Type = "Repaired", Id = id })
end

function TycoonService:RepairAll(player: Player): number
	local plot = playerPlot[player]
	if not plot then
		return 0
	end
	local count = 0
	for id in plot.Disabled do
		self:_repair(plot, id)
		count += 1
	end
	if count > 0 then
		self:_recompute(plot)
	end
	return count
end

function TycoonService:WreckedCount(plot): number
	local n = 0
	for _ in plot.Disabled do
		n += 1
	end
	return n
end

-- wreck a share of the tower (nukes)
function TycoonService:KnockOutFraction(plot, fraction: number, seconds: number): number
	local candidates = {}
	for id in plot.Built do
		local item = TycoonItems.ById[id]
		if item and canKnockOut(item) and not plot.Disabled[id] then
			table.insert(candidates, id)
		end
	end
	local count = math.floor(#candidates * fraction)
	local wrecked = 0
	for _ = 1, count do
		if #candidates == 0 then
			break
		end
		local id = table.remove(candidates, math.random(1, #candidates))
		if self:KnockOut(plot, id, seconds) then
			wrecked += 1
		end
	end
	if wrecked > 0 then
		self:_recompute(plot)
	end
	return wrecked
end

-- wreck items near a world position (meteors, tornadoes). horizontal = ignore height
function TycoonService:KnockOutNear(plot, position: Vector3, radius: number, maxCount: number, seconds: number, horizontal: boolean?): number
	local hits = {}
	for id, pos in plot.ItemPos do
		if plot.Built[id] and not plot.Disabled[id] then
			local item = TycoonItems.ById[id]
			if item and canKnockOut(item) then
				local delta = pos - position
				if horizontal then
					delta = Vector3.new(delta.X, 0, delta.Z)
				end
				local d = delta.Magnitude
				if d <= radius then
					table.insert(hits, { Id = id, D = d })
				end
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.D < b.D
	end)
	local wrecked = 0
	for i = 1, math.min(maxCount, #hits) do
		if self:KnockOut(plot, hits[i].Id, seconds) then
			wrecked += 1
		end
	end
	if wrecked > 0 then
		self:_recompute(plot)
	end
	return wrecked
end

-- which plot (if any) contains this world position (x/z)
function TycoonService:PlotAt(position: Vector3)
	for _, plot in plots do
		local localPos = plot.CFrame:PointToObjectSpace(position)
		if math.abs(localPos.X) <= 60 and math.abs(localPos.Z) <= 60 then
			return plot
		end
	end
	return nil
end

-- shelter info for disasters: bunkers + shield domes
function TycoonService:GetShelters()
	local boxes, spheres, doors = {}, {}, {}
	for _, plot in plots do
		if plot.Owner then
			if plot.Shelter then
				table.insert(boxes, { CFrame = plot.Shelter.CFrame, Size = plot.Shelter.Size })
				table.insert(doors, plot.Shelter.Door)
			end
			if plot.Shielded then
				table.insert(spheres, { Center = plot.ShieldCenter, Radius = plot.ShieldRadius })
				table.insert(doors, (plot.SpawnCFrame).Position)
			end
		end
	end
	return boxes, spheres, doors
end

function TycoonService:IsInsideShield(position: Vector3)
	for _, plot in plots do
		if plot.Owner and plot.Shielded and (position - plot.ShieldCenter).Magnitude <= plot.ShieldRadius then
			return plot
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Spawning / teleporting
---------------------------------------------------------------------------
local function streamAround(player: Player, position: Vector3)
	pcall(function()
		player:RequestStreamAroundAsync(position, 3)
	end)
end

function TycoonService:GetSpawnCFrame(player: Player): CFrame
	local stage = player:GetAttribute("ObbyStage") or 0
	if stage > 0 and S.ObbyService then
		local cf = S.ObbyService:GetCheckpointCFrame(stage)
		if cf then
			return cf
		end
	end
	local plot = playerPlot[player]
	if plot then
		return plot.SpawnCFrame
	end
	return CFrame.new(0, 5, 0)
end

-- streams the destination in first (non-blocking for the caller)
function TycoonService:TeleportHome(player: Player)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		local cf = self:GetSpawnCFrame(player)
		task.spawn(function()
			streamAround(player, cf.Position)
			if player.Character == character then
				character:PivotTo(cf)
			end
		end)
	end
end

function TycoonService:TeleportToFloor(player: Player, plotIndex: any, floor: any)
	if player:GetAttribute("InMinigame") then
		return
	end
	local plot = plots[tonumber(plotIndex) or -1]
	floor = tonumber(floor)
	if not plot or not floor or floor < 1 or floor > FLOORS + 1 then
		return
	end
	if not self:IsFloorUnlocked(plot, floor) then
		Remotes.Notify:FireClient(player, { Text = "That floor isn't built yet!", Type = "error" })
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local cf = TycoonBuilder.FloorCF(plot, floor) * CFrame.new(-28, 4, -28) * CFrame.Angles(0, math.pi, 0)
	if floor == FLOORS + 1 then
		cf = TycoonBuilder.FloorCF(plot, floor) * CFrame.new(0, 4, -20) * CFrame.Angles(0, math.pi, 0)
	end
	player:SetAttribute("ObbyStage", 0)
	Remotes.VFX:FireClient(player, "Flash", {})
	task.spawn(function()
		streamAround(player, cf.Position)
		if player.Character == character then
			character:PivotTo(cf)
		end
	end)
end

function TycoonService:_hookCharacter(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait()
		if player:GetAttribute("InMinigame") then
			return
		end
		local cf = self:GetSpawnCFrame(player)
		streamAround(player, cf.Position)
		character:PivotTo(cf)
	end)
end

return TycoonService
