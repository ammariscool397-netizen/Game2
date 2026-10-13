--[[
	Every buyable item in a tycoon. Positions are in the plot's local space:
	  X = left/right (-60..60), Z = front/back (-60 is the entrance), Y = up.
	Buttons are laid out automatically in a grid at the front of the plot.

	Kinds:
	  Dropper  - spawns drops worth `Value` every `Interval` seconds
	  Upgrader - multiplies drops passing through by `Multiplier`
	  Walls    - decorative walls (`Side` = Left / Right / Back)
	  Decor    - decorative build (`Model` = Garden / Fountain / Sign / Statue / Tower)
	  SpeedPad - pad that gives a short speed boost
]]

export type Item = {
	Id: string,
	Name: string,
	Cost: number,
	Kind: string,
	Requires: string?,
	Pos: Vector3,
	Value: number?,
	Interval: number?,
	Multiplier: number?,
	Color: Color3?,
	Material: Enum.Material?,
	Tier: number?,
	Side: string?,
	Model: string?,
}

local DROPPER_X = { -48, -41.5, -35, -28.5, -22, -15.5, -9, -2.5, 4 }
local DROPPER_Z = 10

local Items: { Item } = {
	{ Id = "Dropper1", Name = "Basic Dropper", Cost = 25, Kind = "Dropper", Pos = Vector3.new(DROPPER_X[1], 0, DROPPER_Z),
		Value = 6, Interval = 1.5, Tier = 1, Color = Color3.fromRGB(170, 170, 170), Material = Enum.Material.SmoothPlastic },
	{ Id = "Dropper2", Name = "Stone Dropper", Cost = 150, Kind = "Dropper", Requires = "Dropper1", Pos = Vector3.new(DROPPER_X[2], 0, DROPPER_Z),
		Value = 12, Interval = 1.5, Tier = 2, Color = Color3.fromRGB(110, 110, 120), Material = Enum.Material.Slate },
	{ Id = "WallLeft", Name = "Left Walls", Cost = 250, Kind = "Walls", Requires = "Dropper1", Side = "Left", Pos = Vector3.new(-59, 0, 0) },
	{ Id = "Dropper3", Name = "Iron Dropper", Cost = 600, Kind = "Dropper", Requires = "Dropper2", Pos = Vector3.new(DROPPER_X[3], 0, DROPPER_Z),
		Value = 25, Interval = 1.5, Tier = 3, Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal },
	{ Id = "WallRight", Name = "Right Walls", Cost = 800, Kind = "Walls", Requires = "WallLeft", Side = "Right", Pos = Vector3.new(59, 0, 0) },
	{ Id = "Upgrader1", Name = "Basic Upgrader (x1.5)", Cost = 1_200, Kind = "Upgrader", Requires = "Dropper3", Pos = Vector3.new(14, 0, DROPPER_Z),
		Multiplier = 1.5, Color = Color3.fromRGB(0, 170, 255) },
	{ Id = "Dropper4", Name = "Gold Dropper", Cost = 2_500, Kind = "Dropper", Requires = "Dropper3", Pos = Vector3.new(DROPPER_X[4], 0, DROPPER_Z),
		Value = 55, Interval = 1.5, Tier = 4, Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Foil },
	{ Id = "Garden", Name = "Tree Garden", Cost = 3_500, Kind = "Decor", Requires = "WallRight", Model = "Garden", Pos = Vector3.new(-40, 0, 40) },
	{ Id = "WallBack", Name = "Back Wall", Cost = 4_500, Kind = "Walls", Requires = "WallRight", Side = "Back", Pos = Vector3.new(0, 0, 59) },
	{ Id = "Dropper5", Name = "Emerald Dropper", Cost = 7_500, Kind = "Dropper", Requires = "Dropper4", Pos = Vector3.new(DROPPER_X[5], 0, DROPPER_Z),
		Value = 120, Interval = 1.5, Tier = 5, Color = Color3.fromRGB(40, 220, 110), Material = Enum.Material.Glass },
	{ Id = "Fountain", Name = "Fountain", Cost = 10_000, Kind = "Decor", Requires = "Garden", Model = "Fountain", Pos = Vector3.new(0, 0, 40) },
	{ Id = "Upgrader2", Name = "Neon Upgrader (x2)", Cost = 18_000, Kind = "Upgrader", Requires = "Dropper5", Pos = Vector3.new(24, 0, DROPPER_Z),
		Multiplier = 2, Color = Color3.fromRGB(255, 0, 200) },
	{ Id = "Dropper6", Name = "Ruby Dropper", Cost = 30_000, Kind = "Dropper", Requires = "Dropper5", Pos = Vector3.new(DROPPER_X[6], 0, DROPPER_Z),
		Value = 260, Interval = 1.5, Tier = 6, Color = Color3.fromRGB(230, 30, 60), Material = Enum.Material.Glass },
	{ Id = "NeonSign", Name = "Neon Sign", Cost = 40_000, Kind = "Decor", Requires = "WallBack", Model = "Sign", Pos = Vector3.new(0, 12, 58) },
	{ Id = "SpeedPad", Name = "Speed Pad", Cost = 60_000, Kind = "SpeedPad", Requires = "Dropper6", Pos = Vector3.new(-50, 0, -50) },
	{ Id = "Dropper7", Name = "Sapphire Dropper", Cost = 80_000, Kind = "Dropper", Requires = "Dropper6", Pos = Vector3.new(DROPPER_X[7], 0, DROPPER_Z),
		Value = 550, Interval = 1.5, Tier = 7, Color = Color3.fromRGB(40, 90, 255), Material = Enum.Material.Glass },
	{ Id = "Upgrader3", Name = "Plasma Upgrader (x3)", Cost = 150_000, Kind = "Upgrader", Requires = "Dropper7", Pos = Vector3.new(34, 0, DROPPER_Z),
		Multiplier = 3, Color = Color3.fromRGB(255, 120, 0) },
	{ Id = "Dropper8", Name = "Diamond Dropper", Cost = 300_000, Kind = "Dropper", Requires = "Dropper7", Pos = Vector3.new(DROPPER_X[8], 0, DROPPER_Z),
		Value = 1_200, Interval = 1.5, Tier = 8, Color = Color3.fromRGB(150, 240, 255), Material = Enum.Material.Ice },
	{ Id = "Statue", Name = "Golden Statue", Cost = 450_000, Kind = "Decor", Requires = "NeonSign", Model = "Statue", Pos = Vector3.new(22, 0, 44) },
	{ Id = "Dropper9", Name = "Galaxy Dropper", Cost = 900_000, Kind = "Dropper", Requires = "Dropper8", Pos = Vector3.new(DROPPER_X[9], 0, DROPPER_Z),
		Value = 3_000, Interval = 1.5, Tier = 9, Color = Color3.fromRGB(140, 60, 255), Material = Enum.Material.Neon },
	{ Id = "Tower", Name = "Cash Tower", Cost = 1_500_000, Kind = "Decor", Requires = "Dropper9", Model = "Tower", Pos = Vector3.new(45, 0, 40) },
}

local ById: { [string]: Item } = {}
for index, item in Items do
	ById[item.Id] = item
	-- auto button layout: 9 columns, rows going toward the entrance
	local col = (index - 1) % 9
	local row = (index - 1) // 9
	;(item :: any).ButtonPos = Vector3.new(-48 + col * 12, 0, -14 - row * 12)
end

return {
	List = Items,
	ById = ById,
}
