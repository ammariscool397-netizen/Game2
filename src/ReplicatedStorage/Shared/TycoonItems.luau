--[[
	TycoonItems - generates every buyable item of the 8-floor tower
	(8 floors x 62 upgrades + 6 rooftop items + 12 secret relics = 514).

	Costs and values are CALIBRATED automatically: walking the items in their
	natural order, each item costs "N seconds of the income you would have at
	that point" (Config.Tycoon.PaceStartSeconds -> PaceEndSeconds), and each
	dropper / generator adds a fixed share of income. Change the pace in
	Config and every price rescales consistently.

	Positions are in FLOOR-LOCAL space: X = left/right (-42..42),
	Z = front/back (-42 is the front, facing the lobby), Y = up from the floor.
	Secret relics use PLOT-LOCAL space (front yard).

	Kinds: Unlock, Dropper, Mk2, Upgrader, Generator, Conveyor, Boost, Decor,
	       Wall, Special, Trophy, Roof, Secret
]]

local Config = require(script.Parent.Config)

local TC = Config.Tycoon
local FLOORS = TC.Floors
local OVERLAP = 40 -- a new floor unlocks around item 40 of the previous floor

local Items = {}

---------------------------------------------------------------------------
-- Themes (one per floor)
---------------------------------------------------------------------------
local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Items.Themes = {
	{
		Name = "Starter Factory", Adj = "Factory",
		Primary = rgb(150, 155, 165), Secondary = rgb(70, 75, 85), Accent = rgb(255, 140, 0),
		Floor = Enum.Material.DiamondPlate, Wall = Enum.Material.Brick, Drop = Enum.Material.Metal, Hue = 0.08,
		Droppers = { "Scrap", "Bolt", "Gear", "Pipe", "Steel", "Copper", "Brass", "Chrome", "Titanium", "Turbo" },
		Generators = { "Coin Press", "Bill Printer", "Steam Engine", "Cash Furnace", "Gear Spinner", "Money Compressor", "Smelter", "Mega Press" },
		Special = "Panic Bunker", SpecialKind = "Bunker",
	},
	{
		Name = "Gold Mine", Adj = "Golden",
		Primary = rgb(200, 160, 60), Secondary = rgb(110, 80, 45), Accent = rgb(255, 215, 0),
		Floor = Enum.Material.Slate, Wall = Enum.Material.Rock, Drop = Enum.Material.Foil, Hue = 0.13,
		Droppers = { "Pebble", "Nugget", "Ore", "Gold Bar", "Gold Coin", "Gold Brick", "Treasure", "Royal", "Midas", "Golden Idol" },
		Generators = { "Mine Cart", "Drill Rig", "Gold Sifter", "Ore Crusher", "Pickaxe Bot", "Gold Smelter", "Dynamite Crate", "Golden Drill" },
		Special = "Nuke Shield Dome", SpecialKind = "Shield",
	},
	{
		Name = "Jungle Greenhouse", Adj = "Jungle",
		Primary = rgb(70, 170, 80), Secondary = rgb(90, 65, 40), Accent = rgb(170, 255, 90),
		Floor = Enum.Material.Grass, Wall = Enum.Material.Wood, Drop = Enum.Material.Grass, Hue = 0.3,
		Droppers = { "Seed", "Sprout", "Leaf", "Vine", "Bamboo", "Coconut", "Mango", "Orchid", "Venus Trap", "Ancient Tree" },
		Generators = { "Money Tree", "Cash Flower", "Sprinkler", "Compost Bin", "Bee Hive", "Mushroom Farm", "Water Wheel", "Jungle Totem" },
		Special = "Money Fountain", SpecialKind = "Bonus",
	},
	{
		Name = "Crystal Lab", Adj = "Crystal",
		Primary = rgb(120, 200, 230), Secondary = rgb(60, 50, 110), Accent = rgb(190, 90, 255),
		Floor = Enum.Material.Marble, Wall = Enum.Material.Glass, Drop = Enum.Material.Glass, Hue = 0.55,
		Droppers = { "Quartz", "Amethyst", "Topaz", "Sapphire", "Emerald", "Ruby", "Opal", "Diamond", "Prism", "Void Crystal" },
		Generators = { "Growth Tank", "Laser Cutter", "Plasma Coil", "Particle Mixer", "Tesla Tower", "Quantum PC", "Hologram Core", "Crystal Reactor" },
		Special = "Diamond Vault", SpecialKind = "Bonus",
	},
	{
		Name = "Volcano Forge", Adj = "Molten",
		Primary = rgb(200, 70, 40), Secondary = rgb(50, 40, 40), Accent = rgb(255, 120, 0),
		Floor = Enum.Material.Basalt, Wall = Enum.Material.CrackedLava, Drop = Enum.Material.CrackedLava, Hue = 0.03,
		Droppers = { "Ember", "Magma", "Obsidian", "Lava", "Fire Opal", "Inferno", "Phoenix", "Dragonstone", "Hellfire", "Volcano Core" },
		Generators = { "Lava Pump", "Forge Anvil", "Fire Pit", "Magma Turbine", "Dragon Furnace", "Obsidian Press", "Fire Elemental", "Volcano Vent" },
		Special = "Lava Reactor", SpecialKind = "Bonus",
	},
	{
		Name = "Ice Palace", Adj = "Frozen",
		Primary = rgb(200, 235, 255), Secondary = rgb(120, 170, 220), Accent = rgb(0, 220, 255),
		Floor = Enum.Material.Ice, Wall = Enum.Material.Glacier, Drop = Enum.Material.Ice, Hue = 0.52,
		Droppers = { "Snowflake", "Icicle", "Frost", "Glacier", "Aurora", "Blizzard", "Frozen Gem", "Ice Crown", "Polar Star", "Absolute Zero" },
		Generators = { "Snow Machine", "Ice Sculptor", "Frost Generator", "Penguin Bank", "Aurora Projector", "Glacier Drill", "Yeti Treadmill", "Ice Throne" },
		Special = "Ice Dragon Statue", SpecialKind = "Bonus",
	},
	{
		Name = "Cyber City", Adj = "Neon",
		Primary = rgb(40, 40, 60), Secondary = rgb(20, 20, 30), Accent = rgb(255, 0, 200),
		Floor = Enum.Material.SmoothPlastic, Wall = Enum.Material.Metal, Drop = Enum.Material.Neon, Hue = 0.85,
		Droppers = { "Byte", "Pixel", "Circuit", "Chip", "Neon", "Hologram", "Cyber", "Quantum", "Mainframe", "AI Core" },
		Generators = { "Server Rack", "Crypto Miner", "Arcade Cabinet", "Neon Billboard", "Drone Dock", "Data Center", "Robot Arm", "Supercomputer" },
		Special = "Hologram Tower", SpecialKind = "Bonus",
	},
	{
		Name = "Galaxy Penthouse", Adj = "Cosmic",
		Primary = rgb(60, 30, 100), Secondary = rgb(15, 10, 30), Accent = rgb(140, 120, 255),
		Floor = Enum.Material.Glass, Wall = Enum.Material.Glass, Drop = Enum.Material.Neon, Hue = 0.72,
		Droppers = { "Stardust", "Comet", "Meteorite", "Moon Rock", "Planet", "Nebula", "Supernova", "Black Hole", "Galaxy", "Universe" },
		Generators = { "Star Forge", "Rocket Pad", "Alien Reactor", "Wormhole", "Satellite", "Space Bank", "Gravity Well", "Big Bang Machine" },
		Special = "Galaxy Portal", SpecialKind = "Bonus",
	},
}

