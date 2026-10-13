--[[
	AdminService - rank-based admin commands (chat ";cmd" or the Admin Panel).

	Ranks: 1 Mod, 2 Admin, 3 Head Admin, 4 Owner (see Config.Admin)
	Player selectors: me, all, others, random, admins, nonadmins,
	partial names ("rob" -> Roblox), or comma lists ("me,bob").
	Amounts accept suffixes: 10k, 2.5m, 1b
]]
local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local BuildKit = require(script.Parent.BuildKit)

local AdminService = {}
local S

local commands = {}
local byName: { [string]: any } = {}
local logs: { { Time: number, By: string, Text: string } } = {}
local tempRanks: { [number]: number } = {}
local jails: { [Player]: Model } = {}

local banStore: DataStore? = nil
pcall(function()
	banStore = DataStoreService:GetDataStore(Config.Admin.BanDataStore)
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function computeRank(player: Player): number
	if RunService:IsStudio() and Config.Admin.StudioEveryoneIsOwner then
		return 4
	end
	local rank = 0
	if Config.Admin.CreatorIsOwner then
		if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
			return 4
		elseif game.CreatorType == Enum.CreatorType.Group then
			local ok, groupRank = pcall(player.GetRankInGroup, player, game.CreatorId)
			if ok and groupRank == 255 then
				return 4
			end
		end
	end
	rank = math.max(rank, Config.Admin.Admins[player.UserId] or 0)
	if Config.Admin.GroupId ~= 0 then
		local ok, groupRank = pcall(player.GetRankInGroup, player, Config.Admin.GroupId)
		if ok then
			for minGroupRank, adminRank in Config.Admin.GroupRanks do
				if groupRank >= minGroupRank then
					rank = math.max(rank, adminRank)
				end
			end
		end
	end
	rank = math.max(rank, tempRanks[player.UserId] or 0)
	return rank
end

function AdminService:GetRank(player: Player): number
	return tonumber(player:GetAttribute("AdminRank")) or 0
end

local function filterBroadcast(text: string, from: Player): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, from.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	return nil
end

local function parseAmount(text: string?): number?
	if not text then
		return nil
	end
	local clean = ((text :: string):lower():gsub(",", ""))
	local number, suffix = clean:match("^(%-?[%d%.]+)(%a*)$")
	number = Util.Number(number)
	if not number then
		return nil
	end
	local mult = ({ [""] = 1, k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15 })[suffix]
	if not mult then
		return nil
	end
	return Util.Number(number * mult)
end

local function getCharacterParts(player: Player)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	return character, character:FindFirstChildOfClass("Humanoid"), character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Resolve a selector string to a list of players
local function resolvePlayers(executor: Player, selector: string?): { Player }
	if not selector or selector == "" then
		return { executor }
	end
	local result = {}
	local seen = {}
	local function add(p: Player)
		if not seen[p] then
			seen[p] = true
			table.insert(result, p)
		end
	end
	for _, token in (selector :: string):lower():split(",") do
		if token == "me" then
			add(executor)
		elseif token == "all" or token == "everyone" then
			for _, p in Players:GetPlayers() do
				add(p)
			end
		elseif token == "others" then
			for _, p in Players:GetPlayers() do
				if p ~= executor then
					add(p)
				end
			end
		elseif token == "random" then
			local list = Players:GetPlayers()
			add(list[math.random(1, #list)])
		elseif token == "admins" then
			for _, p in Players:GetPlayers() do
				if AdminService:GetRank(p) > 0 then
					add(p)
				end
			end
		elseif token == "nonadmins" then
			for _, p in Players:GetPlayers() do
				if AdminService:GetRank(p) == 0 then
					add(p)
				end
			end
		elseif token ~= "" then
			for _, p in Players:GetPlayers() do
				if p.Name:lower():sub(1, #token) == token or p.DisplayName:lower():sub(1, #token) == token then
					add(p)
				end
			end
		end
	end
	return result
end

local function namesOf(list: { Player }): string
	local names = {}
	for _, p in list do
		table.insert(names, p.DisplayName)
	end
	return #names > 0 and table.concat(names, ", ") or "nobody"
end

local function restText(args: { string }, from: number): string
	local parts = {}
	for i = from, #args do
		table.insert(parts, args[i])
	end
	return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Command registry
---------------------------------------------------------------------------
local function register(def)
	table.insert(commands, def)
	byName[def.Name:lower()] = def
	for _, alias in def.Aliases or {} do
		byName[alias:lower()] = def
	end
end

-- Targets helper: iterates targets, skips players with higher/equal rank for harmful commands
local function eachTarget(executor: Player, selector: string?, harmful: boolean, fn: (Player) -> ())
	local targets = resolvePlayers(executor, selector)
	local myRank = AdminService:GetRank(executor)
	local affected = {}
	for _, target in targets do
		-- staff can't be harmed by equal/lower ranks (the Owner can do anything,
		-- which also lets Studio play-testers - all Owners - test on each other)
		if harmful and target ~= executor and myRank < 4 and AdminService:GetRank(target) >= myRank then
			continue
		end
		local ok, err = pcall(fn, target)
		if ok then
			table.insert(affected, target)
		else
			warn("[Admin] " .. tostring(err))
		end
	end
	return affected
end

local function charCommand(name, aliases, rank, desc, harmful, fn)
	register({
		Name = name,
		Aliases = aliases,
		Rank = rank,
		Args = "<player>",
		Desc = desc,
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], harmful, function(target)
				local character, humanoid, root = getCharacterParts(target)
				if character and humanoid and root then
					fn(target, character, humanoid, root, args)
				end
			end)
			return name .. ": " .. namesOf(affected)
		end,
	})
end

local function buildCommands()
	---------------- Mod (1) ----------------
	register({
		Name = "cmds",
		Aliases = { "commands", "help" },
		Rank = 1,
		Args = "",
		Desc = "Open the admin panel with all commands",
		Run = function(executor)
			Remotes.ClientCommand:FireClient(executor, "openadmin", "Commands")
			return "Opened admin panel"
		end,
	})
	register({
		Name = "logs",
		Aliases = {},
		Rank = 1,
		Args = "",
		Desc = "Show the command log",
		Run = function(executor)
			Remotes.ClientCommand:FireClient(executor, "openadmin", "Logs")
			return "Opened logs"
		end,
	})
	register({
		Name = "tp",
		Aliases = { "teleport" },
		Rank = 1,
		Args = "<player> <player>",
		Desc = "Teleport players to another player",
		Run = function(executor, args)
			local dest = resolvePlayers(executor, args[2])[1]
			if not dest then
				return "Destination not found"
			end
			local _, _, destRoot = getCharacterParts(dest)
			if not destRoot then
				return "Destination not found"
			end
			local affected = eachTarget(executor, args[1], false, function(target)
				if target.Character and target ~= dest then
					target.Character:PivotTo(destRoot.CFrame * CFrame.new(math.random(-3, 3), 0, 4))
				end
			end)
			return "Teleported " .. namesOf(affected) .. " to " .. dest.DisplayName
		end,
	})
	register({
		Name = "bring",
		Aliases = {},
		Rank = 1,
		Args = "<player>",
		Desc = "Bring players to you",
		Run = function(executor, args)
			local _, _, root = getCharacterParts(executor)
			if not root then
				return "You have no character"
			end
			local affected = eachTarget(executor, args[1], false, function(target)
				if target ~= executor and target.Character then
					target.Character:PivotTo(root.CFrame * CFrame.new(math.random(-4, 4), 0, -5))
				end
			end)
			return "Brought " .. namesOf(affected)
		end,
	})
	register({
		Name = "to",
		Aliases = { "goto" },
		Rank = 1,
		Args = "<player>",
		Desc = "Teleport yourself to a player",
		Run = function(executor, args)
			local target = resolvePlayers(executor, args[1])[1]
			if not target then
				return "Player not found"
			end
			local _, _, root = getCharacterParts(target)
			if not root or not executor.Character then
				return "Player not found"
			end
			executor.Character:PivotTo(root.CFrame * CFrame.new(0, 0, 4))
			return "Teleported to " .. target.DisplayName
		end,
	})
	register({
		Name = "home",
		Aliases = { "plot" },
		Rank = 1,
		Args = "<player>",
		Desc = "Send players back to their tycoon",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				target:SetAttribute("ObbyStage", 0)
				S.TycoonService:TeleportHome(target)
			end)
			return "Sent home: " .. namesOf(affected)
		end,
	})
	charCommand("speed", { "ws", "walkspeed" }, 1, "Set walk speed: ;speed me 50", false, function(_, _, humanoid, _, args)
		humanoid.WalkSpeed = math.clamp(Util.Number(args[2]) or 16, 0, 500)
	end)
	charCommand("jump", { "jp", "jumppower" }, 1, "Set jump power: ;jump me 100", false, function(_, _, humanoid, _, args)
		humanoid.UseJumpPower = true
		humanoid.JumpPower = math.clamp(Util.Number(args[2]) or 50, 0, 1000)
	end)
	charCommand("heal", {}, 1, "Fully heal players", false, function(_, _, humanoid)
		humanoid.Health = humanoid.MaxHealth
	end)
	charCommand("god", {}, 1, "Make players invincible", false, function(_, _, humanoid)
		humanoid.MaxHealth = math.huge
		humanoid.Health = math.huge
	end)
	charCommand("ungod", {}, 1, "Remove god mode", false, function(_, _, humanoid)
		humanoid.MaxHealth = 100
		humanoid.Health = 100
	end)
	charCommand("ff", { "forcefield" }, 1, "Give a force field", false, function(_, character)
		Instance.new("ForceField").Parent = character
	end)
	charCommand("unff", {}, 1, "Remove force fields", false, function(_, character)
		for _, ff in character:GetChildren() do
			if ff:IsA("ForceField") then
				ff:Destroy()
			end
		end
	end)
	charCommand("kill", {}, 1, "Kill players", true, function(_, _, humanoid)
		humanoid.Health = 0
	end)
	charCommand("freeze", {}, 1, "Freeze players in place", true, function(_, _, _, root)
		root.Anchored = true
	end)
	charCommand("thaw", { "unfreeze" }, 1, "Unfreeze players", false, function(_, _, _, root)
		root.Anchored = false
	end)
	charCommand("sparkles", {}, 1, "Give sparkles", false, function(_, _, _, root)
		Instance.new("Sparkles").Parent = root
	end)
	charCommand("fire", {}, 1, "Set players on (harmless) fire", false, function(_, _, _, root)
		Instance.new("Fire").Parent = root
	end)
	charCommand("smoke", {}, 1, "Give smoke", false, function(_, _, _, root)
		Instance.new("Smoke").Parent = root
	end)
	charCommand("unfx", { "uneffects" }, 1, "Remove sparkles/fire/smoke", false, function(_, _, _, root)
		for _, child in root:GetChildren() do
			if child:IsA("Sparkles") or child:IsA("Fire") or child:IsA("Smoke") then
				child:Destroy()
			end
		end
	end)
	charCommand("invisible", { "invis" }, 1, "Make players invisible", false, function(_, character)
		for _, d in character:GetDescendants() do
			if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
				(d :: any).Transparency = 1
			end
		end
	end)
	charCommand("visible", { "vis" }, 1, "Make players visible again", false, function(_, character)
		for _, d in character:GetDescendants() do
			if (d:IsA("BasePart") and d.Name ~= "HumanoidRootPart") or d:IsA("Decal") then
				(d :: any).Transparency = 0
			end
		end
	end)
	charCommand("respawn", { "re", "refresh" }, 1, "Respawn players", false, function(target)
		target:LoadCharacter()
	end)
	charCommand("jail", {}, 1, "Lock players in a cage", true, function(target, _, _, root)
		if jails[target] then
			jails[target]:Destroy()
		end
		local cage = BuildKit.Model("Jail_" .. target.Name, workspace)
		local center = root.Position
		local barColor = Color3.fromRGB(40, 40, 40)
		for _, data in {
			{ Vector3.new(10, 1, 10), Vector3.new(0, -3.5, 0) },
			{ Vector3.new(10, 1, 10), Vector3.new(0, 5.5, 0) },
			{ Vector3.new(1, 9, 10), Vector3.new(-5, 1, 0) },
			{ Vector3.new(1, 9, 10), Vector3.new(5, 1, 0) },
			{ Vector3.new(10, 9, 1), Vector3.new(0, 1, -5) },
			{ Vector3.new(10, 9, 1), Vector3.new(0, 1, 5) },
		} do
			BuildKit.Part({ Size = data[1], Position = center + data[2], Color = barColor, Material = Enum.Material.ForceField, Transparency = 0.3, Parent = cage })
		end
		jails[target] = cage
	end)
	charCommand("unjail", {}, 1, "Free players from jail", false, function(target)
		if jails[target] then
			jails[target]:Destroy()
			jails[target] = nil
		end
	end)
	register({
		Name = "fly",
		Aliases = {},
		Rank = 1,
		Args = "<player>",
		Desc = "Let players fly (WASD + Space/Ctrl)",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				Remotes.ClientCommand:FireClient(target, "fly", true)
			end)
			return "Fly: " .. namesOf(affected)
		end,
	})
	register({
		Name = "unfly",
		Aliases = {},
		Rank = 1,
		Args = "<player>",
		Desc = "Stop flying",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				Remotes.ClientCommand:FireClient(target, "fly", false)
			end)
			return "Unfly: " .. namesOf(affected)
		end,
	})
	register({
		Name = "noclip",
		Aliases = {},
		Rank = 1,
		Args = "<player>",
		Desc = "Walk through walls",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				Remotes.ClientCommand:FireClient(target, "noclip", true)
			end)
			return "Noclip: " .. namesOf(affected)
		end,
	})
	register({
		Name = "clip",
		Aliases = {},
		Rank = 1,
		Args = "<player>",
		Desc = "Disable noclip",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				Remotes.ClientCommand:FireClient(target, "noclip", false)
			end)
			return "Clip: " .. namesOf(affected)
		end,
	})
	register({
		Name = "view",
		Aliases = { "spectate" },
		Rank = 1,
		Args = "<player>",
		Desc = "Spectate a player",
		Run = function(executor, args)
			local target = resolvePlayers(executor, args[1])[1]
			if not target then
				return "Player not found"
			end
			Remotes.ClientCommand:FireClient(executor, "view", target)
			return "Viewing " .. target.DisplayName
		end,
	})
	register({
		Name = "unview",
		Aliases = {},
		Rank = 1,
		Args = "",
		Desc = "Stop spectating",
		Run = function(executor)
			Remotes.ClientCommand:FireClient(executor, "view", nil)
			return "Stopped viewing"
		end,
	})
	register({
		Name = "m",
		Aliases = { "announce", "message" },
		Rank = 1,
		Args = "<text>",
		Desc = "Big announcement to everyone",
		Run = function(executor, args)
			local text = filterBroadcast(restText(args, 1), executor)
			if not text or text == "" then
				return "Message could not be sent"
			end
			Remotes.Announce:FireAllClients({ Title = "📢 " .. executor.DisplayName, Text = text, Color = Color3.fromRGB(255, 196, 0) })
			return "Announced"
		end,
	})
	register({
		Name = "h",
		Aliases = { "hint" },
		Rank = 1,
		Args = "<text>",
		Desc = "Small notification to everyone",
		Run = function(executor, args)
			local text = filterBroadcast(restText(args, 1), executor)
			if not text or text == "" then
				return "Hint could not be sent"
			end
			Remotes.Notify:FireAllClients({ Text = executor.DisplayName .. ": " .. text, Type = "info", Duration = 6 })
			return "Hint sent"
		end,
	})

	---------------- Admin (2) ----------------
	register({
		Name = "kick",
		Aliases = {},
		Rank = 2,
		Args = "<player> [reason]",
		Desc = "Kick players from the server",
		Run = function(executor, args)
			local reason = filterBroadcast(restText(args, 2), executor) or ""
			local affected = eachTarget(executor, args[1], true, function(target)
				if target ~= executor then
					target:Kick("Kicked by " .. executor.Name .. (reason ~= "" and (": " .. reason) or ""))
				end
			end)
			return "Kicked " .. namesOf(affected)
		end,
	})
	local function cashCommand(name, aliases, desc, fn)
		register({
			Name = name,
			Aliases = aliases,
			Rank = 2,
			Args = "<player> <amount>",
			Desc = desc,
			Run = function(executor, args)
				local amount = parseAmount(args[2])
				if not amount then
					return "Invalid amount (try 10k, 5m, 1b)"
				end
				local affected = eachTarget(executor, args[1], false, function(target)
					fn(target, amount)
				end)
				return name .. " " .. Util.Money(amount) .. ": " .. namesOf(affected)
			end,
		})
	end
	cashCommand("givecash", { "give", "addcash", "cash" }, "Give cash: ;givecash me 1m", function(target, amount)
		S.DataService:AddCash(target, amount, false)
		Remotes.VFX:FireClient(target, "CashBurst", { Amount = amount })
	end)
	cashCommand("takecash", { "removecash" }, "Take cash away", function(target, amount)
		S.DataService:AddCash(target, -amount, false)
	end)
	cashCommand("setcash", {}, "Set cash to an exact amount", function(target, amount)
		S.DataService:SetCash(target, amount)
	end)
	register({
		Name = "giverebirth",
		Aliases = { "addrebirths", "setrebirths" },
		Rank = 2,
		Args = "<player> <amount>",
		Desc = "Add rebirths (without resetting the tycoon)",
		Run = function(executor, args)
			local amount = math.clamp(math.floor(Util.Number(args[2]) or 1), -1000, 1000)
			local affected = eachTarget(executor, args[1], false, function(target)
				local data = S.DataService:Get(target)
				if data then
					data.Rebirths = math.clamp(data.Rebirths + amount, 0, 10000)
					S.DataService:Sync(target)
				end
			end)
			return "Rebirths +" .. amount .. ": " .. namesOf(affected)
		end,
	})
	register({
		Name = "rebirth",
		Aliases = { "forcerebirth" },
		Rank = 2,
		Args = "<player>",
		Desc = "Force a free rebirth",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				S.TycoonService:Rebirth(target, true)
			end)
			return "Rebirthed " .. namesOf(affected)
		end,
	})
	register({
		Name = "unlockall",
		Aliases = { "maxtycoon" },
		Rank = 2,
		Args = "<player>",
		Desc = "Instantly build the whole tycoon",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				S.TycoonService:UnlockAll(target)
			end)
			return "Unlocked all: " .. namesOf(affected)
		end,
	})
	charCommand("explode", { "boom" }, 2, "Blow players up", true, function(_, _, _, root)
		local explosion = Instance.new("Explosion")
		explosion.Position = root.Position
		explosion.BlastRadius = 8
		explosion.DestroyJointRadiusPercent = 1
		explosion.Parent = workspace
		Remotes.VFX:FireAllClients("Shockwave", { Position = root.Position, Color = Color3.fromRGB(255, 120, 0), Size = 40 })
	end)
	charCommand("giant", { "big" }, 2, "Make players huge", false, function(_, character)
		character:ScaleTo(2.5)
	end)
	charCommand("tiny", { "small" }, 2, "Make players tiny", false, function(_, character)
		character:ScaleTo(0.4)
	end)
	charCommand("normal", { "unsize" }, 2, "Reset player size", false, function(_, character)
		character:ScaleTo(1)
	end)
	charCommand("confetti", {}, 2, "Confetti explosion on players", false, function(_, _, _, root)
		Remotes.VFX:FireAllClients("Confetti", { Position = root.Position + Vector3.new(0, 3, 0) })
	end)
	register({
		Name = "cashrain",
		Aliases = { "makeitrain" },
		Rank = 2,
		Args = "",
		Desc = "Cash rain: everyone gets cash",
		Run = function(executor)
			S.MonetizationService:CashRain(executor.DisplayName)
			return "Cash rain started"
		end,
	})
	register({
		Name = "doublecash",
		Aliases = { "event", "2x" },
		Rank = 2,
		Args = "<minutes> [multiplier]",
		Desc = "Server-wide cash multiplier event",
		Run = function(executor, args)
			local minutes = math.clamp(Util.Number(args[1]) or 10, 1, 600)
			local mult = math.clamp(Util.Number(args[2]) or 2, 1, 100)
			S.DataService:StartEvent(mult, minutes * 60, "🔥 " .. mult .. "x CASH EVENT! 🔥", "Started by " .. executor.DisplayName .. " for " .. minutes .. " minutes!")
			return mult .. "x event for " .. minutes .. " min"
		end,
	})
	register({
		Name = "music",
		Aliases = { "play", "song" },
		Rank = 2,
		Args = "<soundId>",
		Desc = "Play a song for everyone",
		Run = function(_, args)
			local id = Util.Number(args[1])
			if not id then
				return "Invalid sound id"
			end
			Remotes.Music:FireAllClients("play", { Id = "rbxassetid://" .. id, Name = "DJ Track #" .. id })
			return "Playing " .. id
		end,
	})
	register({
		Name = "stopmusic",
		Aliases = { "resetmusic" },
		Rank = 2,
		Args = "",
		Desc = "Go back to the normal playlist",
		Run = function()
			Remotes.Music:FireAllClients("resume", {})
			return "Music reset"
		end,
	})
	register({
		Name = "minigame",
		Aliases = { "startminigame", "mg" },
		Rank = 2,
		Args = "[CoinRush|FallingTiles|MeteorShower]",
		Desc = "Start a minigame now",
		Run = function(_, args)
			if not S.MinigameService then
				return "Minigames unavailable"
			end
			return S.MinigameService:ForceStart(args[1])
		end,
	})
	register({
		Name = "time",
		Aliases = { "clocktime" },
		Rank = 2,
		Args = "<0-24>",
		Desc = "Set the time of day",
		Run = function(_, args)
			local t = Util.Number(args[1])
			if not t then
				return "Invalid time"
			end
			Lighting.ClockTime = t % 24
			return "Time set to " .. t
		end,
	})

	-- disasters
	local function disasterCommand(name, aliases, kind, desc)
		register({
			Name = name,
			Aliases = aliases,
			Rank = 2,
			Args = "",
			Desc = desc,
			Run = function(executor)
				if not S.DisasterService then
					return "Disasters unavailable"
				end
				return S.DisasterService:Trigger(kind, executor.DisplayName)
			end,
		})
	end
	disasterCommand("nuke", { "nuclear", "bomb" }, "Nuke", "Launch a nuke (30s warning, bunkers save you)")
	disasterCommand("meteors", { "meteorstorm" }, "Meteors", "Start a meteor storm")
	disasterCommand("tornado", { "twister" }, "Tornado", "Summon a tornado")
	disasterCommand("ufo", { "aliens", "invasion" }, "UFO", "Start a UFO invasion")
	register({
		Name = "stopdisaster",
		Aliases = { "stopevent", "calm" },
		Rank = 2,
		Args = "",
		Desc = "Stop the current disaster",
		Run = function()
			return S.DisasterService and S.DisasterService:Stop() or "Disasters unavailable"
		end,
	})
	register({
		Name = "repair",
		Aliases = { "fix" },
		Rank = 2,
		Args = "<player>",
		Desc = "Instantly repair wrecked upgrades",
		Run = function(executor, args)
			local total = 0
			local affected = eachTarget(executor, args[1], false, function(target)
				total += S.TycoonService:RepairAll(target)
			end)
			return "Repaired " .. total .. " items for " .. namesOf(affected)
		end,
	})
	register({
		Name = "wreck",
		Aliases = { "damage" },
		Rank = 2,
		Args = "<player> [percent]",
		Desc = "Wreck part of a tower (test the repair system)",
		Run = function(executor, args)
			local percent = math.clamp(Util.Number(args[2]) or 25, 1, 100)
			local total = 0
			local affected = eachTarget(executor, args[1], true, function(target)
				local plot = S.TycoonService:GetPlot(target)
				if plot then
					total += S.TycoonService:KnockOutFraction(plot, percent / 100, Config.Disasters.Nuke.KnockoutSeconds)
				end
			end)
			return "Wrecked " .. total .. " items: " .. namesOf(affected)
		end,
	})
	register({
		Name = "floor",
		Aliases = { "gofloor" },
		Rank = 1,
		Args = "<1-9>",
		Desc = "Teleport to a floor of your tower (9 = roof)",
		Run = function(executor, args)
			local plot = S.TycoonService:GetPlot(executor)
			if not plot then
				return "You have no tower"
			end
			S.TycoonService:TeleportToFloor(executor, plot.Index, Util.Number(args[1]) or 1)
			return "Teleported"
		end,
	})
	register({
		Name = "unlockfloor",
		Aliases = { "buildto" },
		Rank = 2,
		Args = "<player> <floor>",
		Desc = "Instantly build a tower up to a floor",
		Run = function(executor, args)
			local floor = math.clamp(math.floor(Util.Number(args[2]) or 1), 1, Config.Tycoon.Floors + 1)
			local affected = eachTarget(executor, args[1], false, function(target)
				S.TycoonService:UnlockAll(target, floor)
			end)
			return "Built up to floor " .. floor .. ": " .. namesOf(affected)
		end,
	})
	register({
		Name = "givesecrets",
		Aliases = { "allsecrets" },
		Rank = 2,
		Args = "<player>",
		Desc = "Unlock all 12 secrets",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				S.SecretService:FindAll(target)
			end)
			return "Gave all secrets to " .. namesOf(affected)
		end,
	})
	register({
		Name = "duo",
		Aliases = { "forceduo" },
		Rank = 2,
		Args = "<host> <partner>",
		Desc = "Put two players in a duo",
		Run = function(executor, args)
			local host = resolvePlayers(executor, args[1])[1]
			local partner = args[2] and resolvePlayers(executor, args[2])[1]
			if not host or not partner or host == partner then
				return "Usage: duo <host> <partner>"
			end
			local _, message = S.DuoService:Join(host, partner)
			return message
		end,
	})
	register({
		Name = "unduo",
		Aliases = { "breakduo" },
		Rank = 2,
		Args = "<player>",
		Desc = "End a player's duo",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], false, function(target)
				S.DuoService:Leave(target)
			end)
			return "Ended duo: " .. namesOf(affected)
		end,
	})

	---------------- Head Admin (3) ----------------
	register({
		Name = "ban",
		Aliases = {},
		Rank = 3,
		Args = "<player/username> [reason]",
		Desc = "Permanently ban a player (works offline too)",
		Run = function(executor, args)
			local reason = filterBroadcast(restText(args, 2), executor) or "No reason"
			local targets = resolvePlayers(executor, args[1])
			local banned = {}
			if #targets == 0 and args[1] then
				local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, args[1])
				if ok and userId then
					AdminService:Ban(userId, reason, executor.Name)
					return "Banned offline user " .. args[1]
				end
				return "User not found"
			end
			for _, target in targets do
				local myRank = AdminService:GetRank(executor)
				if target ~= executor and (myRank >= 4 or AdminService:GetRank(target) < myRank) then
					AdminService:Ban(target.UserId, reason, executor.Name)
					target:Kick("You are banned: " .. reason)
					table.insert(banned, target)
				end
			end
			return "Banned " .. namesOf(banned)
		end,
	})
	register({
		Name = "unban",
		Aliases = {},
		Rank = 3,
		Args = "<username>",
		Desc = "Unban a user by username",
		Run = function(_, args)
			if not args[1] then
				return "Usage: unban <username>"
			end
			local ok, userId = pcall(Players.GetUserIdFromNameAsync, Players, args[1])
			if not ok or not userId then
				return "User not found"
			end
			if banStore then
				pcall(function()
					(banStore :: DataStore):RemoveAsync(tostring(userId))
				end)
			end
			return "Unbanned " .. args[1]
		end,
	})
	register({
		Name = "resetsecrets",
		Aliases = {},
		Rank = 3,
		Args = "<player>",
		Desc = "Forget all found secrets",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], true, function(target)
				S.SecretService:Reset(target)
			end)
			return "Reset secrets: " .. namesOf(affected)
		end,
	})
	register({
		Name = "resetdata",
		Aliases = { "wipe" },
		Rank = 3,
		Args = "<player>",
		Desc = "Wipe a player's progress (keeps passes)",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], true, function(target)
				S.DataService:ResetData(target)
				S.TycoonService:Rebuild(target)
				S.DataService:Sync(target)
			end)
			return "Reset " .. namesOf(affected)
		end,
	})
	register({
		Name = "givepass",
		Aliases = { "pass" },
		Rank = 3,
		Args = "<player> <DoubleCash|AutoCollect|FastDroppers|VIP|SuperSpeed>",
		Desc = "Give a game pass for free",
		Run = function(executor, args)
			local key
			for k in Config.GamePasses do
				if args[2] and k:lower() == args[2]:lower() then
					key = k
				end
			end
			if not key then
				return "Unknown pass"
			end
			local affected = eachTarget(executor, args[1], false, function(target)
				S.MonetizationService:GrantPass(target, key)
			end)
			return "Gave " .. key .. " to " .. namesOf(affected)
		end,
	})
	register({
		Name = "removepass",
		Aliases = { "revokepass" },
		Rank = 3,
		Args = "<player> <pass>",
		Desc = "Remove an admin-given pass",
		Run = function(executor, args)
			local key
			for k in Config.GamePasses do
				if args[2] and k:lower() == args[2]:lower() then
					key = k
				end
			end
			if not key then
				return "Unknown pass"
			end
			local affected = eachTarget(executor, args[1], false, function(target)
				S.MonetizationService:RevokePass(target, key)
			end)
			return "Removed " .. key .. " from " .. namesOf(affected)
		end,
	})

	---------------- Owner (4) ----------------
	register({
		Name = "admin",
		Aliases = { "setrank", "rank" },
		Rank = 4,
		Args = "<player> <1-3>",
		Desc = "Give a player an admin rank (this server)",
		Run = function(executor, args)
			local rank = math.clamp(math.floor(Util.Number(args[2]) or 2), 0, 3)
			local affected = eachTarget(executor, args[1], false, function(target)
				if target ~= executor then
					tempRanks[target.UserId] = rank
					target:SetAttribute("AdminRank", computeRank(target))
					Remotes.Notify:FireClient(target, { Text = "You are now " .. Config.RankNames[rank] .. "! Say ;cmds", Type = "success", Duration = 6 })
				end
			end)
			return "Rank " .. rank .. ": " .. namesOf(affected)
		end,
	})
	register({
		Name = "unadmin",
		Aliases = {},
		Rank = 4,
		Args = "<player>",
		Desc = "Remove a temporary admin rank",
		Run = function(executor, args)
			local affected = eachTarget(executor, args[1], true, function(target)
				tempRanks[target.UserId] = nil
				target:SetAttribute("AdminRank", computeRank(target))
			end)
			return "Unadmined " .. namesOf(affected)
		end,
	})
	register({
		Name = "shutdown",
		Aliases = {},
		Rank = 4,
		Args = "",
		Desc = "Shut the server down (saves everyone first)",
		Run = function(executor)
			Remotes.Announce:FireAllClients({ Title = "⚠️ SERVER SHUTTING DOWN", Text = "Your data is being saved. Please rejoin!", Color = Color3.fromRGB(255, 60, 60) })
			task.delay(4, function()
				for _, p in Players:GetPlayers() do
					S.DataService:Save(p)
					p:Kick("Server shut down by " .. executor.Name .. ". Your data was saved - please rejoin!")
				end
			end)
			return "Shutting down..."
		end,
	})
