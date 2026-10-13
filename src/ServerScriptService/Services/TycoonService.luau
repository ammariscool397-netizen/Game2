--[[
	TycoonService - plots, purchasing, droppers, upgraders, collecting,
	rebirths and spawning players at their tycoon.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local TycoonItems = require(Shared.TycoonItems)
local BuildKit = require(script.Parent.BuildKit)
local TycoonBuilder = require(script.Parent.TycoonBuilder)

local TycoonService = {}
local S

local plots = {}
local playerPlot: { [Player]: any } = {}
local MAX_DROPS_PER_PLOT = 220

local PLOT_POSITIONS = {
	{ Vector3.new(-150, 0, -170), 1 },
	{ Vector3.new(0, 0, -170), 1 },
	{ Vector3.new(150, 0, -170), 1 },
	{ Vector3.new(-150, 0, 170), -1 },
	{ Vector3.new(0, 0, 170), -1 },
	{ Vector3.new(150, 0, 170), -1 },
}

local GREEN = Color3.fromRGB(60, 220, 100)
local RED = Color3.fromRGB(235, 70, 70)

---------------------------------------------------------------------------
function TycoonService:Init(services)
	S = services
	local folder = Instance.new("Folder")
	folder.Name = "Tycoons"
	folder.Parent = workspace

	for index = 1, math.min(Config.MaxPlots, #PLOT_POSITIONS) do
		local pos, dir = PLOT_POSITIONS[index][1], PLOT_POSITIONS[index][2]
		local cf = CFrame.lookAt(pos, pos + Vector3.new(0, 0, dir))
		local plot = TycoonBuilder.BuildPlot(index, cf, folder)
		plot.Owner = nil
		plot.Built = {}
		plot.ButtonObjs = {}
		plot.Droppers = {}
		plot.Connections = {}
		plot.PendingPop = 0
		plot.LastPadTouch = 0
		plots[index] = plot
		self:_wirePlot(plot)
	end

	S.DataService.PlayerLoaded:Connect(function(player, data)
		self:_assign(player, data)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_release(player)
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
end

function TycoonService:Start()
	-- dropper loop
	task.spawn(function()
		while true do
			local now = os.clock()
			for _, plot in plots do
				local owner = plot.Owner
				if owner then
					local fast = S.MonetizationService and S.MonetizationService:HasPass(owner, "FastDroppers")
					local count = #plot.Drops:GetChildren()
					for _, dropper in plot.Droppers do
						if now >= dropper.Next then
							dropper.Next = now + dropper.Item.Interval / (fast and 2 or 1)
							if count < MAX_DROPS_PER_PLOT then
								count += 1
								self:_spawnDrop(plot, dropper)
							end
						end
					end
				end
			end
			task.wait(0.1)
		end
	end)

	-- batched "+$123" popups at the collector
	task.spawn(function()
		while true do
			task.wait(0.6)
			for _, plot in plots do
				if plot.Owner and plot.PendingPop > 0 then
					Remotes.VFX:FireClient(plot.Owner, "CashPop", {
						Position = plot.Collector.Position + Vector3.new(0, 4, 0),
						Amount = plot.PendingPop,
						Vault = not S.MonetizationService:HasPass(plot.Owner, "AutoCollect"),
					})
					plot.PendingPop = 0
				end
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Wiring (done once per plot)
---------------------------------------------------------------------------
function TycoonService:_wirePlot(plot)
	plot.Collector.Touched:Connect(function(hit)
		if hit.Parent ~= plot.Drops then
			return
		end
		local value = hit:GetAttribute("Value")
		if not value then
			return
		end
		hit:SetAttribute("Value", nil)
		hit:Destroy()
		local owner = plot.Owner
		if not owner then
			return
		end
		local amount = value * S.DataService:GetMultiplier(owner)
		if S.MonetizationService:HasPass(owner, "AutoCollect") then
			S.DataService:AddCash(owner, amount)
		else
			S.DataService:AddVault(owner, amount)
		end
		plot.PendingPop += amount
	end)

	plot.CollectPad.Touched:Connect(function(hit)
		local player = BuildKit.PlayerFromHit(hit)
		if not player or player ~= plot.Owner then
			return
		end
		if os.clock() - plot.LastPadTouch < 1 then
			return
		end
		plot.LastPadTouch = os.clock()
		self:CollectVault(player)
	end)
end

function TycoonService:CollectVault(player: Player)
	local data = S.DataService:Get(player)
	if not data or data.Vault <= 0 then
		return
	end
	local amount = data.Vault
	data.Vault = 0
	S.DataService:AddCash(player, amount)
	Remotes.VFX:FireClient(player, "CashBurst", { Amount = amount })
	Remotes.Notify:FireClient(player, { Text = "Collected " .. Util.Money(amount) .. "!", Type = "success" })
end

function TycoonService:_spawnDrop(plot, dropper)
	local drop = TycoonBuilder.MakeDrop(dropper.Item, dropper.Spout)
	drop:SetAttribute("Value", dropper.Item.Value)
	drop.Parent = plot.Drops
	pcall(function()
		drop:SetNetworkOwner(nil)
	end)
	Debris:AddItem(drop, Config.DropLifetime)
end

---------------------------------------------------------------------------
-- Plot assignment
---------------------------------------------------------------------------
function TycoonService:GetPlot(player: Player)
	return playerPlot[player]
end

function TycoonService:GetPlots()
	return plots
end

function TycoonService:_assign(player: Player, data)
	if playerPlot[player] then
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
		Remotes.Notify:FireClient(player, { Text = "All plots are taken! You can still play minigames and the obby.", Type = "error", Duration = 8 })
		return
	end
	plot.Owner = player
	playerPlot[player] = plot
	player:SetAttribute("Plot", plot.Index)
	for _, label in plot.SignLabels do
		label.Text = string.upper(player.DisplayName) .. "'S TYCOON"
	end

	for _, item in TycoonItems.List do
		if data.Purchased[item.Id] then
			self:_buildItem(plot, item, false)
		end
	end
	self:_refreshButtons(plot)

	table.insert(plot.Connections, player:GetAttributeChangedSignal("Cash"):Connect(function()
		self:_updateButtonColors(plot)
	end))
	table.insert(plot.Connections, player:GetAttributeChangedSignal("Vault"):Connect(function()
		self:_updateVaultLabel(plot)
	end))
	self:_updateVaultLabel(plot)

	if player.Character then
		self:TeleportHome(player)
	end
	Remotes.Notify:FireClient(player, { Text = "Welcome! Plot #" .. plot.Index .. " is yours. Step on the buttons to build!", Type = "success", Duration = 6 })
end

function TycoonService:_release(player: Player)
	local plot = playerPlot[player]
	if not plot then
		return
	end
	playerPlot[player] = nil
	self:_clearPlot(plot)
	for _, conn in plot.Connections do
		conn:Disconnect()
	end
	plot.Connections = {}
	plot.Owner = nil
	for _, label in plot.SignLabels do
		label.Text = "EMPTY PLOT"
	end
	plot.VaultLabel.Text = "🏦 VAULT: $0\nStep here to collect"
end

function TycoonService:_clearPlot(plot)
	plot.Items:ClearAllChildren()
	plot.Buttons:ClearAllChildren()
	plot.Drops:ClearAllChildren()
	plot.Built = {}
	plot.ButtonObjs = {}
	plot.Droppers = {}
	plot.PendingPop = 0
end

function TycoonService:RefreshVaultLabel(player: Player)
	local plot = playerPlot[player]
	if plot then
		self:_updateVaultLabel(plot)
	end
end

function TycoonService:_updateVaultLabel(plot)
	local owner = plot.Owner
	if not owner then
		return
	end
	if S.MonetizationService:HasPass(owner, "AutoCollect") then
		plot.VaultLabel.Text = "🧲 AUTO COLLECT ON"
	else
		plot.VaultLabel.Text = "🏦 VAULT: " .. Util.Money(owner:GetAttribute("Vault") or 0) .. "\nStep here to collect"
	end
end

---------------------------------------------------------------------------
-- Items & buttons
---------------------------------------------------------------------------
function TycoonService:_buildItem(plot, item, withEffects: boolean)
	if plot.Built[item.Id] then
		return
	end
	local model, extra = TycoonBuilder.BuildItem(plot, item, plot.Owner and plot.Owner.DisplayName)
	plot.Built[item.Id] = model

	if item.Kind == "Dropper" then
		table.insert(plot.Droppers, { Item = item, Spout = extra.Spout, Next = 0 })
	elseif item.Kind == "Upgrader" and extra.Detector then
		local key = "U_" .. item.Id
		extra.Detector.Touched:Connect(function(hit)
			if hit.Parent ~= plot.Drops then
				return
			end
			local value = hit:GetAttribute("Value")
			if not value or hit:GetAttribute(key) then
				return
			end
			hit:SetAttribute(key, true)
			hit:SetAttribute("Value", value * item.Multiplier)
			hit.Color = item.Color
			hit.Material = Enum.Material.Neon
		end)
	elseif item.Kind == "SpeedPad" and extra.Pad then
		extra.Pad.Touched:Connect(function(hit)
			local player, humanoid = BuildKit.PlayerFromHit(hit)
			if not player or not humanoid or player:GetAttribute("SpeedBoosted") then
				return
			end
			player:SetAttribute("SpeedBoosted", true)
			local base = S.MonetizationService:GetBaseSpeed(player)
			humanoid.WalkSpeed = base * 2.2
			Remotes.VFX:FireClient(player, "SpeedLines", { Duration = 6 })
			task.delay(6, function()
				player:SetAttribute("SpeedBoosted", nil)
				if humanoid.Parent then
					humanoid.WalkSpeed = S.MonetizationService:GetBaseSpeed(player)
				end
			end)
		end)
	end

	if withEffects then
		Remotes.VFX:FireAllClients("BuildIn", { Model = model, Position = model:GetPivot().Position, Color = item.Color or plot.Color })
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
	for _, item in TycoonItems.List do
		local owned = data.Purchased[item.Id]
		local unlocked = item.Requires == nil or data.Purchased[item.Requires]
		if not owned and unlocked and not plot.ButtonObjs[item.Id] then
			local button = TycoonBuilder.BuildButton(plot, item)
			plot.ButtonObjs[item.Id] = button
			local lastFail = 0
			local busy = false
			button.Pad.Touched:Connect(function(hit)
				if busy then
					return
				end
				local player = BuildKit.PlayerFromHit(hit)
				if not player or player ~= plot.Owner then
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
			local affordable = cash >= item.Cost
			button.Pad.Color = affordable and GREEN or RED
			button.Label.TextColor3 = affordable and Color3.fromRGB(180, 255, 190) or Color3.fromRGB(255, 190, 190)
		end
	end
end

function TycoonService:TryPurchase(player: Player, itemId: string): (boolean, string)
	local plot = playerPlot[player]
	local data = S.DataService:Get(player)
	local item = TycoonItems.ById[itemId]
	if not plot or not data or not item then
		return false, "Can't buy that right now."
	end
	if data.Purchased[itemId] then
		return false, "You already own this!"
	end
	if item.Requires and not data.Purchased[item.Requires] then
		return false, "Buy the previous upgrade first!"
	end
	if data.Cash < item.Cost then
		return false, "You need " .. Util.Money(item.Cost - data.Cash) .. " more!"
	end
	S.DataService:SpendCash(player, item.Cost)
	data.Purchased[itemId] = true

	local button = plot.ButtonObjs[itemId]
	if button then
		plot.ButtonObjs[itemId] = nil
		Remotes.VFX:FireAllClients("ButtonPop", { Position = button.Pad.Position, Color = GREEN })
		button.Model:Destroy()
	end
	self:_buildItem(plot, item, true)
	self:_refreshButtons(plot)
	Remotes.Notify:FireClient(player, { Text = "Purchased " .. item.Name .. "!", Type = "success" })
	Remotes.VFX:FireClient(player, "PurchaseSound", {})
	return true, "ok"
end

-- Admin helper: give every item
function TycoonService:UnlockAll(player: Player)
	local plot = playerPlot[player]
	local data = S.DataService:Get(player)
	if not plot or not data then
		return
	end
	for _, item in TycoonItems.List do
		if not data.Purchased[item.Id] then
			data.Purchased[item.Id] = true
			local button = plot.ButtonObjs[item.Id]
			if button then
				button.Model:Destroy()
				plot.ButtonObjs[item.Id] = nil
			end
			self:_buildItem(plot, item, true)
		end
	end
end

-- Rebuild the whole plot from data (after reset / rebirth)
function TycoonService:Rebuild(player: Player)
	local plot = playerPlot[player]
	local data = S.DataService:Get(player)
	if not plot or not data then
		return
	end
	self:_clearPlot(plot)
	for _, item in TycoonItems.List do
		if data.Purchased[item.Id] then
			self:_buildItem(plot, item, false)
		end
	end
	self:_refreshButtons(plot)
	self:_updateVaultLabel(plot)
end

function TycoonService:Rebirth(player: Player, free: boolean?)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local cost = Config.GetRebirthCost(data.Rebirths)
	if not free and data.Cash < cost then
		Remotes.Notify:FireClient(player, { Text = "You need " .. Util.Money(cost) .. " to rebirth!", Type = "error" })
		return
	end
	data.Rebirths += 1
	data.Cash = Config.StartingCash
	data.Vault = 0
	data.Purchased = {}
	S.DataService:Sync(player)
	self:Rebuild(player)

	Remotes.VFX:FireClient(player, "Rebirth", { Rebirths = data.Rebirths })
	local plot = playerPlot[player]
	if plot then
		Remotes.VFX:FireAllClients("Shockwave", { Position = plot.CFrame.Position + Vector3.new(0, 2, 0), Color = Color3.fromRGB(255, 200, 40), Size = 140 })
	end
	Remotes.Announce:FireAllClients({
		Title = "🔄 " .. player.DisplayName .. " REBIRTHED!",
		Text = "Now at Rebirth " .. data.Rebirths .. " (" .. (1 + data.Rebirths * Config.Rebirth.MultiplierPerRebirth) .. "x cash)",
		Color = Color3.fromRGB(255, 200, 40),
	})
	task.spawn(S.DataService.Save, S.DataService, player)
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------
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

function TycoonService:TeleportHome(player: Player)
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		character:PivotTo(self:GetSpawnCFrame(player))
	end
end

function TycoonService:_hookCharacter(player: Player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait()
		if player:GetAttribute("InMinigame") then
			return
		end
		character:PivotTo(self:GetSpawnCFrame(player))
	end)
end

return TycoonService