Items.DecorNames = {
	"Crate Stack", "Barrel", "Lamp", "Potted Plant", "Bench", "Table", "Rug", "Shelf", "Statue",
	"Banner", "TV Screen", "Mini Fountain", "Crystal", "Money Pile", "Light Pillar", "Couch", "Vending Machine",
}
Items.WallNames = { "Left Wall", "Right Wall", "Back Wall", "Front Windows", "Corner Pillars", "Neon Trim" }
Items.WallSides = { "Left", "Right", "Back", "Front", "Pillars", "Trim" }
Items.UpgraderNames = { "Polisher", "Refiner", "Enchanter", "Supercharger" }
Items.UpgraderMult = { 1.2, 1.35, 1.5, 1.75 }
Items.BoostNames = { "Power Booster", "Mega Booster", "Ultra Booster" }
Items.BoostMult = { 1.25, 1.5, 2 }
Items.ConveyorNames = { "Fast Conveyor", "Turbo Conveyor" }

Items.DecorBonus = 0.02 -- +2% floor income each
Items.WallBonus = 0.01 -- +1% floor income each
Items.ConveyorBonus = 0.15 -- +15% floor drop income each
Items.SpecialBonus = 0.08 -- +8% total income (specials & trophies)
Items.RoofBonus = 0.10
Items.SecretBonus = (Config.SecretRewards.BonusPercent or 5) / 100

