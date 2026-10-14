--[[
	MEGA TYCOON - Main configuration
	Everything you might want to tweak lives here: economy, floors, game passes,
	developer products, admins, disasters, secrets, music, minigames and codes.

	>>> BEFORE PUBLISHING <<<
	1. Create your Game Passes / Developer Products on the Creator Dashboard
	   and paste their IDs into GamePasses / Products below.
	2. Add your own UserId to Admin.Admins (the game creator is always Owner).
	3. Replace the music IDs with tracks you can use (Creator Store > Audio).
	4. Game Settings > Security > Enable Studio Access to API Services
	   (needed for saving in Studio).
	5. Set the place's Max Players to 8 (one tower per player).
]]

local Config = {}

Config.GameName = "MEGA TYCOON"
Config.Version = "2.1.0"

---------------------------------------------------------------------------
-- Data / economy
---------------------------------------------------------------------------
Config.DataStoreName = "MegaTycoon_PlayerData_v1"
Config.AutoSaveInterval = 90 -- seconds

Config.StartingCash = 100
Config.BaseWalkSpeed = 16
Config.MaxPlots = 8

Config.Tycoon = {
	Floors = 8,
	FloorHeight = 22,
	DropInterval = 2, -- seconds between drops of a dropper
	GeneratorCycle = 5, -- generators pay out every N seconds (visual)
	ConveyorSpeed = 12, -- studs per second (visual drops)
	-- Pacing: how long (in seconds of income) items cost, from the first item to
	-- the last one. Bigger = slower game. With the defaults a full 8-floor
	-- tower takes about 3 hours (much less with rebirths / passes).
	PaceStartSeconds = 4,
	PaceEndSeconds = 44,
	ButtonSlotsPerFloor = 12,
	MaxBuildPerTick = 30, -- items built per frame when a big tycoon loads
}

Config.OfflineEarnings = {
	Enabled = true,
	Percent = 0.25, -- earn 25% of your income while offline
	MaxHours = 8,
}

Config.Rebirth = {
	RequiredFloor = 5, -- the first rebirth costs as much as unlocking this floor
	CostGrowth = 4, -- each rebirth costs 4x more
	MultiplierPerRebirth = 0.5, -- each rebirth adds +0.5x to all income
	-- Rebirth ranks: reaching rebirth N earns that rank and its perk, forever.
	-- Perk kinds: Income (+x to the income multiplier), Start (extra cash after a
	-- rebirth), Offline (+% offline earnings, 0.05 = +5%), Quest / Gift (+% rewards),
	-- Speed (+walk speed). Perks of every rank earned so far add up.
	Ranks = {
		{ Rebirths = 1, Name = "Reborn", Icon = "🌱", Perks = { Start = 500 }, Text = "+500 starting cash after each rebirth" },
		{ Rebirths = 2, Name = "Hustler", Icon = "💼", Perks = { Speed = 2 }, Text = "+2 walk speed" },
		{ Rebirths = 3, Name = "Saver", Icon = "💤", Perks = { Offline = 0.05 }, Text = "+5% offline earnings" },
		{ Rebirths = 4, Name = "Quest Hunter", Icon = "📜", Perks = { Quest = 0.1 }, Text = "+10% quest rewards" },
		{ Rebirths = 5, Name = "Gift Magnet", Icon = "🎁", Perks = { Gift = 0.1 }, Text = "+10% playtime gifts" },
		{ Rebirths = 6, Name = "Mogul", Icon = "🏢", Perks = { Income = 0.5 }, Text = "+0.5x income" },
		{ Rebirths = 7, Name = "Sprinter", Icon = "👟", Perks = { Speed = 2 }, Text = "+2 more walk speed" },
		{ Rebirths = 8, Name = "Banker", Icon = "🏦", Perks = { Start = 5000, Offline = 0.05 }, Text = "+5,000 starting cash, +5% offline" },
		{ Rebirths = 9, Name = "Legend", Icon = "🏆", Perks = { Quest = 0.15, Gift = 0.15 }, Text = "+15% quest rewards and gifts" },
		{ Rebirths = 10, Name = "Mythic", Icon = "👑", Perks = { Income = 1, Offline = 0.1 }, Text = "+1x income, +10% offline" },
	},
}

