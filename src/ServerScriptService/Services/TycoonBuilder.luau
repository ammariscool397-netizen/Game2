--[[
	TycoonBuilder - procedural geometry for plots, buttons and every tycoon item.
	All positions are relative to the plot CFrame (see TycoonItems.luau).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local BuildKit = require(script.Parent.BuildKit)

local Part = BuildKit.Part

local TycoonBuilder = {}

local PLOT_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(90, 220, 110),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(190, 90, 255),
	Color3.fromRGB(255, 130, 40),
}

local function at(cf: CFrame, x: number, y: number, z: number): CFrame
	return cf * CFrame.new(x, y, z)
end

---------------------------------------------------------------------------
-- Plot base (always present)
---------------------------------------------------------------------------
function TycoonBuilder.BuildPlot(index: number, cf: CFrame, parent: Instance)
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]
	local model = BuildKit.Model("Plot" .. index, parent)
	model:SetAttribute("PlotIndex", index)

	local base = BuildKit.Model("Base", model)
	Part({
		Name = "Floor",
		Size = Vector3.new(120, 1, 120),
		CFrame = at(cf, 0, 0.5, 0),
		Color = Color3.fromRGB(225, 225, 230),
		Material = Enum.Material.Concrete,
		Parent = base,
	})
	-- glowing border
	for _, data in {
		{ Vector3.new(120, 0.3, 1), Vector3.new(0, 1.1, -59.5) },
		{ Vector3.new(120, 0.3, 1), Vector3.new(0, 1.1, 59.5) },
		{ Vector3.new(1, 0.3, 120), Vector3.new(-59.5, 1.1, 0) },
		{ Vector3.new(1, 0.3, 120), Vector3.new(59.5, 1.1, 0) },
	} do
		Part({ Name = "Border", Size = data[1], CFrame = at(cf, data[2].X, data[2].Y, data[2].Z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = base })
	end

	-- entrance gate with owner name
	for _, x in { -11, 11 } do
		Part({ Name = "GatePillar", Size = Vector3.new(2, 16, 2), CFrame = at(cf, x, 8, -58), Color = Color3.fromRGB(45, 45, 60), Material = Enum.Material.Metal, Parent = base })
		local orb = Part({ Name = "GateOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.4, CFrame = at(cf, x, 17, -58), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = base })
		BuildKit.Light(orb, color, 20, 2)
	end
	local beam = Part({ Name = "GateSign", Size = Vector3.new(24, 4, 1.2), CFrame = at(cf, 0, 14, -58), Color = color, Material = Enum.Material.SmoothPlastic, Parent = base })
	local _, signLabel = BuildKit.SurfaceText(beam, Enum.NormalId.Front, "EMPTY PLOT", { PixelsPerStud = 20 })
	local _, signLabelBack = BuildKit.SurfaceText(beam, Enum.NormalId.Back, "EMPTY PLOT", { PixelsPerStud = 20 })

	-- conveyor
	local conveyor = Part({
		Name = "Conveyor",
		Size = Vector3.new(100, 1, 6),
		CFrame = at(cf, -2, 1.5, 10),
		Color = Color3.fromRGB(40, 40, 48),
		Material = Enum.Material.DiamondPlate,
		Parent = base,
	})
	conveyor.AssemblyLinearVelocity = cf.RightVector * Config.ConveyorSpeed
	for _, z in { 6.7, 13.3 } do
		Part({ Name = "Rail", Size = Vector3.new(100, 1.4, 0.6), CFrame = at(cf, -2, 2.7, z), Color = color, Material = Enum.Material.Neon, Parent = base })
	end
	-- end cap behind the first dropper
	Part({ Name = "Rail", Size = Vector3.new(0.6, 1.4, 7.2), CFrame = at(cf, -52, 2.7, 10), Color = color, Material = Enum.Material.Neon, Parent = base })

	-- collector
	local collector = Part({
		Name = "Collector",
		Size = Vector3.new(5, 4, 8),
		CFrame = at(cf, 50.5, 2, 10),
		Color = Color3.fromRGB(40, 230, 110),
		Material = Enum.Material.Neon,
		Tags = { "Pulse" },
		Parent = base,
	})
	BuildKit.Billboard(collector, "COLLECTOR", { Size = UDim2.fromOffset(160, 36), Offset = Vector3.new(0, 4, 0), Color = Color3.fromRGB(120, 255, 160), MaxDistance = 80 })
	BuildKit.Particles(collector, {
		Color = ColorSequence.new(Color3.fromRGB(120, 255, 160)),
		Size = BuildKit.Size(0.6),
		Rate = 6,
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top,
	})

	-- vault collect pad
	local pad = Part({
		Name = "CollectPad",
		Size = Vector3.new(7, 0.5, 7),
		CFrame = at(cf, 50, 1.25, -3),
		Color = Color3.fromRGB(255, 200, 30),
		Material = Enum.Material.Neon,
		Tags = { "Pulse" },
		Parent = base,
	})
	local _, vaultLabel = BuildKit.Billboard(pad, "🏦 VAULT: $0\nStep here to collect", {
		Size = UDim2.fromOffset(220, 64),
		Offset = Vector3.new(0, 4, 0),
		Color = Color3.fromRGB(255, 225, 90),
		MaxDistance = 90,
	})

	local folders = {}
	for _, name in { "Items", "Buttons", "Drops" } do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		folders[name] = f
	end

	return {
		Index = index,
		CFrame = cf,
		Color = color,
		Model = model,
		Items = folders.Items,
		Buttons = folders.Buttons,
		Drops = folders.Drops,
		SignLabels = { signLabel, signLabelBack },
		Conveyor = conveyor,
		Collector = collector,
		CollectPad = pad,
		VaultLabel = vaultLabel,
		SpawnCFrame = at(cf, 0, 4, -48) * CFrame.Angles(0, math.pi, 0),
	}
end

---------------------------------------------------------------------------
-- Purchase button
---------------------------------------------------------------------------
function TycoonBuilder.BuildButton(plot, item)
	local pos: Vector3 = item.ButtonPos
	local model = BuildKit.Model(item.Id, plot.Buttons)
	local base = Part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 6.2, 6.2),
		CFrame = at(plot.CFrame, pos.X, 1.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(30, 30, 40),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local pad = Part({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 5, 5),
		CFrame = at(plot.CFrame, pos.X, 1.4, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(235, 70, 70),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local gui, label = BuildKit.Billboard(pad, item.Name .. "\n" .. Util.Money(item.Cost), {
		Size = UDim2.fromOffset(170, 56),
		Offset = Vector3.new(0, 3.5, 0),
		MaxDistance = 70,
	})
	model.PrimaryPart = base
	-- tiny spawn-in pop
	pad.Size = Vector3.new(0.6, 0.5, 0.5)
	game:GetService("TweenService"):Create(pad, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.6, 5, 5) }):Play()
	return { Model = model, Pad = pad, Label = label, Gui = gui }
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------
local builders = {}

function builders.Dropper(plot, item, model: Model)
	local p: Vector3 = item.Pos
	local cf = plot.CFrame
	local color: Color3 = item.Color or Color3.new(0.7, 0.7, 0.7)
	local material = item.Material or Enum.Material.SmoothPlastic
	local tier = item.Tier or 1

	Part({ Name = "Pillar", Size = Vector3.new(1.4, 13, 1.4), CFrame = at(cf, p.X, 7, p.Z + 5.2), Color = Color3.fromRGB(50, 50, 60), Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Arm", Size = Vector3.new(1.4, 1.4, 4), CFrame = at(cf, p.X, 12, p.Z + 3), Color = Color3.fromRGB(50, 50, 60), Material = Enum.Material.Metal, Parent = model })
	local body = Part({ Name = "Body", Size = Vector3.new(4.5, 4, 4.5), CFrame = at(cf, p.X, 11, p.Z), Color = color, Material = material, Parent = model })
	Part({ Name = "Band", Size = Vector3.new(4.7, 0.6, 4.7), CFrame = at(cf, p.X, 10, p.Z), Color = plot.Color, Material = Enum.Material.Neon, Parent = model })
	Part({ Name = "Funnel", Size = Vector3.new(2.6, 1.6, 2.6), CFrame = at(cf, p.X, 8.2, p.Z), Color = Color3.fromRGB(40, 40, 50), Material = Enum.Material.Metal, Parent = model })
	local gem = Part({
		Name = "Gem",
		Size = Vector3.new(1.4, 1.4, 1.4),
		CFrame = at(cf, p.X, 14, p.Z) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin" },
		Parent = model,
	})
	if tier >= 4 then
		BuildKit.Particles(body, {
			Color = ColorSequence.new(color),
			Size = BuildKit.Size(0.5),
			Rate = 3 + tier,
			Speed = NumberRange.new(1, 2),
			SpreadAngle = Vector2.new(180, 180),
		})
	end
	if tier >= 6 then
		BuildKit.Light(gem, color, 14, 2)
	end
	if tier >= 9 then
		BuildKit.Particles(gem, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(140, 60, 255), Color3.fromRGB(0, 220, 255)),
			Size = BuildKit.Size(1.2),
			Rate = 20,
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(180, 180),
			RotSpeed = NumberRange.new(-90, 90),
		})
	end
	BuildKit.Billboard(body, item.Name, { Size = UDim2.fromOffset(120, 24), Offset = Vector3.new(0, 5.5, 0), MaxDistance = 50, Color = color:Lerp(Color3.new(1, 1, 1), 0.4) })
	return { Spout = (at(cf, p.X, 6.8, p.Z)).Position }
end

function builders.Upgrader(plot, item, model: Model)
	local p: Vector3 = item.Pos
	local cf = plot.CFrame
	local color: Color3 = item.Color or Color3.fromRGB(0, 170, 255)
	for _, dz in { -4.4, 4.4 } do
		Part({ Name = "Pillar", Size = Vector3.new(1.6, 8, 1.6), CFrame = at(cf, p.X, 5, p.Z + dz), Color = Color3.fromRGB(45, 45, 55), Material = Enum.Material.Metal, Parent = model })
	end
	Part({ Name = "Top", Size = Vector3.new(2.4, 1.4, 10.4), CFrame = at(cf, p.X, 9.4, p.Z), Color = color, Material = Enum.Material.Neon, Parent = model })
	local detector = Part({
		Name = "Detector",
		Size = Vector3.new(1.6, 5.5, 6),
		CFrame = at(cf, p.X, 5, p.Z),
		Color = color,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		CanCollide = false,
		Parent = model,
	})
	BuildKit.Light(detector, color, 14, 2)
	BuildKit.Particles(detector, {
		Color = ColorSequence.new(color),
		Size = BuildKit.Size(0.4),
		Rate = 12,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
	})
	local ring = Part({
		Name = "Ring",
		Size = Vector3.new(0.4, 3, 3),
		CFrame = at(cf, p.X, 12, p.Z),
		Color = color,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		Tags = { "Spin" },
		Parent = model,
	})
	BuildKit.Billboard(ring, "x" .. tostring(item.Multiplier), { Size = UDim2.fromOffset(80, 30), Offset = Vector3.new(0, 2.5, 0), MaxDistance = 60, Color = color:Lerp(Color3.new(1, 1, 1), 0.5) })
	return { Detector = detector }
end

function builders.Walls(plot, item, model: Model)
	local cf = plot.CFrame
	local wallColor = Color3.fromRGB(235, 230, 220)
	local size, pos, strip
	if item.Side == "Left" then
		size, pos, strip = Vector3.new(2, 14, 118), Vector3.new(-59, 8, 0), Vector3.new(2.4, 0.8, 118)
	elseif item.Side == "Right" then
		size, pos, strip = Vector3.new(2, 14, 118), Vector3.new(59, 8, 0), Vector3.new(2.4, 0.8, 118)
	else
		size, pos, strip = Vector3.new(118, 14, 2), Vector3.new(0, 8, 59), Vector3.new(118, 0.8, 2.4)
	end
	Part({ Name = "Wall", Size = size, CFrame = at(cf, pos.X, pos.Y, pos.Z), Color = wallColor, Material = Enum.Material.Brick, Parent = model })
	Part({ Name = "Trim", Size = strip, CFrame = at(cf, pos.X, 15.2, pos.Z), Color = plot.Color, Material = Enum.Material.Neon, Parent = model })
	Part({ Name = "Trim", Size = strip, CFrame = at(cf, pos.X, 1.4, pos.Z), Color = plot.Color, Material = Enum.Material.Neon, Parent = model })
	-- windows
	for i = -2, 2 do
		local offset = i * 22
		local wsize = item.Side == "Back" and Vector3.new(10, 5, 2.2) or Vector3.new(2.2, 5, 10)
		local wpos = item.Side == "Back" and Vector3.new(offset, 9, pos.Z) or Vector3.new(pos.X, 9, offset)
		Part({ Name = "Window", Size = wsize, CFrame = at(cf, wpos.X, wpos.Y, wpos.Z), Color = Color3.fromRGB(150, 210, 255), Material = Enum.Material.Glass, Transparency = 0.4, Parent = model })
	end
	return {}
end

local decor = {}

function decor.Garden(plot, item, model: Model)
	local cf = plot.CFrame
	local p: Vector3 = item.Pos
	Part({ Name = "Grass", Size = Vector3.new(30, 0.4, 26), CFrame = at(cf, p.X, 1.2, p.Z), Color = Color3.fromRGB(80, 170, 70), Material = Enum.Material.Grass, Parent = model })
	local rng = Random.new(plot.Index * 77)
	for i = 1, 5 do
		local x = p.X + rng:NextNumber(-11, 11)
		local z = p.Z + rng:NextNumber(-9, 9)
		local h = rng:NextNumber(6, 10)
		Part({ Name = "Trunk", Size = Vector3.new(1.2, h, 1.2), CFrame = at(cf, x, 1.4 + h / 2, z), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood, Parent = model })
		Part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(5, 7),
			CFrame = at(cf, x, 1.4 + h, z),
			Color = Color3.fromHSV(0.25 + i * 0.02, 0.65, 0.65),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
	end
	for i = 1, 14 do
		local flower = Part({
			Name = "Flower",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.9,
			CFrame = at(cf, p.X + rng:NextNumber(-13, 13), 1.8, p.Z + rng:NextNumber(-11, 11)),
			Color = Color3.fromHSV(rng:NextNumber(), 0.7, 1),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
		flower.Name = "Flower" .. i
	end
	return {}
end

function decor.Fountain(plot, item, model: Model)
	local cf = plot.CFrame
	local p: Vector3 = item.Pos
	local flat = CFrame.Angles(0, 0, math.rad(90))
	Part({ Name = "Basin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 18, 18), CFrame = at(cf, p.X, 2, p.Z) * flat, Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Marble, Parent = model })
	Part({ Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 16, 16), CFrame = at(cf, p.X, 3.05, p.Z) * flat, Color = Color3.fromRGB(60, 160, 255), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, Parent = model })
	Part({ Name = "Column", Size = Vector3.new(2, 6, 2), CFrame = at(cf, p.X, 6, p.Z), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Marble, Parent = model })
	local top = Part({ Name = "Top", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.6, CFrame = at(cf, p.X, 9.5, p.Z), Color = Color3.fromRGB(80, 200, 255), Material = Enum.Material.Neon, Tags = { "Pulse" }, Parent = model })
	BuildKit.Light(top, Color3.fromRGB(80, 200, 255), 24, 2)
	BuildKit.Particles(top, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(160, 220, 255)),
		Size = BuildKit.Size(0.8, 0.8, 0.2),
		Rate = 60,
		Speed = NumberRange.new(10, 14),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, -30, 0),
		Lifetime = NumberRange.new(1, 1.2),
		EmissionDirection = Enum.NormalId.Top,
		Transparency = NumberSequence.new(0.2, 1),
	})
	return {}
end

function decor.Sign(plot, item, model: Model, ownerName: string?)
	local cf = plot.CFrame
	local p: Vector3 = item.Pos
	Part({ Name = "Backing", Size = Vector3.new(44, 9, 0.6), CFrame = at(cf, p.X, p.Y, p.Z - 0.4), Color = Color3.fromRGB(20, 20, 30), Parent = model })
	local sign = Part({ Name = "Sign", Size = Vector3.new(42, 7.5, 0.4), CFrame = at(cf, p.X, p.Y, p.Z - 0.9), Color = Color3.fromRGB(20, 20, 30), Material = Enum.Material.SmoothPlastic, Parent = model })
	local _, label = BuildKit.SurfaceText(sign, Enum.NormalId.Front, string.upper((ownerName or "MY") .. "'S TYCOON"), { PixelsPerStud = 20, Brightness = 3 })
	label.Name = "RainbowText"
	label:SetAttribute("Rainbow", true)
	sign:AddTag("RainbowSign")
	BuildKit.Light(sign, plot.Color, 30, 2)
	return {}
end

function decor.Statue(plot, item, model: Model, ownerName: string?)
	local cf = plot.CFrame
	local p: Vector3 = item.Pos
	local gold = Color3.fromRGB(255, 200, 40)
	Part({ Name = "Pedestal", Size = Vector3.new(8, 3, 8), CFrame = at(cf, p.X, 2.5, p.Z), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Marble, Parent = model })
	local base = at(cf, p.X, 4, p.Z) * CFrame.Angles(0, math.pi, 0)
	local function piece(name, size, offset)
		return Part({ Name = name, Size = size, CFrame = base * CFrame.new(offset), Color = gold, Material = Enum.Material.Foil, Reflectance = 0.25, Parent = model })
	end
	piece("LeftLeg", Vector3.new(1.6, 4, 1.6), Vector3.new(-0.9, 2, 0))
	piece("RightLeg", Vector3.new(1.6, 4, 1.6), Vector3.new(0.9, 2, 0))
	piece("Torso", Vector3.new(3.6, 4, 1.8), Vector3.new(0, 6, 0))
	piece("LeftArm", Vector3.new(1.6, 4, 1.6), Vector3.new(-2.6, 6, 0))
	piece("RightArm", Vector3.new(1.6, 4, 1.6), Vector3.new(2.6, 7.6, 0)).CFrame = base * CFrame.new(2.6, 8.4, 0) * CFrame.Angles(0, 0, math.rad(150))
	piece("Head", Vector3.new(2, 2, 2), Vector3.new(0, 9, 0))
	local coin = Part({
		Name = "Coin",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 3, 3),
		CFrame = base * CFrame.new(0, 13, 0),
		Color = gold,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin", "Bob" },
		Parent = model,
	})
	BuildKit.Light(coin, gold, 20, 2)
	BuildKit.Billboard(coin, ownerName and (ownerName .. " the Great") or "The Great", { Size = UDim2.fromOffset(160, 30), Offset = Vector3.new(0, 3, 0), Color = gold, MaxDistance = 60 })
	return {}
end

function decor.Tower(plot, item, model: Model)
	local cf = plot.CFrame
	local p: Vector3 = item.Pos
	Part({ Name = "Base", Size = Vector3.new(10, 4, 10), CFrame = at(cf, p.X, 3, p.Z), Color = Color3.fromRGB(40, 40, 55), Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Pillar", Size = Vector3.new(3, 40, 3), CFrame = at(cf, p.X, 25, p.Z), Color = Color3.fromRGB(60, 60, 75), Material = Enum.Material.Metal, Parent = model })
	for i = 1, 4 do
		Part({
			Name = "Ring" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 8 - i, 8 - i),
			CFrame = at(cf, p.X, 8 + i * 8, p.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromHSV(0.12 + i * 0.05, 0.9, 1),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Tags = { "Spin" },
			Parent = model,
		})
	end
	local orb = Part({ Name = "Orb", Shape = Enum.PartType.Ball, Size = Vector3.one * 6, CFrame = at(cf, p.X, 48, p.Z), Color = Color3.fromRGB(255, 210, 40), Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
	BuildKit.Light(orb, Color3.fromRGB(255, 210, 40), 60, 4)
	BuildKit.Particles(orb, {
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 80)),
		Size = BuildKit.Size(1.5),
		Rate = 30,
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(1.5, 2.5),
	})
	Part({ Name = "SkyBeam", Size = Vector3.new(1.5, 300, 1.5), CFrame = at(cf, p.X, 200, p.Z), Color = Color3.fromRGB(255, 220, 80), Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false, CanQuery = false, CanTouch = false, Parent = model })
	return {}
end

function builders.Decor(plot, item, model: Model, ownerName: string?)
	local fn = decor[item.Model]
	if fn then
		return fn(plot, item, model, ownerName)
	end
	return {}
end

function builders.SpeedPad(plot, item, model: Model)
	local cf = plot.CFrame
	local p: Vector3 = item.Pos
	local pad = Part({ Name = "SpeedPad", Size = Vector3.new(8, 0.5, 8), CFrame = at(cf, p.X, 1.25, p.Z), Color = Color3.fromRGB(0, 230, 255), Material = Enum.Material.Neon, Tags = { "Pulse" }, Parent = model })
	BuildKit.Billboard(pad, "⚡ SPEED PAD", { Size = UDim2.fromOffset(150, 34), Offset = Vector3.new(0, 3, 0), Color = Color3.fromRGB(120, 240, 255), MaxDistance = 60 })
	BuildKit.Particles(pad, {
		Color = ColorSequence.new(Color3.fromRGB(0, 230, 255)),
		Size = BuildKit.Size(0.5),
		Rate = 15,
		Speed = NumberRange.new(3, 6),
		EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(10, 10),
	})
	return { Pad = pad }
end

-- Build an item into the plot. Returns (model, extra)
function TycoonBuilder.BuildItem(plot, item, ownerName: string?)
	local model = BuildKit.Model(item.Id, plot.Items)
	local builder = builders[item.Kind]
	local extra = {}
	if builder then
		extra = builder(plot, item, model, ownerName) or {}
	end
	return model, extra
end

-- A drop that falls out of a dropper
function TycoonBuilder.MakeDrop(item, position: Vector3): Part
	local tier = item.Tier or 1
	local size = 1 + math.min(tier, 9) * 0.08
	local drop = Instance.new("Part")
	drop.Name = "Drop"
	drop.Size = Vector3.one * size
	drop.Color = item.Color or Color3.new(0.8, 0.8, 0.8)
	drop.Material = item.Material or Enum.Material.SmoothPlastic
	drop.TopSurface = Enum.SurfaceType.Smooth
	drop.BottomSurface = Enum.SurfaceType.Smooth
	drop.CollisionGroup = "Drops"
	drop.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	drop.CanQuery = false
	if tier >= 7 then
		drop.Material = Enum.Material.Neon
		BuildKit.Light(drop, drop.Color, 6, 1)
	end
	return drop
end

return TycoonBuilder
