--[[
	StaffService - per-player admin permissions, glowing titles, and passes
	waiting for players who are offline.

	Everything is saved in one DataStore registry (shared by all servers, re-read
	every Config.Admin.StaffRefreshSeconds):
	  Perms[userId]   = { Name, Groups = { [groupId] = true }, By, Time }
	  Titles[userId]  = { Name, Text, Color = "#RRGGBB" | "rainbow", By, Time }
	  Pending[userId] = { { Key, From, Time } }   passes to hand over on the next join

	A player with ticked permission groups gets the player attribute "AdminPerms"
	("Moderation,Disasters"); AdminService lets them run those groups' commands.
	A title is a glowing billboard above the head, also shown in chat.
]]
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)

local AC = Config.Admin

local StaffService = {}
local S

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(AC.StaffDataStore)
end)

local registry: { Perms: { [string]: any }, Titles: { [string]: any }, Pending: { [string]: any } } = { Perms = {}, Titles = {}, Pending = {} }
local loaded = false

local groupById: { [string]: any } = {}
for _, group in AC.Permissions do
	groupById[group.Id] = group
end
StaffService.Groups = groupById

local colorByName: { [string]: string } = {}
for _, entry in AC.TitleColors do
	colorByName[entry.Name:lower()] = entry.Hex
end

---------------------------------------------------------------------------
-- Saved registry
---------------------------------------------------------------------------
local function normalize(reg: any)
	reg.Perms = reg.Perms or {}
	reg.Titles = reg.Titles or {}
	reg.Pending = reg.Pending or {}
	return reg
end

-- applies `mutate` to the saved registry (atomically across servers) and caches the result
function StaffService:_commit(mutate: (any) -> ()): boolean
	local dataStore = store
	if dataStore then
		local ok, result = pcall(function()
			return dataStore:UpdateAsync("Registry", function(old)
				local reg = normalize(type(old) == "table" and old or {})
				mutate(reg)
				return reg
			end)
		end)
		if ok and type(result) == "table" then
			registry = normalize(result)
			return true
		end
		warn("[Staff] could not save the registry: " .. tostring(result))
	end
	mutate(registry)
	return false
end

function StaffService:Refresh()
	local dataStore = store
	if not dataStore then
		return
	end
	local ok, result = pcall(function()
		return dataStore:GetAsync("Registry")
	end)
	if ok and type(result) == "table" then
		registry = normalize(result)
		for _, player in Players:GetPlayers() do
			self:Apply(player)
		end
	end
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
function StaffService:GetGroups(userId: number): { [string]: boolean }
	local entry = registry.Perms[tostring(userId)]
	return entry and entry.Groups or {}
end

function StaffService:GetTitle(userId: number)
	return registry.Titles[tostring(userId)]
end

-- everyone with permissions or a title (for the admin panel)
function StaffService:GetOverview()
	local seen, list = {}, {}
	local function add(key: string, name: string)
		if seen[key] then
			return
		end
		seen[key] = true
		local groups = {}
		for id in (registry.Perms[key] and registry.Perms[key].Groups or {}) do
			table.insert(groups, id)
		end
		table.sort(groups)
		local title = registry.Titles[key]
		table.insert(list, {
			UserId = tonumber(key) or 0,
			Name = name,
			Groups = groups,
			Title = title and { Text = title.Text, Color = title.Color } or nil,
		})
	end
	for key, entry in registry.Perms do
		add(key, entry.Name)
	end
	for key, entry in registry.Titles do
		add(key, entry.Name)
	end
	table.sort(list, function(a, b)
		return a.Name:lower() < b.Name:lower()
	end)
	return list
end

-- the saved state of one user (online or not)
function StaffService:GetInfo(userId: number, name: string)
	local groups = {}
	for id in self:GetGroups(userId) do
		groups[id] = true
	end
	local title = self:GetTitle(userId)
	local online = Players:GetPlayerByUserId(userId)
	local passes = {}
	if online then
		for key in Config.GamePasses do
			if online:GetAttribute("Pass_" .. key) then
				passes[key] = true
			end
		end
	end
	local pending = {}
	for _, entry in registry.Pending[tostring(userId)] or {} do
		table.insert(pending, entry.Key)
	end
	return {
		UserId = userId,
		Name = name,
		Online = online ~= nil,
		Groups = groups,
		Title = title and { Text = title.Text, Color = title.Color } or nil,
		Passes = passes,
		Pending = pending,
	}
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------
function StaffService:SetGroup(userId: number, name: string, groupId: string, enabled: boolean, by: string): boolean
	if not groupById[groupId] then
		return false
	end
	local key = tostring(userId)
	self:_commit(function(reg)
		local entry = reg.Perms[key] or { Groups = {} }
		entry.Name, entry.By, entry.Time = name, by, os.time()
		entry.Groups[groupId] = enabled and true or nil
		if next(entry.Groups) == nil then
			reg.Perms[key] = nil
		else
			reg.Perms[key] = entry
		end
	end)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		self:Apply(player)
	end
	return true
end

function StaffService:ClearGroups(userId: number)
	self:_commit(function(reg)
		reg.Perms[tostring(userId)] = nil
	end)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		self:Apply(player)
	end
end