---------------------------------------------------------------------------
-- Duo building
---------------------------------------------------------------------------
Config.Duo = {
	Enabled = true,
	InviteTimeout = 30,
}

---------------------------------------------------------------------------
-- Disasters (random server events). Nukes/meteors/tornadoes knock out
-- tycoon items for a while unless the tower has the Nuke Shield Dome.
---------------------------------------------------------------------------
Config.Disasters = {
	Enabled = true,
	FirstDelay = 240, -- seconds after the server starts
	MinInterval = 300,
	MaxInterval = 480,
	MainMapMaxY = 400, -- players above this (minigame arena) are not affected
	Nuke = {
		Weight = 1,
		Warning = 30, -- seconds to reach a bunker
		ShockSpeed = 320, -- studs per second
		KnockoutFraction = 0.25, -- share of an unshielded tower that gets wrecked
		KnockoutSeconds = 180,
	},
	Meteors = {
		Weight = 3,
		Duration = 40,
		Interval = 0.35,
		Radius = 12,
		Damage = 45,
		KnockoutSeconds = 90,
		CrystalChance = 0.3,
		CrystalIncomeSeconds = 20,
	},
	Tornado = {
		Weight = 3,
		Duration = 45,
		Radius = 22,
		Speed = 30,
		KnockoutSeconds = 60,
	},
	UFO = {
		Weight = 3,
		Duration = 45,
		Count = 3,
		AbductEvery = 6,
		CashEvery = 1.5,
		CashIncomeSeconds = 10,
	},
	Earthquake = {
		Weight = 2,
		Duration = 25,
		WaveEvery = 3, -- seconds between shocks
		Damage = 6, -- per shock, if you're not in a shelter
		KnockoutFraction = 0.03, -- share of an unshielded tower wrecked per shock
		KnockoutSeconds = 90,
		GeodeCount = 6, -- cash geodes pushed out of the ground
		GeodeIncomeSeconds = 15,
	},
}

---------------------------------------------------------------------------
-- Secrets hidden around the map. Each one gives cash and permanently builds
-- a secret relic in your tower (+5% income each, kept through rebirths).
---------------------------------------------------------------------------
Config.SecretRewards = {
	IncomeSeconds = 180,
	MinCash = 5_000,
	BonusPercent = 5,
}

Config.Secrets = {
	{ Id = "Board", Name = "Behind the Scenes", Hint = "Leaders always have something behind them...", Color = Color3.fromRGB(255, 200, 40), BadgeId = 0 },
	{ Id = "Bunker", Name = "Doomsday Stash", Hint = "Preppers hide snacks where it's safe from the bomb.", Color = Color3.fromRGB(150, 160, 170), BadgeId = 0 },
	{ Id = "Summit", Name = "Top of the World", Hint = "Climb the snowy mountain all the way up.", Color = Color3.fromRGB(220, 240, 255), BadgeId = 0 },
	{ Id = "Cave", Name = "Crystal Cave", Hint = "The mountain is hollow. Look for a gap behind the trees.", Color = Color3.fromRGB(150, 80, 255), BadgeId = 0 },
	{ Id = "LakeFloor", Name = "Sunken Treasure", Hint = "Hold your breath and dive to the bottom of the lake.", Color = Color3.fromRGB(0, 170, 255), BadgeId = 0 },
	{ Id = "Island", Name = "Castaway", Hint = "A lonely tree on a lonely island is hiding something.", Color = Color3.fromRGB(90, 220, 110), BadgeId = 0 },
	{ Id = "Obby", Name = "Shortcut Seeker", Hint = "Some obby platforms are almost invisible...", Color = Color3.fromRGB(255, 80, 160), BadgeId = 0 },
	{ Id = "Cloud", Name = "Head in the Clouds", Hint = "A strange pad in the east forest sends you flying.", Color = Color3.fromRGB(255, 255, 255), BadgeId = 0 },
	{ Id = "Edge", Name = "End of the World", Hint = "Walk until the world ends. Then check the corner.", Color = Color3.fromRGB(60, 60, 80), BadgeId = 0 },
	{ Id = "GiantTree", Name = "Tree House", Hint = "The biggest tree in the forest has a door.", Color = Color3.fromRGB(140, 90, 50), BadgeId = 0 },
	{ Id = "Graveyard", Name = "Spooky Secret", Hint = "Not everyone in the graveyard is resting.", Color = Color3.fromRGB(120, 255, 120), BadgeId = 0 },
	{ Id = "Waterfall", Name = "Behind the Falls", Hint = "Walk through the waterfall next to the mountain.", Color = Color3.fromRGB(120, 220, 255), BadgeId = 0 },
}

