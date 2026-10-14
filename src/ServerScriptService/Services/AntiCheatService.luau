--[[
	AntiCheatService - catches common exploits on the server (never trust the client).

	What it looks for (all tunable in Config.AntiCheat):
	  Speed        running on the ground much faster than WalkSpeed allows
	  Fly          staying in the air for a long time without falling
	  Teleport     lots of big position jumps in a short time
	  Reach        rewards / touches claimed from far away (BuildKit.IsNear fails)
	  RemoteSpam   hundreds of remote events per second
	  AdminRemote  calling the admin remotes without a rank

	Every detection is a STRIKE: the player is kicked and the proof (what was
	seen, with numbers) is saved. Strikes are stored in a DataStore, so they
	count across servers and sessions. The StrikesToBan-th strike bans the player.
	Head Admins review the evidence in the admin panel (Anti-Cheat tab) and can
	unban from there or with ;unban. Strikes are forgotten after
	StrikeExpireDays without a new one.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local BuildKit = require(script.Parent.BuildKit)

local AC = Config.AntiCheat

local AntiCheatService = {}
local S

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(AC.DataStore)
end)

-- the saved registry (cached): both tables are keyed by tostring(UserId)
--   Strikes[id] = { Name, Count, Last, Evidence = { { Time, Kind, Detail, Server } } }
--   Bans[id]    = { UserId, Name, Time, By, Reason, Strikes, Evidence }
local registry: { Strikes: { [string]: any }, Bans: { [string]: any } } = { Strikes = {}, Bans = {} }

local handled: { [Player]: boolean } = {} -- already struck this session (being kicked)
local tracks: { [Player]: any } = {} -- movement samples
local scores: { [Player]: { [string]: any } } = {} -- [kind] = { Score, Since, Notes }
local remoteCounts: { [Player]: number } = {}
local spamSeconds: { [Player]: number } = {}

local function title(kind: string): string
	local def = AC.Kinds[kind]
	return def and def.Title or kind
end

---------------------------------------------------------------------------
-- The saved registry
---------------------------------------------------------------------------
-- applies `mutate` to the saved registry (atomically across servers) and
-- caches the result; without a DataStore it only changes this server's copy
function AntiCheatService:_commit(mutate: (any) -> ()): boolean
	local dataStore = store
	if dataStore then
		local ok, result = pcall(function()
			return dataStore:UpdateAsync("Registry", function(old)
				local reg = type(old) == "table" and old or {}
				reg.Strikes = reg.Strikes or {}
				reg.Bans = reg.Bans or {}
				mutate(reg)
				return reg
			end)
		end)
		if ok and type(result) == "table" then
			registry = result
			return true
		end
		warn("[AntiCheat] could not save the registry: " .. tostring(result))
	end
	mutate(registry)
	return false
end

-- re-reads the saved registry and kicks anyone in this server who got banned elsewhere
function AntiCheatService:Refresh(): boolean
	local dataStore = store
	if not dataStore then
		return false
	end
	local ok, result = pcall(function()
		return dataStore:GetAsync("Registry")
	end)
	if not ok or type(result) ~= "table" then
		return false
	end
	result.Strikes = result.Strikes or {}
	result.Bans = result.Bans or {}
	registry = result
	for _, player in Players:GetPlayers() do
		local ban = registry.Bans[tostring(player.UserId)]
		if ban then
			handled[player] = true
			player:Kick("You are banned for cheating: " .. tostring(ban.Reason))
		end
	end
	return true
end

-- plain lists for the admin panel (newest first); the evidence is what was seen
function AntiCheatService:GetReport()
	self:Refresh()
	local bans, strikes = {}, {}
	for _, ban in registry.Bans do
		table.insert(bans, ban)
	end
	for _, record in registry.Strikes do
		table.insert(strikes, { UserId = record.UserId or 0, Name = record.Name, Count = record.Count, Time = record.Last or 0, Evidence = record.Evidence })
	end
	local function newestFirst(a, b)
		return a.Time > b.Time
	end
	table.sort(bans, newestFirst)
	table.sort(strikes, newestFirst)
	return { Bans = bans, Strikes = strikes, StrikesToBan = AC.StrikesToBan }
end

-- (strikes, banned) of one user
function AntiCheatService:GetStrikes(userId: number): (number, boolean)
	local key = tostring(userId)
	local ban = registry.Bans[key]
	if ban then
		return ban.Strikes or AC.StrikesToBan, true
	end
	local record = registry.Strikes[key]
	return record and record.Count or 0, false
end

function AntiCheatService:Unban(userId: number): boolean
	local key = tostring(userId)
	local existed = false
	self:_commit(function(reg)
		existed = reg.Bans[key] ~= nil or reg.Strikes[key] ~= nil
		reg.Bans[key] = nil
		reg.Strikes[key] = nil
	end)
	return existed
end

function AntiCheatService:ClearStrikes(userId: number): boolean
	local key = tostring(userId)
	local existed = false
	self:_commit(function(reg)
		existed = reg.Strikes[key] ~= nil
		reg.Strikes[key] = nil
	end)
	return existed
end

-- a ban an admin made by hand: listed in the panel too, so it can be undone there
function AntiCheatService:RecordBan(userId: number, name: string, reason: string, by: string)
	self:_commit(function(reg)
		reg.Bans[tostring(userId)] = { UserId = userId, Name = name, Time = os.time(), By = by, Reason = reason, Strikes = 0, Evidence = {} }
	end)
end

---------------------------------------------------------------------------
-- Strikes
---------------------------------------------------------------------------
function AntiCheatService:IsExempt(player: Player): boolean
	return S.AdminService ~= nil and S.AdminService:GetRank(player) >= AC.ExemptRank
end

-- tell the online admins what happened
function AntiCheatService:_tell(text: string)
	if not S.AdminService then
		return
	end
	for _, admin in Players:GetPlayers() do
		if S.AdminService:GetRank(admin) >= 2 then
			Remotes.Notify:FireClient(admin, { Text = "🛡️ " .. text, Type = "error", Duration = 8 })
		end
	end
end

-- "Speed hacking x3, Flying x2"
local function summarize(evidence): string
	local counts, order = {}, {}
	for _, entry in evidence do
		if not counts[entry.Kind] then
			counts[entry.Kind] = 0
			table.insert(order, entry.Kind)
		end
		counts[entry.Kind] += 1
	end
	local parts = {}
	for _, kind in order do
		table.insert(parts, title(kind) .. " x" .. counts[kind])
	end
	return table.concat(parts, ", ")
end

function AntiCheatService:_strike(player: Player, kind: string, detail: string)
	if handled[player] then
		return
	end
	handled[player] = true -- one strike per visit: they're about to be kicked
	local userId, name = player.UserId, player.Name
	local key = tostring(userId)
	local evidence = { Time = os.time(), Kind = kind, Detail = string.sub(detail, 1, 500), Server = game.JobId }
	task.spawn(function()
		local count, banned, reason = 0, false, ""
		self:_commit(function(reg)
			-- forget players whose last strike is old
			local expire = os.time() - AC.StrikeExpireDays * 86400
			for otherKey, other in reg.Strikes do
				if (other.Last or 0) < expire then
					reg.Strikes[otherKey] = nil
				end
			end
			local record = reg.Strikes[key] or { Count = 0, Evidence = {} }
			record.Name = name
			record.UserId = userId
			record.Last = evidence.Time
			record.Count += 1
			table.insert(record.Evidence, evidence)
			while #record.Evidence > AC.MaxEvidence do
				table.remove(record.Evidence, 1)
			end
			count = record.Count
			banned = count >= AC.StrikesToBan
			if banned then
				reason = "Cheating: " .. summarize(record.Evidence)
				reg.Bans[key] = { UserId = userId, Name = name, Time = evidence.Time, By = "Anti-Cheat", Reason = reason, Strikes = count, Evidence = record.Evidence }
				reg.Strikes[key] = nil
			else
				reg.Strikes[key] = record
			end
		end)
		if banned then
			if S.AdminService then
				S.AdminService:Ban(userId, reason, "Anti-Cheat")
			end
			self:_tell(name .. " was BANNED by the anti-cheat (" .. reason .. ")")
			player:Kick("You are banned for cheating (" .. reason .. "). If this is a mistake, contact the game owner.")
		else
			self:_tell(("%s was kicked: %s (strike %d/%d)"):format(name, title(kind), count, AC.StrikesToBan))
			local warning = count == AC.StrikesToBan - 1 and " The next strike is a permanent ban!" or ""
			player:Kick(("Anti-cheat: %s detected (strike %d/%d).%s"):format(title(kind), count, AC.StrikesToBan, warning))
		end
	end)
end

-- a sign of cheating. Some kinds need several signs within a window before they count.
function AntiCheatService:Flag(player: Player, kind: string, detail: string, weight: number?)
	local def = AC.Kinds[kind]
	if not AC.Enabled or not def or handled[player] or self:IsExempt(player) then
		return
	end
	local byKind = scores[player]
	if not byKind then
		byKind = {}
		scores[player] = byKind
	end
	local now = os.clock()
	local entry = byKind[kind]
	if not entry or now - entry.Since > def.Window then
		entry = { Score = 0, Since = now, Notes = {} }
		byKind[kind] = entry
	end
	entry.Score += weight or 1
	if #entry.Notes < 3 then
		table.insert(entry.Notes, detail)
	end
	if entry.Score >= def.Threshold then
		byKind[kind] = nil
		local text = detail
		if #entry.Notes > 1 then
			text = ("%s (%d signs in %ds: %s)"):format(kind, math.floor(entry.Score), def.Window, table.concat(entry.Notes, "; "))
		end
		self:_strike(player, kind, text)
	end
end

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------
local function describe(position: Vector3): string
	return ("(%d, %d, %d)"):format(position.X, position.Y, position.Z)
end

-- movement: called every Speed.Interval seconds for every player
function AntiCheatService:_sample(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		tracks[player] = nil
		return
	end
	local now = os.clock()
	local track = tracks[player]
	if not track or track.Character ~= character then
		tracks[player] = { Character = character, Position = root.Position, Time = now, Streak = 0, Worst = 0, Airborne = 0, Start = root.Position }
		return
	end
	local dt = now - track.Time
	if dt < AC.Speed.Interval * 0.5 then
		return
	end
	local delta = root.Position - track.Position
	local from = track.Position
	track.Position, track.Time = root.Position, now
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local speed = flat / dt

	local state = humanoid:GetState()
	local special = humanoid.Sit or humanoid.PlatformStand
		or state == Enum.HumanoidStateType.Climbing or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Seated or state == Enum.HumanoidStateType.Physics
		or state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.FallingDown
		or player:GetAttribute("InMinigame") == true or workspace:GetAttribute("Disaster") == "Tornado"
	if special then
		track.Streak, track.Worst, track.Airborne = 0, 0, 0
		return
	end
	if flat > AC.Speed.TeleportDistance then
		-- a teleport (going home, into a minigame...) happens now and then; many in a row is a cheat
		track.Streak, track.Worst, track.Airborne = 0, 0, 0
		self:Flag(player, "Teleport", ("Jumped %d studs in %.2fs: %s -> %s"):format(flat, dt, describe(from), describe(root.Position)))
		return
	end

	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local allowed = humanoid.WalkSpeed * AC.Speed.Tolerance + AC.Speed.Slack
	if grounded and speed > allowed then
		if track.Streak == 0 then
			track.Start = from
		end
		track.Streak += 1
		track.Worst = math.max(track.Worst, speed)
		if track.Streak >= AC.Speed.Samples then
			local detail = ("Ran %d studs/s for %.1fs on the ground (WalkSpeed %d allows %d), %s -> %s"):format(track.Worst, track.Streak * AC.Speed.Interval, humanoid.WalkSpeed, allowed, describe(track.Start), describe(root.Position))
			track.Streak, track.Worst = 0, 0
			self:Flag(player, "Speed", detail)
		end
	else
		track.Streak, track.Worst = 0, 0
	end

	-- flying: a long time in the air, and not falling
	if not grounded and delta.Y / dt > -AC.Fly.MinFallSpeed then
		track.Airborne += dt
		if track.Airborne >= AC.Fly.Seconds then
			local detail = ("In the air for %ds without falling (vertical speed %d studs/s) at %s"):format(track.Airborne, delta.Y / dt, describe(root.Position))
			track.Airborne = 0
			self:Flag(player, "Fly", detail)
		end
	else
		track.Airborne = 0
	end
end

-- remote events: counted once per second
function AntiCheatService:_checkSpam()
	for player, count in remoteCounts do
		if count > AC.RemoteSpam.PerSecond then
			spamSeconds[player] = (spamSeconds[player] or 0) + 1
			if spamSeconds[player] >= AC.RemoteSpam.Seconds then
				spamSeconds[player] = 0
				self:Flag(player, "RemoteSpam", ("Sent %d remote events in one second (limit %d), %d seconds in a row"):format(count, AC.RemoteSpam.PerSecond, AC.RemoteSpam.Seconds))
			end
		else
			spamSeconds[player] = 0
		end
	end
	table.clear(remoteCounts)
end

function AntiCheatService:Init(services)
	S = services
	if not AC.Enabled then
		return
	end
	-- touches from far away (BuildKit.IsNear says no)
	BuildKit.OnFarTouch = function(player, part, distance, allowed)
		if distance > allowed + AC.Reach.Margin then
			self:Flag(player, "Reach", ("Touched %s from %d studs away (allowed %d)"):format(part:GetFullName(), distance, allowed))
		end
	end
	-- every remote event counts toward the spam check
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	for _, remote in folder and folder:GetChildren() or {} do
		if remote:IsA("RemoteEvent") then
			remote.OnServerEvent:Connect(function(player)
				remoteCounts[player] = (remoteCounts[player] or 0) + 1
			end)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		handled[player], tracks[player], scores[player] = nil, nil, nil
		remoteCounts[player], spamSeconds[player] = nil, nil
	end)
	task.spawn(function()
		self:Refresh()
	end)
end

function AntiCheatService:Start()
	if not AC.Enabled then
		return
	end
	task.spawn(function()
		while true do
			task.wait(1)
			Util.Try("AntiCheat spam", self._checkSpam, self)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AC.RefreshSeconds)
			Util.Try("AntiCheat refresh", self.Refresh, self)
		end
	end)
	while true do
		task.wait(AC.Speed.Interval)
		for _, player in Players:GetPlayers() do
			if not handled[player] and not self:IsExempt(player) then
				Util.Try("AntiCheat", self._sample, self, player)
			end
		end
	end
end

return AntiCheatService