-- "#RRGGBB", "rainbow", or a colour name from Config.Admin.TitleColors -> stored form, or nil
function StaffService:ParseColor(input: string?): string?
	if not input then
		return nil
	end
	local text = (input :: string):lower()
	if colorByName[text] then
		return colorByName[text]
	end
	if text == "rainbow" then
		return "rainbow"
	end
	local hex = text:match("^#?(%x%x%x%x%x%x)$")
	return hex and ("#" .. hex:upper()) or nil
end

-- cleans the text of a title; nil if nothing is left
function StaffService:CleanTitle(input: string?): string?
	if type(input) ~= "string" then
		return nil
	end
	local text: string = (input :: string):gsub("[<>%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	local length = utf8.len(text)
	if not length or length == 0 then
		return nil
	end
	if length > AC.MaxTitleLength then
		text = text:sub(1, (utf8.offset(text, AC.MaxTitleLength + 1) or #text + 1) - 1)
	end
	return text
end

function StaffService:SetTitle(userId: number, name: string, text: string, color: string, by: string)
	self:_commit(function(reg)
		reg.Titles[tostring(userId)] = { Name = name, Text = text, Color = color, By = by, Time = os.time() }
	end)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		self:Apply(player)
	end
end

function StaffService:ClearTitle(userId: number): boolean
	local had = false
	self:_commit(function(reg)
		had = reg.Titles[tostring(userId)] ~= nil
		reg.Titles[tostring(userId)] = nil
	end)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		self:Apply(player)
	end
	return had
end

-- a pass for a player who is not here: handed over when they next join
function StaffService:QueuePass(userId: number, key: string, from: string)
	self:_commit(function(reg)
		local list = reg.Pending[tostring(userId)] or {}
		for _, entry in list do
			if entry.Key == key then
				return
			end
		end
		table.insert(list, { Key = key, From = from, Time = os.time() })
		reg.Pending[tostring(userId)] = list
	end)
end

function StaffService:_deliverPending(player: Player)
	local list = registry.Pending[tostring(player.UserId)]
	if not list or #list == 0 then
		return
	end
	local keys = {}
	self:_commit(function(reg)
		keys = reg.Pending[tostring(player.UserId)] or {}
		reg.Pending[tostring(player.UserId)] = nil
	end)
	for _, entry in keys do
		if Config.GamePasses[entry.Key] then
			S.MonetizationService:GrantPass(player, entry.Key, entry.From)
		end
	end
end

---------------------------------------------------------------------------
-- Applying to a player
---------------------------------------------------------------------------
local function addTitleTag(player: Player, character: Model, title)
	local head = character:WaitForChild("Head", 10) :: BasePart?
	if not head then
		return
	end
	local old = head:FindFirstChild("StaffTitle")
	if old then
		if title and old:GetAttribute("Text") == title.Text and old:GetAttribute("Color") == title.Color then
			return -- unchanged (the registry is re-read every minute)
		end
		old:Destroy()
	end
	if not title then
		return
	end
	local color = title.Color
	local tag = Instance.new("BillboardGui")
	tag.Name = "StaffTitle"
	tag:SetAttribute("Text", title.Text)
	tag:SetAttribute("Color", title.Color)
	tag.Size = UDim2.fromOffset(240, 34)
	tag.StudsOffset = Vector3.new(0, 4.9, 0)
	tag.MaxDistance = 120
	tag.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.Text = title.Text
	local rainbow = color == "rainbow"
	label.TextColor3 = rainbow and Color3.new(1, 1, 1) or (Color3.fromHex(color))
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Glow"
	stroke.Thickness = 3
	stroke.Color = label.TextColor3
	stroke.Transparency = 0.45
	stroke.Parent = label
	label:SetAttribute("Rainbow", rainbow)
	CollectionService:AddTag(label, "GlowTitle")
	label.Parent = tag
	tag.Parent = head
end

-- (re)applies permissions and the title to a player
function StaffService:Apply(player: Player)
	local groups = {}
	for id in self:GetGroups(player.UserId) do
		if groupById[id] then
			table.insert(groups, id)
		end
	end
	table.sort(groups)
	player:SetAttribute("AdminPerms", table.concat(groups, ","))
	local title = self:GetTitle(player.UserId)
	player:SetAttribute("TitleText", title and title.Text or nil)
	player:SetAttribute("TitleColor", title and title.Color or nil)
	if player.Character then
		task.spawn(addTitleTag, player, player.Character, title)
	end
end

function StaffService:Init(services)
	S = services

	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			local title = self:GetTitle(player.UserId)
			if title then
				addTitleTag(player, character, title)
			end
		end)
		task.spawn(function()
			local waited = 0
			while not loaded and waited < 10 do
				waited += task.wait(0.25)
			end
			if player.Parent then
				self:Apply(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	S.DataService.PlayerLoaded:Connect(function(player)
		Util.Try("Staff pending passes", self._deliverPending, self, player)
	end)

	task.spawn(function()
		self:Refresh()
		loaded = true
	end)
	if not store then
		loaded = true
	end
end

function StaffService:Start()
	while true do
		task.wait(AC.StaffRefreshSeconds)
		Util.Try("Staff refresh", self.Refresh, self)
	end
end

return StaffService
