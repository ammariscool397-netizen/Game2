--[[
	DataService - loads, saves and edits player data.
	Values the client needs are mirrored to Player attributes
	(Cash, Vault, Rebirths, TotalEarned, Multiplier, BoostEnd, LastDaily, ...)
	so UI can simply listen to GetAttributeChangedSignal.
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

local DataService = {}
DataService.PlayerLoaded = Signal.new() -- (player, data)
DataService.BeforeSave = Signal.new()

local S

local TEMPLATE = {
	Cash = Config.StartingCash,
	Vault = 0,
	TotalEarned = 0,
	Rebirths = 0,
	Purchased = {},
	Passes = {}, -- passes granted by admins / simulated in Studio
	RedeemedCodes = {},
	DailyStreak = 0,
	LastDaily = 0,
	BoostEnd = 0,
	LastObbyReward = 0,
	ObbyCompletions = 0,
	MinigameWins = 0,
	PlayTime = 0,
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
		earnedStore = DataStoreService:GetOrderedDataStore(Config.DataStoreName .. "_TotalEarned")
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

	-- autosave + boost / event expiry ticks
	task.spawn(function()
		while true do
			task.wait(Config.AutoSaveInterval)
			for _, player in Players:GetPlayers() do
				task.spawn(self.Save, self, player)
			end
		end
	end)
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
	end
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
	self.BeforeSave:Fire(player, data)
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
			(earnedStore :: OrderedDataStore):SetAsync(tostring(player.UserId), math.floor(math.min(data.TotalEarned, 2 ^ 52)))
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

function DataService:GetMultiplier(player: Player): number
	local data = profiles[player]
	if not data then
		return 1
	end
	local mult = 1 + data.Rebirths * Config.Rebirth.MultiplierPerRebirth
	if S.MonetizationService then
		if S.MonetizationService:HasPass(player, "DoubleCash") then
			mult *= 2
		end
		if S.MonetizationService:HasPass(player, "VIP") then
			mult *= 1.5
		end
	end
	if data.BoostEnd > os.time() then
		mult *= 2
	end
	mult *= workspace:GetAttribute("EventMultiplier") or 1
	return mult
end

function DataService:RefreshMultiplier(player: Player)
	player:SetAttribute("Multiplier", self:GetMultiplier(player))
end

-- Push data values to attributes + leaderstats
function DataService:Sync(player: Player)
	local data = profiles[player]
	if not data then
		return
	end
	player:SetAttribute("Cash", data.Cash)
	player:SetAttribute("Vault", data.Vault)
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("TotalEarned", data.TotalEarned)
	player:SetAttribute("BoostEnd", data.BoostEnd)
	player:SetAttribute("LastDaily", data.LastDaily)
	player:SetAttribute("DailyStreak", data.DailyStreak)
	player:SetAttribute("RebirthCost", Config.GetRebirthCost(data.Rebirths))
	player:SetAttribute("MusicVolume", data.Settings.MusicVolume)
	player:SetAttribute("SFX", data.Settings.SFX)
	self:RefreshMultiplier(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		(leaderstats :: any).Cash.Value = Util.Money(data.Cash)
		;(leaderstats :: any).Rebirths.Value = data.Rebirths
	end
end

-- Add cash. `earned` = counts toward TotalEarned (income), default true
function DataService:AddCash(player: Player, amount: number, earned: boolean?)
	local data = profiles[player]
	if not data then
		return
	end
	amount = math.floor(amount)
	data.Cash = math.max(0, data.Cash + amount)
	if earned ~= false and amount > 0 then
		data.TotalEarned += amount
	end
	self:Sync(player)
end

function DataService:SetCash(player: Player, amount: number)
	local data = profiles[player]
	if not data then
		return
	end
	data.Cash = math.max(0, math.floor(amount))
	self:Sync(player)
end

function DataService:SpendCash(player: Player, amount: number): boolean
	local data = profiles[player]
	if not data or data.Cash < amount then
		return false
	end
	data.Cash -= amount
	self:Sync(player)
	return true
end

function DataService:AddVault(player: Player, amount: number)
	local data = profiles[player]
	if not data then
		return
	end
	data.Vault += math.floor(amount)
	player:SetAttribute("Vault", data.Vault)
end

function DataService:AddBoost(player: Player, seconds: number)
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