---------------------------------------------------------------------------
-- Monetization
-- Id = 0 means "not configured yet". While in Roblox Studio, buying an item
-- with Id 0 simulates the purchase so you can test everything for free.
---------------------------------------------------------------------------
Config.Monetization = {
	SimulateUnconfiguredInStudio = true,
}

Config.GamePasses = {
	DoubleCash = {
		Id = 0,
		Name = "2x Cash",
		Description = "Double ALL income, forever! Works for your duo partner too.",
		PriceHint = 299,
		Icon = "💵",
		Color = Color3.fromRGB(70, 200, 90),
		Order = 1,
	},
	AutoCollect = {
		Id = 0,
		Name = "Auto Collect",
		Description = "Cash goes straight to your wallet. No more vault!",
		PriceHint = 149,
		Icon = "🧲",
		Color = Color3.fromRGB(80, 160, 255),
		Order = 2,
	},
	FastDroppers = {
		Id = 0,
		Name = "Fast Droppers",
		Description = "All droppers drop 2x faster (2x dropper income).",
		PriceHint = 249,
		Icon = "⚡",
		Color = Color3.fromRGB(255, 200, 40),
		Order = 3,
	},
	VIP = {
		Id = 0,
		Name = "VIP",
		Description = "+50% cash, golden VIP chat tag, VIP aura & daily bonus x2.",
		PriceHint = 399,
		Icon = "👑",
		Color = Color3.fromRGB(255, 170, 0),
		Order = 4,
	},
	SuperSpeed = {
		Id = 0,
		Name = "Super Speed",
		Description = "Run 2x faster around the map (great for escaping nukes!).",
		PriceHint = 99,
		Icon = "👟",
		Color = Color3.fromRGB(255, 90, 160),
		Order = 5,
	},
	AutoBuild = {
		Id = 0,
		Name = "Auto Builder",
		Description = "Your tower buys its best affordable upgrade by itself. Turn it on/off in Settings.",
		PriceHint = 349,
		Icon = "🤖",
		Color = Color3.fromRGB(0, 210, 190),
		Order = 6,
	},
}

-- Automatic server-wide cash events (a reason to stay in the server)
Config.AutoEvents = {
	Enabled = true,
	EveryMinutes = 45, -- the first one starts this long after the server starts
	DurationMinutes = 5,
	Multiplier = 2,
}

-- Free income bonuses: Roblox Premium members, and friends playing together
-- (per friend in the server, up to MaxFriends). Shown in the HUD.
Config.Bonuses = {
	PremiumPercent = 10,
	FriendPercent = 10,
	MaxFriends = 5,
}

-- Auto Builder: how often it buys (seconds) and how many upgrades per go
Config.AutoBuild = {
	Interval = 2,
	PerTick = 1,
}