end

---------------------------------------------------------------------------
-- Bans
---------------------------------------------------------------------------
function AdminService:Ban(userId: number, reason: string, by: string)
	if not banStore then
		return
	end
	pcall(function()
		(banStore :: DataStore):SetAsync(tostring(userId), { Reason = reason, By = by, Time = os.time() })
	end)
end

-- Returns true (and kicks) if banned
function AdminService:CheckBan(player: Player): boolean
	if not banStore then
		return false
	end
	local ok, entry = pcall(function()
		return (banStore :: DataStore):GetAsync(tostring(player.UserId))
	end)
	if ok and type(entry) == "table" then
		player:Kick("You are banned from this game. Reason: " .. tostring(entry.Reason))
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Execution
---------------------------------------------------------------------------
function AdminService:Execute(executor: Player, text: string): (boolean, string)
	if type(text) ~= "string" then
		return false, "Invalid command"
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	local prefix = Config.Admin.Prefix
	if text:sub(1, #prefix) == prefix then
		text = text:sub(#prefix + 1)
	end
	local args = {}
	for word in text:gmatch("%S+") do
		table.insert(args, word)
	end
	if #args == 0 then
		return false, "Type a command"
	end
	local name = (table.remove(args, 1) :: string):lower()
	local command = byName[name]
	if not command then
		return false, "Unknown command '" .. name .. "'. Try " .. prefix .. "cmds"
	end
	local rank = self:GetRank(executor)
	if rank < command.Rank then
		return false, "You need " .. Config.RankNames[command.Rank] .. " for that"
	end
	local ok, result = pcall(command.Run, executor, args)
	table.insert(logs, 1, { Time = os.time(), By = executor.Name, Text = prefix .. text })
	if #logs > 200 then
		table.remove(logs)
	end
	if not ok then
		warn("[Admin] " .. tostring(result))
		return false, "Error: " .. tostring(result)
	end
	return true, tostring(result or "Done")
end

function AdminService:Init(services)
	S = services
	buildCommands()

	local function onPlayer(player: Player)
		task.spawn(function()
			player:SetAttribute("AdminRank", computeRank(player))
		end)
		-- with TextChatService the client sends chat commands through the
		-- AdminCommand remote (see Admin controller); Chatted is the fallback
		-- for the legacy chat system only, so commands never run twice
		player.Chatted:Connect(function(message)
			if TextChatService.ChatVersion ~= Enum.ChatVersion.LegacyChatService then
				return
			end
			local prefix = Config.Admin.Prefix
			if message:sub(1, #prefix) ~= prefix or self:GetRank(player) <= 0 then
				return
			end
			local ok, result = self:Execute(player, message)
			Remotes.Notify:FireClient(player, { Text = result, Type = ok and "success" or "error" })
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		if jails[player] then
			jails[player]:Destroy()
			jails[player] = nil
		end
	end)

	Remotes.AdminCommand.OnServerInvoke = function(player, text)
		if self:GetRank(player) <= 0 then
			return false, "You are not an admin"
		end
		return self:Execute(player, text)
	end

	Remotes.AdminData.OnServerInvoke = function(player, what)
		local rank = self:GetRank(player)
		if rank <= 0 then
			return nil
		end
		if what == "commands" then
			local list = {}
			for _, c in commands do
				table.insert(list, { Name = c.Name, Aliases = c.Aliases, Rank = c.Rank, Args = c.Args, Desc = c.Desc, Allowed = rank >= c.Rank })
			end
			return list
		elseif what == "logs" then
			return logs
		elseif what == "players" then
			local list = {}
			for _, p in Players:GetPlayers() do
				table.insert(list, {
					Name = p.Name,
					DisplayName = p.DisplayName,
					UserId = p.UserId,
					Rank = self:GetRank(p),
					Cash = p:GetAttribute("Cash") or 0,
					Rebirths = p:GetAttribute("Rebirths") or 0,
				})
			end
			return list
		end
		return nil
	end
end

return AdminService