-- Floor-local layout
Items.DropperX = {}
for k = 1, 10 do
	Items.DropperX[k] = -35 + (k - 1) * 5.6
end
Items.UpgraderX = { 20, 24.5, 29, 33.5 }
Items.BeltZ = 8
Items.BeltStartX = -38
Items.BeltEndX = 35
Items.GeneratorPos = {}
for k = 1, 8 do
	Items.GeneratorPos[k] = Vector3.new(-35 + (k - 1) * 10, 0, 30)
end
Items.DecorPos = {
	Vector3.new(-24, 0, -38), Vector3.new(-14, 0, -38), Vector3.new(14, 0, -38), Vector3.new(24, 0, -38),
	Vector3.new(-34, 0, -6), Vector3.new(-24, 0, -6), Vector3.new(-14, 0, -6), Vector3.new(0, 0, -6), Vector3.new(14, 0, -6), Vector3.new(24, 0, -6),
	Vector3.new(-36, 0, 20), Vector3.new(-24, 0, 20), Vector3.new(-12, 0, 20), Vector3.new(0, 0, 20), Vector3.new(12, 0, 20), Vector3.new(24, 0, 20), Vector3.new(36, 0, 20),
}
Items.BoostPos = { Vector3.new(-20, 15, 39.4), Vector3.new(0, 15, 39.4), Vector3.new(20, 15, 39.4) }
Items.SpecialPos = Vector3.new(35.5, 0, -37)
Items.TrophyPos = Vector3.new(0, 13, 36)
Items.ElevatorPos = Vector3.new(-37, 0, -37)
Items.VaultPadPos = Vector3.new(37, 0, -4)
Items.CollectorPos = Vector3.new(37, 0, Items.BeltZ)
Items.ButtonSlots = {}
for row = 0, 1 do
	for col = 0, 5 do
		table.insert(Items.ButtonSlots, Vector3.new(-27 + col * 10.8, 0, -20 - row * 10))
	end
end
Items.RoofPos = {
	Vector3.new(0, 0, 0), -- helipad
	Vector3.new(-30, 0, 30), -- antenna
	Vector3.new(25, 0, 25), -- pool
	Vector3.new(0, 0, -36), -- billboard
	Vector3.new(-30, 0, -24), -- fireworks
	Vector3.new(28, 0, -20), -- crown
}
Items.RoofNames = { "Rooftop Helipad", "Giant Antenna", "Rooftop Pool", "Mega Billboard", "Fireworks Launcher", "Golden Crown" }
Items.RoofModels = { "Helipad", "Antenna", "Pool", "Billboard", "Fireworks", "Crown" }
-- secret relics sit in the front yard of the plot (plot-local)
Items.SecretPos = {}
for i, x in { -10, 10, -18, 18, -26, 26, -34, 34, -42, 42, -50, 50 } do
	Items.SecretPos[i] = Vector3.new(x, 0, -47)
end

---------------------------------------------------------------------------
-- Per-floor sequence (62 items)
---------------------------------------------------------------------------
local SEQ = {
	"Unlock", "D1", "W1", "D2", "Decor", "D3", "G1", "U1", "D4", "Decor",
	"M1", "D5", "G2", "Decor", "M2", "W2", "D6", "U2", "G3", "Decor",
	"M3", "D7", "C1", "Decor", "G4", "M4", "D8", "B1", "Decor", "W3",
	"M5", "G5", "D9", "U3", "Decor", "M6", "Special", "Decor", "G6", "D10",
	"M7", "Decor", "W4", "B2", "G7", "Decor", "M8", "C2", "Decor", "U4",
	"G8", "M9", "Decor", "W5", "Decor", "M10", "B3", "Decor", "W6", "Decor",
	"Decor", "Trophy",
}
Items.Sequence = SEQ
Items.PerFloor = #SEQ

local List = {}
local ById = {}