-- Cash products pay "Minutes" of your current income (never less than MinCash)
Config.Products = {
	CashSmall = {
		Id = 0,
		Name = "Pile of Cash",
		Description = "10 minutes of your income",
		PriceHint = 25,
		Icon = "💰",
		Minutes = 10,
		MinCash = 10_000,
		Order = 1,
	},
	CashMedium = {
		Id = 0,
		Name = "Bag of Cash",
		Description = "30 minutes of your income",
		PriceHint = 79,
		Icon = "💰",
		Minutes = 30,
		MinCash = 100_000,
		Order = 2,
	},
	CashLarge = {
		Id = 0,
		Name = "Vault of Cash",
		Description = "2 hours of your income",
		PriceHint = 249,
		Icon = "🏦",
		Minutes = 120,
		MinCash = 1_000_000,
		Order = 3,
	},
	CashHuge = {
		Id = 0,
		Name = "Cash Mountain",
		Description = "8 hours of your income!",
		PriceHint = 699,
		Icon = "⛰️",
		Minutes = 480,
		MinCash = 10_000_000,
		Order = 4,
	},
	Boost = {
		Id = 0,
		Name = "2x Boost (15 min)",
		Description = "Double income for 15 minutes. Stacks time!",
		PriceHint = 49,
		Icon = "🚀",
		BoostSeconds = 15 * 60,
		Order = 5,
	},
	InstantRepair = {
		Id = 0,
		Name = "Instant Repair",
		Description = "Fix every wrecked upgrade in your tower right now.",
		PriceHint = 29,
		Icon = "🔧",
		Repair = true,
		Order = 6,
	},
	LaunchNuke = {
		Id = 0,
		Name = "Launch a NUKE",
		Description = "Nuke the whole server! Everyone has 30s to find a bunker.",
		PriceHint = 199,
		Icon = "☢️",
		ServerEvent = "Nuke",
		Order = 7,
	},
	MeteorStorm = {
		Id = 0,
		Name = "Meteor Storm",
		Description = "Rain meteors on the server. They leave cash crystals!",
		PriceHint = 99,
		Icon = "☄️",
		ServerEvent = "Meteors",
		Order = 8,
	},
	CashRain = {
		Id = 0,
		Name = "Server Cash Rain",
		Description = "Make it rain cash for EVERYONE in the server!",
		PriceHint = 149,
		Icon = "🌧️",
		ServerEvent = "CashRain",
		Order = 9,
	},
}

---------------------------------------------------------------------------
-- Admin
-- Ranks: 0 = Player, 1 = Mod, 2 = Admin, 3 = HeadAdmin, 4 = Owner
---------------------------------------------------------------------------
Config.Admin = {
	Prefix = ";",
	CreatorIsOwner = true, -- the place owner (or group owner) is always Owner
	StudioEveryoneIsOwner = true, -- in Studio play-tests everyone is Owner
	Admins = {
		-- [123456789] = 4,
	},
	GroupId = 0, -- set to your group id to give ranks by group rank
	GroupRanks = {
		-- [255] = 4, [254] = 3, [200] = 2, [100] = 1,
	},
	BanDataStore = "MegaTycoon_Bans_v1",
}

---------------------------------------------------------------------------
-- Anti-cheat (server side). Every detection is a STRIKE: the player is kicked
-- and the evidence is saved. Strikes are shared between servers; the
-- StrikesToBan-th strike bans. Head Admins review the evidence and unban in
-- the admin panel (Anti-Cheat tab) or with ;unban. Staff of ExemptRank or
-- higher (Head Admin, Owner - everyone in Studio) are never checked.
---------------------------------------------------------------------------
Config.AntiCheat = {
	Enabled = true,
	StrikesToBan = 5,
	ExemptRank = 3,
	DataStore = "MegaTycoon_AntiCheat_v1",
	MaxEvidence = 10, -- evidence entries kept per player
	StrikeExpireDays = 30, -- a player's strikes are forgotten after this long without a new one
	RefreshSeconds = 60, -- how often a server re-reads the shared ban list
	-- running: Samples checks in a row (every Interval s) on the ground faster than
	-- WalkSpeed x Tolerance + Slack. Big jumps (> TeleportDistance) are teleports.
	Speed = { Interval = 0.25, Samples = 6, Tolerance = 1.6, Slack = 6, TeleportDistance = 80 },
	Fly = { Seconds = 10, MinFallSpeed = 15 }, -- in the air this long without falling
	Reach = { Margin = 20 }, -- studs beyond a touch's allowed distance that count as "far away"
	RemoteSpam = { PerSecond = 80, Seconds = 3 }, -- remote events per second, for this many seconds
	-- Threshold = score needed within Window seconds (each sign adds 1)
	Kinds = {
		Speed = { Title = "Speed hacking", Threshold = 1, Window = 1 },
		Fly = { Title = "Flying", Threshold = 1, Window = 1 },
		Teleport = { Title = "Teleporting", Threshold = 12, Window = 20 },
		Reach = { Title = "Grabbing things from far away", Threshold = 5, Window = 30 },
		RemoteSpam = { Title = "Spamming the server", Threshold = 1, Window = 1 },
		AdminRemote = { Title = "Using admin commands without permission", Threshold = 1, Window = 1 },
	},
}

