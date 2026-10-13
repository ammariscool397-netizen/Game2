--[[
	DataService - loads, saves and edits player data.

	Values the client needs are mirrored to Player attributes
	(Cash, Vault, Rebirths, TotalEarned, Multiplier, Income, BoostEnd, ...)
	so UI can simply listen to GetAttributeChangedSignal.

	DUO WALLETS: a duo partner spends and earns from the host's wallet.
	AddCash / SpendCash / AddVault automatically route to the "wallet owner"
	(the host), and the partner's Cash/Vault attributes mirror the host's.
	The partner's own saved data is untouched while they are in a duo.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Signal = require(Shared.Signal)
local Remotes = require(Shared.Remotes)
local TycoonItems = require(Shared.TycoonItems)

local DataService = {}
DataService.PlayerLoaded = Signal.new() -- (player, data)
DataService.BeforeSave = Signal.new() -- (player, data)

local S

local TEMPLATE = {
	Cash = Config.StartingCash,
	Vault = 0,
	TotalEarned = 0,
	Rebirths = 0,
	Purchased = { F1_1 = true },
	Passes = {}, -- passes granted by admins / simulated in Studio
	Secrets = {},
	RedeemedCodes = {},
	DailyStreak = 0,
	LastDaily = 0,
	BoostEnd = 0,
	LastObbyReward = 0,
	ObbyCompletions = 0,
	MinigameWins = 0,
	PlayTime = 0,
	LastOnline = 0,
	LastIncome = 0,
	Settings = { MusicVolume = Config.Music.DefaultVolume, SFX = true, LowGraphics = false },
}

local profiles: { [Player]: any } = {}
local canSave: { [Player]: boolean } = {}
local joinTime: { [Player]: number } = {}

local store: DataStore? = nil
local earnedStore: OrderedDataStore? = nil
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.DataStoreName)
		earnedStore = DataStoreService:GetOrderedDataStore(Config.DataStoreName .. "_TotalEarnedLog")
	end)
	if not ok then
		warn("[DataService] DataStores unavailable: " .. tostring(err))
	end
end

local function keyFor(player: Player)
	return "Player_" .. player.UserId
end

local function retry<T>(fn: () -> T, attempts: number?): (boolean, T | string)
	local lastErr
	for i = 1, attempts or 3 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		-- no point retrying when API access is disabled (Studio) or the place is unpublished
		local message = tostring(result)
		if message:find("StudioAccessToApisNotAllowed") or message:find("403") or message:find("publish") then
			break
		end
		task.wait(1 + i)
	end
	return false, tostring(lastErr)
end

-- Leaderboard values are stored as log10 so huge numbers still sort correctly
function DataService.EncodeEarned(n: number): number
	return math.floor(math.log10(math.max(n, 0) + 1) * 1e13)
end

function DataService.DecodeEarned(v: number): number
	return 10 ^ (v / 1e13) - 1
end

