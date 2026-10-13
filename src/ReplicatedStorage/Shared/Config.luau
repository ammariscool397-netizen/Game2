--[[
	MEGA TYCOON - Main configuration
	Everything you might want to tweak lives here: economy, game passes,
	developer products, admins, music, minigames, codes and daily rewards.

	>>> BEFORE PUBLISHING <<<
	1. Create your Game Passes / Developer Products on the Creator Dashboard
	   and paste their IDs into GamePasses / Products below.
	2. Add your own UserId to Admin.Admins (the game creator is always Owner).
	3. Replace the music IDs with tracks you can use (Creator Store > Audio).
	4. Game Settings > Security > Enable Studio Access to API Services
	   (needed for saving in Studio).
]]

local Config = {}

Config.GameName = "MEGA TYCOON"
Config.Version = "1.0.0"

---------------------------------------------------------------------------
-- Data / economy
---------------------------------------------------------------------------
Config.DataStoreName = "MegaTycoon_PlayerData_v1"
Config.AutoSaveInterval = 90 -- seconds

Config.StartingCash = 100
Config.BaseWalkSpeed = 16

Config.Rebirth = {
	BaseCost = 2_500_000,
	CostGrowth = 2.5, -- cost = BaseCost * CostGrowth ^ rebirths
	MultiplierPerRebirth = 0.5, -- each rebirth adds +0.5x to all income
}

function Config.GetRebirthCost(rebirths: number): number
	return math.floor(Config.Rebirth.BaseCost * (Config.Rebirth.CostGrowth ^ rebirths))
end

Config.ConveyorSpeed = 9
Config.DropLifetime = 25
Config.MaxPlots = 6

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
		Description = "Double ALL income, forever!",
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
		Description = "All droppers drop 2x faster.",
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
		Description = "Run 2x faster around the map.",
		PriceHint = 99,
		Icon = "👟",
		Color = Color3.fromRGB(255, 90, 160),
		Order = 5,
	},
}

Config.Products = {
	CashSmall = {
		Id = 0,
		Name = "Pile of Cash",
		Description = "+$10K (scales with rebirths)",
		PriceHint = 25,
		Icon = "💰",
		Cash = 10_000,
		Order = 1,
	},
	CashMedium = {
		Id = 0,
		Name = "Bag of Cash",
		Description = "+$100K (scales with rebirths)",
		PriceHint = 99,
		Icon = "💰",
		Cash = 100_000,
		Order = 2,
	},
	CashLarge = {
		Id = 0,
		Name = "Vault of Cash",
		Description = "+$1M (scales with rebirths)",
		PriceHint = 299,
		Icon = "🏦",
		Cash = 1_000_000,
		Order = 3,
	},
	CashHuge = {
		Id = 0,
		Name = "Cash Mountain",
		Description = "+$10M (scales with rebirths)",
		PriceHint = 799,
		Icon = "⛰️",
		Cash = 10_000_000,
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
	CashRain = {
		Id = 0,
		Name = "Server Cash Rain",
		Description = "Make it rain cash for EVERYONE in the server!",
		PriceHint = 149,
		Icon = "🌧️",
		ServerEvent = "CashRain",
		Order = 6,
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

-- Built-in engine sounds (always available, no upload needed)
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
}

---------------------------------------------------------------------------
-- Minigames
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
			CoinValue = 250, -- cash per coin (x (1 + rebirths))
			WinnerBonus = 5000,
		},
		FallingTiles = {
			DisplayName = "Falling Tiles",
			Description = "Tiles fall after you touch them. Be the last one standing!",
			Duration = 90,
			SurviveReward = 3000,
			WinnerBonus = 10000,
		},
		MeteorShower = {
			DisplayName = "Meteor Shower",
			Description = "Dodge the meteors raining from the sky for 60 seconds!",
			Duration = 60,
			SurviveReward = 6000,
			WinnerBonus = 4000,
		},
	},
}

---------------------------------------------------------------------------
-- Obby
---------------------------------------------------------------------------
Config.Obby = {
	Reward = 15_000, -- x (1 + rebirths)
	Cooldown = 10 * 60, -- seconds between rewarded completions
}

---------------------------------------------------------------------------
-- Daily rewards (index = streak day, loops after the last one)
---------------------------------------------------------------------------
Config.Daily = {
	Cooldown = 20 * 60 * 60, -- 20 hours
	StreakResetAfter = 48 * 60 * 60,
	Rewards = { 1_000, 2_500, 5_000, 10_000, 20_000, 40_000, 100_000 },
}

---------------------------------------------------------------------------
-- Codes (case-insensitive). Remove a code or set Expired = true to disable.
---------------------------------------------------------------------------
Config.Codes = {
	RELEASE = { Cash = 1_000 },
	MEGATYCOON = { Cash = 5_000 },
	BOOST = { BoostSeconds = 10 * 60 },
	THANKYOU = { Cash = 25_000 },
}

---------------------------------------------------------------------------
-- Loading screen tips
---------------------------------------------------------------------------
Config.Tips = {
	"Step on the green buttons in your tycoon to buy upgrades!",
	"Upgraders multiply the value of every drop that passes through.",
	"Rebirth to reset your tycoon and earn a permanent cash multiplier.",
	"Minigames start every few minutes - join them for big rewards!",
	"Finish the obby next to the lobby for a huge cash prize.",
	"Claim your daily reward every day to build your streak.",
	"Codes can be redeemed in the Codes menu. Try RELEASE!",
	"Don't forget to collect your vault!",
}

return Config