Config.RankNames = {
	[0] = "Player",
	[1] = "Mod",
	[2] = "Admin",
	[3] = "Head Admin",
	[4] = "Owner",
}

---------------------------------------------------------------------------
-- Music / sounds
-- Replace these with any audio you have permission to use (search the
-- Creator Store for music uploaded by "Roblox" - those are free to use).
-- Tracks that fail to load are skipped automatically.
---------------------------------------------------------------------------
Config.Music = {
	DefaultVolume = 0.35,
	Lobby = {
		{ Id = "rbxassetid://1837849285", Name = "Tycoon Groove" },
		{ Id = "rbxassetid://1843463175", Name = "Sunny Day" },
		{ Id = "rbxassetid://1839246711", Name = "Chill Vibes" },
		{ Id = "rbxassetid://1845756489", Name = "Money Maker" },
	},
	Minigame = {
		{ Id = "rbxassetid://1838028467", Name = "Minigame Rush" },
		{ Id = "rbxassetid://1836057733", Name = "Adrenaline" },
	},
	Loading = { Id = "rbxassetid://1846368080", Name = "Loading" },
}

-- Built-in engine sounds (always available, no upload needed).
-- Siren: put an audio id here for a real air-raid siren; empty = synthesized.
Config.Sounds = {
	Click = "rbxasset://sounds/clickfast.wav",
	Hover = "rbxasset://sounds/button.wav",
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	Error = "rbxasset://sounds/uuhhh.mp3",
	Cash = "rbxasset://sounds/electronicpingshort.wav",
	Notify = "rbxasset://sounds/button.wav",
	Rebirth = "rbxasset://sounds/victory.wav",
	Win = "rbxasset://sounds/victory.wav",
	Countdown = "rbxasset://sounds/clickfast.wav",
	Whoosh = "rbxasset://sounds/swordslash.wav",
	Coin = "rbxasset://sounds/electronicpingshort.wav",
	Boom = "rbxasset://sounds/collide.wav",
	Siren = "",
}

---------------------------------------------------------------------------
-- Minigames (rewards are "seconds of your income", with a minimum)
---------------------------------------------------------------------------
Config.Minigames = {
	Enabled = true,
	Intermission = 150, -- seconds between minigames
	JoinTime = 20, -- seconds players get to press "Join"
	MinPlayers = 1,
	ArenaCenter = Vector3.new(0, 600, 0),
	Games = {
		CoinRush = {
			DisplayName = "Coin Rush",
			Description = "Grab as many coins as you can in 45 seconds!",
			Duration = 45,
			CoinIncomeSeconds = 3,
			CoinMin = 250,
			WinnerIncomeSeconds = 90,
			WinnerMin = 5000,
		},
		FallingTiles = {
			DisplayName = "Falling Tiles",
			Description = "Tiles fall after you touch them. Be the last one standing!",
			Duration = 90,
			SurviveIncomeSeconds = 60,
			SurviveMin = 3000,
			WinnerIncomeSeconds = 120,
			WinnerMin = 10000,
		},
		MeteorShower = {
			DisplayName = "Meteor Dodge",
			Description = "Dodge the meteors raining from the sky for 60 seconds!",
			Duration = 60,
			SurviveIncomeSeconds = 90,
			SurviveMin = 6000,
			WinnerIncomeSeconds = 60,
			WinnerMin = 4000,
		},
		LavaRise = {
			DisplayName = "Lava Rise",
			Description = "The lava is rising! Climb the spiral tower - last ones standing win.",
			Duration = 60,
			RiseSpeed = 1.5, -- studs per second
			SurviveIncomeSeconds = 90,
			SurviveMin = 5000,
			WinnerIncomeSeconds = 90,
			WinnerMin = 6000,
		},
	},
}