local function add(item)
	table.insert(List, item)
	ById[item.Id] = item
	return item
end

for F = 1, FLOORS do
	local theme = Items.Themes[(F - 1) % #Items.Themes + 1]
	local decorCount = 0
	local ids = {}
	for i, code in SEQ do
		local id = "F" .. F .. "_" .. i
		ids[i] = id
		local item: any = { Id = id, Floor = F, Index = i, Pos = (F - 1) * OVERLAP + i, Theme = theme }
		local letter, number = code:match("^(%a)(%d+)$")
		number = tonumber(number)
		if code == "Unlock" then
			item.Kind = "Unlock"
			item.Name = F == 1 and "Starter Base" or ("Floor " .. F .. ": " .. theme.Name)
		elseif code == "Decor" then
			decorCount += 1
			item.Kind = "Decor"
			item.Slot = decorCount
			item.Model = decorCount
			item.Name = theme.Adj .. " " .. Items.DecorNames[decorCount]
			item.LocalPos = Items.DecorPos[decorCount]
		elseif code == "Special" then
			item.Kind = "Special"
			item.Effect = theme.SpecialKind
			item.Name = theme.Special
			item.LocalPos = Items.SpecialPos
		elseif code == "Trophy" then
			item.Kind = "Trophy"
			item.Name = "Floor " .. F .. " Trophy"
			item.LocalPos = Items.TrophyPos
		elseif letter == "D" then
			item.Kind = "Dropper"
			item.Slot = number
			item.Tier = number
			item.Name = theme.Droppers[number] .. " Dropper"
			item.LocalPos = Vector3.new(Items.DropperX[number], 0, Items.BeltZ)
			item.Interval = TC.DropInterval
		elseif letter == "M" then
			item.Kind = "Mk2"
			item.Slot = number
			item.Name = theme.Droppers[number] .. " Dropper Mk II"
			item.LocalPos = Vector3.new(Items.DropperX[number], 0, Items.BeltZ)
			item.Multiplier = 2
		elseif letter == "U" then
			item.Kind = "Upgrader"
			item.Slot = number
			item.Multiplier = Items.UpgraderMult[number]
			item.Name = theme.Adj .. " " .. Items.UpgraderNames[number] .. " (x" .. Items.UpgraderMult[number] .. ")"
			item.LocalPos = Vector3.new(Items.UpgraderX[number], 0, Items.BeltZ)
		elseif letter == "G" then
			item.Kind = "Generator"
			item.Slot = number
			item.Name = theme.Generators[number]
			item.LocalPos = Items.GeneratorPos[number]
			item.Cycle = TC.GeneratorCycle
		elseif letter == "C" then
			item.Kind = "Conveyor"
			item.Slot = number
			item.Name = Items.ConveyorNames[number]
		elseif letter == "B" then
			item.Kind = "Boost"
			item.Slot = number
			item.Multiplier = Items.BoostMult[number]
			item.Name = Items.BoostNames[number] .. " (x" .. Items.BoostMult[number] .. ")"
			item.LocalPos = Items.BoostPos[number]
		elseif letter == "W" then
			item.Kind = "Wall"
			item.Slot = number
			item.Side = Items.WallSides[number]
			item.Name = theme.Adj .. " " .. Items.WallNames[number]
		end
		-- requirements: the item 3 steps earlier on this floor (so ~3 buttons show at a time)
		local requires = {}
		if i >= 2 then
			table.insert(requires, ids[math.max(1, i - 3)])
		elseif F > 1 then
			table.insert(requires, "F" .. (F - 1) .. "_40") -- previous floor's 10th dropper
		end
		item.Requires = requires
		add(item)
	end
	-- Mk II upgrades require their dropper
	for i, code in SEQ do
		local n = code:match("^M(%d+)$")
		if n then
			local dropperIndex = table.find(SEQ, "D" .. n)
			local item = ById[ids[i]]
			item.Dropper = ids[dropperIndex]
			table.insert(item.Requires, ids[dropperIndex])
		end
	end
end

-- rooftop items (need floor 8)
for k = 1, #Items.RoofNames do
	add({
		Id = "Roof_" .. k,
		Floor = FLOORS + 1,
		Index = k,
		Pos = FLOORS * OVERLAP + 62 + k,
		Kind = "Roof",
		Model = Items.RoofModels[k],
		Name = Items.RoofNames[k],
		LocalPos = Items.RoofPos[k],
		Requires = { k == 1 and ("F" .. FLOORS .. "_1") or ("Roof_" .. (k - 1)) },
		Theme = Items.Themes[FLOORS],
	})
end

-- secret relics (free, unlocked by finding secrets, survive rebirths)
for i, secret in Config.Secrets do
	add({
		Id = "Secret_" .. secret.Id,
		Floor = 0,
		Index = i,
		Pos = math.huge,
		Kind = "Secret",
		SecretId = secret.Id,
		Name = secret.Name .. " Relic",
		Color = secret.Color,
		LocalPos = Items.SecretPos[i],
		Requires = {},
		Cost = 0,
	})
end

---------------------------------------------------------------------------
-- Calibration (see header). Walk items in natural order.
---------------------------------------------------------------------------
local function nice(x: number): number
	if x < 100 then
		return math.max(1, math.floor(x + 0.5))
	end
	local p = 10 ^ (math.floor(math.log10(x)) - 1)
	return math.floor(x / p + 0.5) * p
end

do
	local order = {}
	for _, item in List do
		if item.Kind ~= "Secret" then
			table.insert(order, item)
		end
	end
	table.sort(order, function(a, b)
		if a.Pos ~= b.Pos then
			return a.Pos < b.Pos
		end
		return a.Floor < b.Floor
	end)

	local N = #order
	local floors = {}
	for F = 1, FLOORS + 1 do
		floors[F] = { dr = 0, gr = 0, um = 1, bm = 1, dec = 0, wall = 0, conv = 0, drops = {} }
	end
	local bonus = 0
	local function floorIncome(f)
		return (f.dr * f.um * (1 + Items.ConveyorBonus * f.conv) + f.gr) * f.bm * (1 + Items.DecorBonus * f.dec + Items.WallBonus * f.wall)
	end
	local function total()
		local sum = 0
		for _, f in floors do
			sum += floorIncome(f)
		end
		return sum * (1 + bonus)
	end
	local BASE = 4
	local lastCost = 0
	for n, item in order do
		local income = math.max(total(), BASE)
		local x = (n - 1) / N
		local T = TC.PaceStartSeconds + (TC.PaceEndSeconds - TC.PaceStartSeconds) * x ^ 1.2
		local cost
		if item.Floor == 1 and item.Kind == "Unlock" then
			cost = 0
		elseif item.Floor == 1 and item.Index == 2 then
			cost = 25
		else
			cost = nice(math.max(income * T, lastCost * 1.04))
		end
		if cost > 0 then
			lastCost = cost
		end
		item.Cost = cost

		local f = floors[item.Floor]
		local mult = f.um * (1 + Items.ConveyorBonus * f.conv) * f.bm * (1 + Items.DecorBonus * f.dec + Items.WallBonus * f.wall) * (1 + bonus)
		local kind = item.Kind
		if kind == "Dropper" then
			local rate = (item.Floor == 1 and item.Slot == 1) and 3 or income * 0.15 / mult
			local value = nice(rate * item.Interval)
			item.Value = value -- cash per drop (before multipliers)
			rate = value / item.Interval
			f.dr += rate
			f.drops[item.Slot] = rate
		elseif kind == "Mk2" then
			f.dr += f.drops[item.Slot] or 0
		elseif kind == "Generator" then
			local gmult = f.bm * (1 + Items.DecorBonus * f.dec + Items.WallBonus * f.wall) * (1 + bonus)
			local rate = income * 0.06 / gmult
			local value = nice(rate * item.Cycle)
			item.Value = value -- cash per cycle (before multipliers)
			f.gr += value / item.Cycle
		elseif kind == "Upgrader" then
			f.um *= item.Multiplier
		elseif kind == "Boost" then
			f.bm *= item.Multiplier
		elseif kind == "Decor" then
			f.dec += 1
		elseif kind == "Wall" then
			f.wall += 1
		elseif kind == "Conveyor" then
			f.conv += 1
		elseif kind == "Special" or kind == "Trophy" then
			item.Bonus = Items.SpecialBonus
			bonus += Items.SpecialBonus
		elseif kind == "Roof" then
			item.Bonus = Items.RoofBonus
			bonus += Items.RoofBonus
		end
	end
end

for _, item in List do
	if item.Kind == "Secret" then
		item.Bonus = Items.SecretBonus
	end
end

-- where an item's physical button lives (floor unlocks are bought one floor down)
for _, item in List do
	if item.Kind == "Unlock" then
		item.ButtonFloor = math.max(1, item.Floor - 1)
	elseif item.Kind == "Roof" then
		item.ButtonFloor = FLOORS
	elseif item.Kind == "Secret" then
		item.ButtonFloor = nil
	else
		item.ButtonFloor = item.Floor
	end
end

Items.List = List
Items.ById = ById
Items.Count = #List
Items.BuyableCount = 0
for _, item in List do
	if item.Kind ~= "Secret" then
		Items.BuyableCount += 1
	end
end

-- items per floor (in order), floor 0 = secrets, FLOORS+1 = roof
Items.ByFloor = {}
for _, item in List do
	Items.ByFloor[item.Floor] = Items.ByFloor[item.Floor] or {}
	table.insert(Items.ByFloor[item.Floor], item)
end

function Items.FloorUnlockId(floor: number): string
	return "F" .. floor .. "_1"
end

function Items.GetRebirthCost(rebirths: number): number
	local base = ById[Items.FloorUnlockId(math.clamp(Config.Rebirth.RequiredFloor, 2, FLOORS))].Cost
	return nice(base * (Config.Rebirth.CostGrowth ^ rebirths))
end

--[[
	Income of a tower (shared by server + client so the numbers always match).
	purchased: { [itemId] = true }, disabled: { [itemId] = true } (wrecked items),
	secrets: { [secretId] = true }, fast: Fast Droppers pass.
	Returns (incomePerSecond, worth) where worth[itemId] = cash per drop for
	droppers / per cycle for generators. Global multipliers (rebirths,
	passes, boosts, events) are NOT included.
]]
function Items.ComputeIncome(purchased: { [string]: boolean }, disabled: { [string]: boolean }?, secrets: { [string]: boolean }?, fast: boolean?)
	disabled = disabled or {}
	secrets = secrets or {}
	local floors = {}
	for F = 0, FLOORS + 1 do
		floors[F] = { dr = 0, gr = 0, um = 1, bm = 1, dec = 0, wall = 0, conv = 0, mk2 = {} }
	end
	local bonus = 0
	local function active(item)
		return purchased[item.Id] and not (disabled :: any)[item.Id]
	end
	for _, item in List do
		local kind = item.Kind
		if kind == "Secret" then
			if (secrets :: any)[item.SecretId] then
				bonus += item.Bonus
			end
		elseif active(item) then
			local f = floors[item.Floor]
			if kind == "Upgrader" then
				f.um *= item.Multiplier
			elseif kind == "Boost" then
				f.bm *= item.Multiplier
			elseif kind == "Decor" then
				f.dec += 1
			elseif kind == "Wall" then
				f.wall += 1
			elseif kind == "Conveyor" then
				f.conv += 1
			elseif kind == "Mk2" then
				f.mk2[item.Slot] = true
			elseif item.Bonus then
				bonus += item.Bonus
			end
		end
	end
	local worth = {}
	local total = 0
	local bonusMult = 1 + bonus
	for F = 0, FLOORS + 1 do
		local f = floors[F]
		local extras = f.bm * (1 + Items.DecorBonus * f.dec + Items.WallBonus * f.wall) * bonusMult
		local dropMult = f.um * (1 + Items.ConveyorBonus * f.conv) * extras
		local items = Items.ByFloor and Items.ByFloor[F]
		if items then
			for _, item in items do
				if active(item) then
					if item.Kind == "Dropper" then
						local mk = f.mk2[item.Slot] and 2 or 1
						local perDrop = item.Value * mk * dropMult
						worth[item.Id] = perDrop
						total += perDrop / item.Interval * (fast and 2 or 1)
					elseif item.Kind == "Generator" then
						local perCycle = item.Value * extras
						worth[item.Id] = perCycle
						total += perCycle / item.Cycle
					end
				end
			end
		end
	end
	return total, worth
end

function Items.IsAvailable(item, purchased: { [string]: boolean }): boolean
	if purchased[item.Id] or item.Kind == "Secret" then
		return false
	end
	for _, req in item.Requires do
		if not purchased[req] then
			return false
		end
	end
	return true
end

return Items