---------------------------------------------------------------------------
function DataService:Init(services)
	S = services
	workspace:SetAttribute("EventMultiplier", 1)
	workspace:SetAttribute("EventEnds", 0)
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		self:_onJoin(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_onLeave(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(self._onJoin, self, player)
	end

	game:BindToClose(function()
		local threads = {}
		for _, player in Players:GetPlayers() do
			table.insert(threads, task.spawn(function()
				self:Save(player)
			end))
		end
		local start = os.clock()
		while os.clock() - start < (RunService:IsStudio() and 3 or 25) do
			local busy = false
			for _, thread in threads do
				if coroutine.status(thread) ~= "dead" then
					busy = true
				end
			end
			if not busy then
				break
			end
			task.wait(0.1)
		end
	end)

	-- autosave
	task.spawn(function()
		while true do
			task.wait(Config.AutoSaveInterval)
			for _, player in Players:GetPlayers() do
				task.spawn(self.Save, self, player)
			end
		end
	end)
	-- boost / event expiry
	task.spawn(function()
		while true do
			task.wait(1)
			local ends = workspace:GetAttribute("EventEnds") or 0
			if (workspace:GetAttribute("EventMultiplier") or 1) ~= 1 and os.time() >= ends then
				workspace:SetAttribute("EventMultiplier", 1)
				Remotes.Announce:FireAllClients({ Title = "EVENT OVER", Text = "The cash multiplier event has ended.", Color = Color3.fromRGB(200, 200, 200) })
				for _, p in Players:GetPlayers() do
					self:RefreshMultiplier(p)
				end
			end
			for player, data in profiles do
				if data.BoostEnd > 0 and os.time() >= data.BoostEnd then
					data.BoostEnd = 0
					self:Sync(player)
					Remotes.Notify:FireClient(player, { Text = "Your 2x Boost has ended.", Type = "info" })
				end
			end
		end
	end)
end

function DataService:_onJoin(player: Player)
	if profiles[player] then
		return
	end
	joinTime[player] = os.time()

	-- ban check first
	if S.AdminService and S.AdminService.CheckBan then
		local banned = S.AdminService:CheckBan(player)
		if banned then
			return
		end
	end

	local data
	if store then
		local ok, result = retry(function()
			return (store :: DataStore):GetAsync(keyFor(player))
		end)
		if ok then
			canSave[player] = true
			data = result
		else
			canSave[player] = false
			warn("[DataService] Could not load data for " .. player.Name .. ": " .. tostring(result))
			task.delay(5, function()
				if player.Parent then
					Remotes.Notify:FireClient(player, {
						Text = RunService:IsStudio() and "Data not saving: enable Studio API access in Game Settings > Security." or "We couldn't load your data. Progress this session won't be saved. Try rejoining!",
						Type = "error",
						Duration = 10,
					})
				end
			end)
		end
	else
		canSave[player] = false
	end

	if not player.Parent then
		return
	end

	if type(data) ~= "table" then
		data = Util.DeepCopy(TEMPLATE)
	else
		Util.Reconcile(data, TEMPLATE)
		local fixed = Util.Sanitize(data, TEMPLATE)
		if fixed > 0 then
			warn("[DataService] Repaired " .. fixed .. " invalid numbers in " .. player.Name .. "'s data")
		end
	end
	-- drop purchases of items that no longer exist (old versions)
	for id in data.Purchased do
		if not TycoonItems.ById[id] then
			data.Purchased[id] = nil
		end
	end
	data.Purchased.F1_1 = true
	profiles[player] = data

	-- leaderstats
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Parent = leaderstats
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = leaderstats
	leaderstats.Parent = player

	self:Sync(player)
	player:SetAttribute("DataLoaded", true)
	self.PlayerLoaded:Fire(player, data)
end

function DataService:_onLeave(player: Player)
	if profiles[player] then
		self:Save(player)
	end
	profiles[player] = nil
	canSave[player] = nil
	joinTime[player] = nil
end

function DataService:Save(player: Player)
	local data = profiles[player]
	if not data or not canSave[player] or not store then
		return false
	end
	if joinTime[player] then
		data.PlayTime += os.time() - joinTime[player]
		joinTime[player] = os.time()
	end
	data.LastOnline = os.time()
	self.BeforeSave:Fire(player, data)
	-- NaN / inf can't be saved (the whole save would fail): repair them first
	local fixed = Util.Sanitize(data, TEMPLATE)
	if fixed > 0 then
		warn("[DataService] Repaired " .. fixed .. " invalid numbers before saving " .. player.Name)
	end
	local ok, err = retry(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function()
			return data
		end)
	end)
	if not ok then
		warn("[DataService] Save failed for " .. player.Name .. ": " .. tostring(err))
	end
	if earnedStore then
		pcall(function()
			(earnedStore :: OrderedDataStore):SetAsync(tostring(player.UserId), DataService.EncodeEarned(data.TotalEarned))
		end)
	end
	return ok
end

function DataService:GetEarnedStore()
	return earnedStore
end

function DataService:Get(player: Player)
	return profiles[player]
end

function DataService:IsLoaded(player: Player)
	return profiles[player] ~= nil
end

---------------------------------------------------------------------------
-- Duo wallet helpers
---------------------------------------------------------------------------
function DataService:GetWalletOwner(player: Player): Player
	local hostId = player:GetAttribute("DuoHost")
	if hostId then
		local host = Players:GetPlayerByUserId(hostId)
		if host and profiles[host] then
			return host
		end
	end
	return player
end

function DataService:GetPartner(host: Player): Player?
	local partnerId = host:GetAttribute("DuoPartner")
	if partnerId then
		local partner = Players:GetPlayerByUserId(partnerId)
		if partner and partner.Parent then
			return partner
		end
	end
	return nil
end

function DataService:GetWallet(player: Player)
	return profiles[self:GetWalletOwner(player)]
end

-- the host plus their partner (if any)
function DataService:GetTeam(player: Player): { Player }
	local host = self:GetWalletOwner(player)
	local team = { host }
	local partner = self:GetPartner(host)
	if partner then
		table.insert(team, partner)
	end
	return team
end

function DataService:TeamHasPass(player: Player, key: string): boolean
	if not S.MonetizationService then
		return false
	end
	for _, member in self:GetTeam(player) do
		if S.MonetizationService:HasPass(member, key) then
			return true
		end
	end
	return false
end

-- Global income multiplier of the wallet that `player` uses.
-- permanentOnly = the player's own rebirths + passes (no duo, boosts or events),
-- used for offline earnings
function DataService:GetMultiplier(player: Player, permanentOnly: boolean?): number
	if permanentOnly then
		local own = profiles[player]
		if not own then
			return 1
		end
		local mult = 1 + own.Rebirths * Config.Rebirth.MultiplierPerRebirth
		local monetization = S and S.MonetizationService
		if monetization and monetization:HasPass(player, "DoubleCash") then
			mult *= 2
		end
		if monetization and monetization:HasPass(player, "VIP") then
			mult *= 1.5
		end
		return mult
	end
	local host = self:GetWalletOwner(player)
	local data = profiles[host]
	if not data then
		return 1
	end
	local mult = 1 + data.Rebirths * Config.Rebirth.MultiplierPerRebirth
	if self:TeamHasPass(host, "DoubleCash") then
		mult *= 2
	end
	if self:TeamHasPass(host, "VIP") then
		mult *= 1.5
	end
	local boosted = false
	for _, member in self:GetTeam(host) do
		local memberData = profiles[member]
		if memberData and memberData.BoostEnd > os.time() then
			boosted = true
		end
	end
	if boosted then
		mult *= 2
	end
	local event = workspace:GetAttribute("EventMultiplier")
	if Util.IsFinite(event) and event > 0 then
		mult *= event
	end
	return mult
end

function DataService:RefreshMultiplier(player: Player)
	for _, member in self:GetTeam(player) do
		member:SetAttribute("Multiplier", self:GetMultiplier(member))
	end
end

local function syncWallet(target: Player, wallet)
	target:SetAttribute("Cash", wallet.Cash)
	target:SetAttribute("Vault", wallet.Vault)
	target:SetAttribute("TotalEarned", wallet.TotalEarned)
	target:SetAttribute("WalletRebirths", wallet.Rebirths)
	target:SetAttribute("RebirthCost", TycoonItems.GetRebirthCost(wallet.Rebirths))
	local leaderstats = target:FindFirstChild("leaderstats")
	if leaderstats then
		(leaderstats :: any).Cash.Value = Util.Money(wallet.Cash)
	end
end

-- Push data values to attributes + leaderstats (for the player and their duo team)
function DataService:Sync(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	-- personal values
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("BoostEnd", data.BoostEnd)
	player:SetAttribute("LastDaily", data.LastDaily)
	player:SetAttribute("DailyStreak", data.DailyStreak)
	player:SetAttribute("MusicVolume", data.Settings.MusicVolume)
	player:SetAttribute("SFX", data.Settings.SFX)
	local found = {}
	for id in data.Secrets do
		table.insert(found, id)
	end
	player:SetAttribute("SecretsFound", table.concat(found, ","))
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		(leaderstats :: any).Rebirths.Value = data.Rebirths
	end
	-- wallet values (host's for a duo partner)
	local host = self:GetWalletOwner(player)
	local wallet = profiles[host] or data
	for _, member in self:GetTeam(host) do
		syncWallet(member, wallet)
	end
	self:RefreshMultiplier(player)
end

-- Add cash to the player's wallet. `earned` = counts toward TotalEarned (income), default true
-- every wallet change goes through these; a bad number (NaN / inf) must never
-- reach the saved data, so it's refused here (and totals are capped)
local MAX_CASH = 1e300

local function capped(n: number): number
	return math.clamp(n, 0, MAX_CASH)
end

local function validAmount(amount: any, what: string): boolean
	if Util.IsFinite(amount) then
		return true
	end
	warn("[DataService] Ignored invalid " .. what .. " amount: " .. tostring(amount))
	return false
end

function DataService:AddCash(player: Player, amount: number, earned: boolean?)
	if not validAmount(amount, "cash") then
		return
	end
	local host = self:GetWalletOwner(player)
	local data = profiles[host]
	if not data then
		return
	end
	data.Cash = capped(data.Cash + amount)
	if earned ~= false and amount > 0 then
		data.TotalEarned = capped(data.TotalEarned + amount)
	end
	self:Sync(host)
end

function DataService:SetCash(player: Player, amount: number)
	if not validAmount(amount, "cash") then
		return
	end
	local host = self:GetWalletOwner(player)
	local data = profiles[host]
	if not data then
		return
	end
	data.Cash = capped(amount)
	self:Sync(host)
end

function DataService:SpendCash(player: Player, amount: number): boolean
	if not validAmount(amount, "spend") or amount < 0 then
		return false
	end
	local host = self:GetWalletOwner(player)
	local data = profiles[host]
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	self:Sync(host)
	return true
end

function DataService:AddVault(player: Player, amount: number)
	if not validAmount(amount, "vault") then
		return
	end
	local host = self:GetWalletOwner(player)
	local data = profiles[host]
	if not data then
		return
	end
	data.Vault = capped(data.Vault + amount)
	data.TotalEarned = capped(data.TotalEarned + amount)
	for _, member in self:GetTeam(host) do
		member:SetAttribute("Vault", data.Vault)
		member:SetAttribute("TotalEarned", data.TotalEarned)
	end
end

-- moves the vault into the wallet (TotalEarned was already counted)
function DataService:CollectVault(player: Player): number
	local host = self:GetWalletOwner(player)
	local data = profiles[host]
	if not data or data.Vault <= 0 then
		return 0
	end
	local amount = data.Vault
	data.Vault = 0
	data.Cash = capped(data.Cash + amount)
	self:Sync(host)
	return amount
end

function DataService:AddBoost(player: Player, seconds: number)
	if not validAmount(seconds, "boost") then
		return
	end
	local data = profiles[player]
	if not data then
		return
	end
	data.BoostEnd = math.max(data.BoostEnd, os.time()) + seconds
	self:Sync(player)
end

function DataService:ResetData(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	local fresh = Util.DeepCopy(TEMPLATE)
	fresh.Passes = data.Passes -- never take away paid stuff
	for k in data do
		data[k] = nil
	end
	for k, v in fresh do
		data[k] = v
	end
	self:Sync(player)
end

return DataService