---------------------------------------------------------------------------
-- Obby
---------------------------------------------------------------------------
Config.Obby = {
	RewardIncomeSeconds = 300,
	MinReward = 15_000,
	Cooldown = 10 * 60, -- seconds between rewarded completions
}

---------------------------------------------------------------------------
-- Daily rewards (index = streak day, loops after the last one).
-- You get the bigger of: the fixed amount, or N minutes of your income.
---------------------------------------------------------------------------
Config.Daily = {
	Cooldown = 20 * 60 * 60, -- 20 hours
	StreakResetAfter = 48 * 60 * 60,
	Rewards = { 1_000, 2_500, 5_000, 10_000, 20_000, 40_000, 100_000 },
	IncomeMinutes = { 2, 3, 5, 8, 12, 18, 30 },
}

---------------------------------------------------------------------------
-- Quests: everyone has 3 at a time; claim one and a new one appears.
-- Rewards = the bigger of RewardSeconds of your income or MinCash x (1 + rebirths).
-- Text uses %d / %s for the target.
---------------------------------------------------------------------------
Config.Quests = {
	Enabled = true,
	Active = 3,
	Types = {
		Buy = { Text = "Buy %d upgrades", Targets = { 5, 8, 12 }, RewardSeconds = 90, MinCash = 400 },
		Earn = { Text = "Earn %s from your tower", IncomeSeconds = { 120, 240, 400 }, MinTarget = 500, RewardSeconds = 120, MinCash = 500 },
		Collect = { Text = "Collect your vault %d times", Targets = { 3, 5 }, RewardSeconds = 60, MinCash = 300 },
		Floor = { Text = "Unlock %s", RewardSeconds = 240, MinCash = 2000, BoostSeconds = 300 },
		Secret = { Text = "Find a hidden secret", RewardSeconds = 180, MinCash = 2500, BoostSeconds = 300 },
		Obby = { Text = "Finish the obby", RewardSeconds = 150, MinCash = 2000 },
		Minigame = { Text = "Play a minigame", RewardSeconds = 120, MinCash = 1500 },
		Survive = { Text = "Survive a disaster", RewardSeconds = 150, MinCash = 1500 },
	},
}

---------------------------------------------------------------------------
-- Playtime gifts: stay in the server to unlock them (resets every session).
-- Each pays the bigger of IncomeMinutes of income or MinCash x (1 + rebirths).
---------------------------------------------------------------------------
Config.Gifts = {
	Enabled = true,
	Minutes = { 5, 10, 20, 30, 45, 60 }, -- minutes PLAYED today (saved; rejoining doesn't restart it)
	IncomeMinutes = { 1, 2, 3, 5, 8, 12 },
	MinCash = { 500, 1_000, 2_000, 4_000, 8_000, 15_000 },
	FinalBoostSeconds = 10 * 60, -- the last gift also gives a 2x boost
}

---------------------------------------------------------------------------
-- Personal shield: for Seconds you take no damage from disasters (like being
-- in a bunker, anywhere). After using it you wait Cooldown seconds (counted
-- from the moment you activated it). Both are saved, so rejoining doesn't help.
---------------------------------------------------------------------------
Config.Shield = {
	Enabled = true,
	Seconds = 90,
	Cooldown = 15 * 60,
}

---------------------------------------------------------------------------
-- Lucky Wheel: one free spin every CooldownMinutes (saved, so it counts while
-- you're offline). A prize is picked by Weight. Cash prizes pay the bigger of
-- Minutes of income or MinCash x (1 + rebirths); BoostSeconds gives a 2x boost.
---------------------------------------------------------------------------
Config.Wheel = {
	Enabled = true,
	CooldownMinutes = 30,
	SpinSeconds = 4.5, -- how long the reel animation runs
	Segments = {
		{ Name = "Pocket Change", Icon = "💵", Minutes = 1, MinCash = 400, Weight = 28, Color = Color3.fromRGB(60, 170, 90) },
		{ Name = "Cash Stack", Icon = "💰", Minutes = 5, MinCash = 2_000, Weight = 22, Color = Color3.fromRGB(40, 150, 200) },
		{ Name = "Cash Bag", Icon = "👜", Minutes = 15, MinCash = 7_000, Weight = 12, Color = Color3.fromRGB(150, 90, 230) },
		{ Name = "2x Boost 5m", Icon = "⚡", BoostSeconds = 5 * 60, Weight = 16, Color = Color3.fromRGB(240, 170, 20) },
		{ Name = "2x Boost 15m", Icon = "🔥", BoostSeconds = 15 * 60, Weight = 8, Color = Color3.fromRGB(235, 100, 40) },
		{ Name = "Mega Cash", Icon = "💎", Minutes = 60, MinCash = 40_000, Weight = 3, Color = Color3.fromRGB(60, 210, 230) },
		{ Name = "JACKPOT", Icon = "🎰", Minutes = 180, MinCash = 150_000, Weight = 1, Color = Color3.fromRGB(255, 70, 110) },
	},
}

---------------------------------------------------------------------------
-- Codes (case-insensitive). Remove a code or set Expired = true to disable.
---------------------------------------------------------------------------
Config.Codes = {
	RELEASE = { Cash = 1_000, IncomeMinutes = 2 },
	MEGATYCOON = { Cash = 5_000, IncomeMinutes = 5 },
	BOOST = { BoostSeconds = 10 * 60 },
	THANKYOU = { Cash = 25_000, IncomeMinutes = 10 },
	NUKE = { Cash = 10_000, IncomeMinutes = 5 },
	DUO = { Cash = 10_000, IncomeMinutes = 5 },
}

---------------------------------------------------------------------------
-- Day / night cycle
---------------------------------------------------------------------------
Config.DayNight = {
	Enabled = true,
	MinutesPerDay = 14,
	StartTime = 13,
}

---------------------------------------------------------------------------
-- Loading screen tips
---------------------------------------------------------------------------
Config.Tips = {
	"Your tower has 8 floors and over 500 upgrades. Can you max it out?",
	"Use the elevator (or the FLOORS button) to move between floors.",
	"Invite a friend with the DUO button and build one tower together!",
	"NUKE INCOMING? Follow the green beam to the nearest bunker!",
	"The Nuke Shield Dome (floor 2) protects your tower from disasters.",
	"There are 12 secrets hidden around the map. Each one boosts your income!",
	"Upgraders multiply the value of every drop on their floor.",
	"Rebirth to reset your tower and earn a permanent cash multiplier.",
	"Minigames start every few minutes - join them for big rewards!",
	"You earn cash while offline. Come back to collect it!",
	"Codes can be redeemed in the Codes menu. Try RELEASE!",
	"Finish quests (bottom right) for big rewards - a new one appears every time you claim!",
	"Stay in the server: playtime gifts open during your first hour.",
	"Follow the glowing beam - it points to the next upgrade you can afford.",
	"Playing with friends? Every friend in the server gives +10% income!",
	"Every 45 minutes there's a 2x CASH HOUR for everyone.",
	"Earthquakes dig up cash geodes - grab them before they vanish!",
}

-- the highest rebirth rank reached with `rebirths` rebirths: index, rank (nil before the first)
function Config.RebirthRank(rebirths: number): (number?, any?)
	local index
	for i, rank in Config.Rebirth.Ranks do
		if rebirths >= rank.Rebirths then
			index = i
		end
	end
	return index, index and Config.Rebirth.Ranks[index]
end

-- total of one perk kind over every rank earned with `rebirths` rebirths
function Config.RebirthPerk(rebirths: number, kind: string): number
	local total = 0
	for _, rank in Config.Rebirth.Ranks do
		if rebirths >= rank.Rebirths then
			total += rank.Perks[kind] or 0
		end
	end
	return total
end

return Config
