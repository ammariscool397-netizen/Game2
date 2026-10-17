--[[
	TycoonBuilder - procedural geometry for plots, 8-floor towers, buttons,
	rubble and every one of the 500+ tycoon items. No assets needed.

	Plot space: plot.CFrame at ground level, -Z faces the lobby.
	Tower space: floor F surface = plot.TowerCF * (0, (F-1) * FloorHeight, 0)
	Floor-local coordinates come from TycoonItems.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Items = require(Shared.TycoonItems)
local BuildKit = require(script.Parent.BuildKit)

local Part = BuildKit.Part
local FH = Config.Tycoon.FloorHeight

local TycoonBuilder = {}

local PLOT_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(90, 220, 110),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(190, 90, 255),
	Color3.fromRGB(255, 130, 40),
	Color3.fromRGB(0, 220, 220),
	Color3.fromRGB(255, 100, 200),
}

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- turns a cylinder upright
local DARK = Color3.fromRGB(40, 40, 50)

local function at(cf: CFrame, x: number, y: number, z: number): CFrame
	return cf * CFrame.new(x, y, z)
end

local function shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), amount)
	end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

function TycoonBuilder.FloorCF(plot, floor: number): CFrame
	return plot.TowerCF * CFrame.new(0, (floor - 1) * FH, 0)
end

local function themeOf(item)
	return item.Theme or Items.Themes[1]
end

---------------------------------------------------------------------------
-- Plot base (always present)
---------------------------------------------------------------------------
function TycoonBuilder.BuildPlot(index: number, cf: CFrame, parent: Instance)
	local color = PLOT_COLORS[(index - 1) % #PLOT_COLORS + 1]
	local model = BuildKit.Model("Plot" .. index, parent)
	model:SetAttribute("PlotIndex", index)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local base = BuildKit.Model("Base", model)
	Part({ Name = "Ground", Size = Vector3.new(120, 1, 120), CFrame = at(cf, 0, 0.5, 0), Color = Color3.fromRGB(225, 225, 230), Material = Enum.Material.Concrete, Parent = base })
	for _, data in {
		{ Vector3.new(120, 0.3, 1), Vector3.new(0, 1.1, -59.5) },
		{ Vector3.new(120, 0.3, 1), Vector3.new(0, 1.1, 59.5) },
		{ Vector3.new(1, 0.3, 120), Vector3.new(-59.5, 1.1, 0) },
		{ Vector3.new(1, 0.3, 120), Vector3.new(59.5, 1.1, 0) },
	} do
		Part({ Name = "Border", Size = data[1], CFrame = at(cf, data[2].X, data[2].Y, data[2].Z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = base })
	end
	-- path from the gate to the tower door
	Part({ Name = "Path", Size = Vector3.new(12, 0.2, 28), CFrame = at(cf, 0, 1.1, -46), Color = Color3.fromRGB(170, 150, 120), Material = Enum.Material.Cobblestone, Parent = base })

	-- entrance gate with owner name
	for _, x in { -11, 11 } do
		Part({ Name = "GatePillar", Size = Vector3.new(2, 16, 2), CFrame = at(cf, x, 8, -58), Color = Color3.fromRGB(45, 45, 60), Material = Enum.Material.Metal, Parent = base })
		local orb = Part({ Name = "GateOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 2.4, CFrame = at(cf, x, 17, -58), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = base })
		BuildKit.Light(orb, color, 20, 2)
	end
	local beam = Part({ Name = "GateSign", Size = Vector3.new(24, 4, 1.2), CFrame = at(cf, 0, 14, -58), Color = color, Parent = base })
	local _, signLabel = BuildKit.SurfaceText(beam, Enum.NormalId.Front, "EMPTY PLOT", { PixelsPerStud = 20 })
	local _, signLabelBack = BuildKit.SurfaceText(beam, Enum.NormalId.Back, "EMPTY PLOT", { PixelsPerStud = 20 })

	local folders = {}
	for _, name in { "Items", "Buttons", "Rubble" } do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = model
		folders[name] = f
	end

	local towerCF = cf * CFrame.new(0, 1, 10)
	return {
		Index = index,
		CFrame = cf,
		TowerCF = towerCF,
		Color = color,
		Model = model,
		Items = folders.Items,
		Buttons = folders.Buttons,
		Rubble = folders.Rubble,
		SignLabels = { signLabel, signLabelBack },
		SpawnCFrame = at(cf, 0, 4, -50) * CFrame.Angles(0, math.pi, 0),
		ShieldCenter = (cf * CFrame.new(0, 60, 10)).Position,
		ShieldRadius = 130,
	}
end

---------------------------------------------------------------------------
-- Purchase button
---------------------------------------------------------------------------
function TycoonBuilder.BuildButton(plot, item, slot: number?, price: number)
	local floorCF = TycoonBuilder.FloorCF(plot, item.ButtonFloor or 1)
	local pos = Items.ButtonLane(item) or Items.ButtonSlots[slot :: number]
	local model = BuildKit.Model(item.Id, plot.Buttons)
	local ring = Part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 6.2, 6.2),
		CFrame = at(floorCF, pos.X, 0.2, pos.Z) * FLAT,
		Color = Color3.fromRGB(30, 30, 40),
		Material = Enum.Material.Metal,
		Parent = model,
	})
	local pad = Part({
		Name = "Pad",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 5, 5),
		CFrame = at(floorCF, pos.X, 0.4, pos.Z) * FLAT,
		Color = Color3.fromRGB(235, 70, 70),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	local gui, label = BuildKit.Billboard(pad, item.Name .. "\n" .. Util.Money(price), {
		Size = UDim2.fromOffset(180, 56),
		Offset = Vector3.new(0, 4.5, 0),
		MaxDistance = 38,
	})
	local pillar = Part({
		Name = "Pillar",
		Size = Vector3.new(0.8, 16, 0.8),
		CFrame = at(floorCF, pos.X, 8.4, pos.Z),
		Color = Color3.fromRGB(235, 70, 70),
		Material = Enum.Material.Neon,
		Transparency = 0.7,
		CanCollide = false,
		Parent = model,
	})
	model.PrimaryPart = ring
	pad.Size = Vector3.new(0.6, 0.5, 0.5)
	TweenService:Create(pad, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.6, 5, 5) }):Play()
	return { Model = model, Pad = pad, Pillar = pillar, Label = label, Gui = gui, Slot = slot, Floor = item.ButtonFloor }
end

---------------------------------------------------------------------------
-- Rubble left behind when a disaster wrecks an item
---------------------------------------------------------------------------
function TycoonBuilder.BuildRubble(plot, position: Vector3, id: string)
	local model = BuildKit.Model("Rubble_" .. id, plot.Rubble)
	local rng = Random.new()
	for _ = 1, 4 do
		Part({
			Name = "Debris",
			Size = Vector3.new(rng:NextNumber(1, 3), rng:NextNumber(0.5, 1.5), rng:NextNumber(1, 3)),
			CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-2, 2), 0.5, rng:NextNumber(-2, 2))) * CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6), rng:NextNumber(-0.6, 0.6)),
			Color = Color3.fromRGB(45, 40, 38),
			Material = Enum.Material.Slate,
			CanCollide = false,
			Parent = model,
		})
	end
	local core = Part({ Name = "Core", Size = Vector3.new(2, 1, 2), Position = position + Vector3.new(0, 0.5, 0), Color = Color3.fromRGB(30, 25, 25), Material = Enum.Material.CrackedLava, CanCollide = false, Parent = model })
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 8
	fire.Parent = core
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(40, 40, 40)
	smoke.Opacity = 0.25
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Parent = core
	BuildKit.Billboard(core, "🔧 WRECKED", { Size = UDim2.fromOffset(110, 24), Offset = Vector3.new(0, 3, 0), Color = Color3.fromRGB(255, 120, 80), MaxDistance = 50 })
	return model
end

---------------------------------------------------------------------------
-- Item builders. Each gets (plot, item, model, floorCF, ownerName)
---------------------------------------------------------------------------
local builders = {}

-- Floor structure: slab, conveyor, collector, vault pad, elevator
function builders.Unlock(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local F = item.Floor
	if F > 1 then
		Part({ Name = "Slab", Size = Vector3.new(84, 1, 84), CFrame = at(cf, 0, -0.5, 0), Color = theme.Primary, Material = theme.Floor, Parent = model })
	else
		Part({ Name = "Tiles", Size = Vector3.new(84, 0.2, 84), CFrame = at(cf, 0, 0.1, 0), Color = theme.Primary, Material = theme.Floor, Parent = model })
	end
	for _, data in {
		{ Vector3.new(84.4, 0.4, 0.6), Vector3.new(0, -0.2, -42) },
		{ Vector3.new(84.4, 0.4, 0.6), Vector3.new(0, -0.2, 42) },
		{ Vector3.new(0.6, 0.4, 84.4), Vector3.new(-42, -0.2, 0) },
		{ Vector3.new(0.6, 0.4, 84.4), Vector3.new(42, -0.2, 0) },
	} do
		Part({ Name = "Edge", Size = data[1], CFrame = at(cf, data[2].X, data[2].Y + (F == 1 and 0.4 or 0), data[2].Z), Color = theme.Accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end

	-- conveyor
	local beltLength = Items.BeltEndX - Items.BeltStartX
	local beltX = (Items.BeltEndX + Items.BeltStartX) / 2
	Part({ Name = "Belt", Size = Vector3.new(beltLength, 1.2, 5), CFrame = at(cf, beltX, 0.6, Items.BeltZ), Color = Color3.fromRGB(35, 35, 42), Material = Enum.Material.DiamondPlate, Parent = model })
	for _, dz in { -2.75, 2.75 } do
		Part({ Name = "Rail", Size = Vector3.new(beltLength, 0.8, 0.5), CFrame = at(cf, beltX, 1.6, Items.BeltZ + dz), Color = theme.Accent, Material = Enum.Material.Neon, Parent = model })
	end
	local collector = Part({
		Name = "Collector",
		Size = Vector3.new(3, 3.5, 6),
		CFrame = at(cf, Items.CollectorPos.X, 1.75, Items.CollectorPos.Z),
		Color = Color3.fromRGB(40, 230, 110),
		Material = Enum.Material.Neon,
		Tags = { "Pulse" },
		Parent = model,
	})
	BuildKit.Light(collector, Color3.fromRGB(120, 255, 160), 14, 1.5)
	BuildKit.Billboard(collector, "COLLECTOR", { Size = UDim2.fromOffset(130, 30), Offset = Vector3.new(0, 3.5, 0), Color = Color3.fromRGB(120, 255, 160), MaxDistance = 50 })

	-- vault pad
	local pad = Part({
		Name = "VaultPad",
		Size = Vector3.new(6, 0.4, 6),
		CFrame = at(cf, Items.VaultPadPos.X, 0.2, Items.VaultPadPos.Z),
		Color = Color3.fromRGB(255, 200, 30),
		Material = Enum.Material.Neon,
		Tags = { "Pulse" },
		Parent = model,
	})
	local _, vaultLabel = BuildKit.Billboard(pad, "🏦 VAULT: $0\nStep here to collect", { Size = UDim2.fromOffset(210, 60), Offset = Vector3.new(0, 4, 0), Color = Color3.fromRGB(255, 225, 90), MaxDistance = 70 })

	-- elevator booth
	local e = Items.ElevatorPos
	Part({ Name = "ElevatorPad", Size = Vector3.new(7, 0.4, 7), CFrame = at(cf, e.X, 0.2, e.Z), Color = Color3.fromRGB(0, 200, 255), Material = Enum.Material.Neon, Parent = model })
	for _, offset in { Vector2.new(-3.3, -3.3), Vector2.new(3.3, -3.3), Vector2.new(-3.3, 3.3), Vector2.new(3.3, 3.3) } do
		Part({ Name = "ElevatorFrame", Size = Vector3.new(0.5, 10, 0.5), CFrame = at(cf, e.X + offset.X, 5, e.Z + offset.Y), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	end
	Part({ Name = "ElevatorRoof", Size = Vector3.new(7.2, 0.5, 7.2), CFrame = at(cf, e.X, 10.2, e.Z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	local console = Part({ Name = "Console", Size = Vector3.new(1.4, 3, 1), CFrame = at(cf, e.X + 2.2, 1.5, e.Z + 2.6), Color = Color3.fromRGB(0, 200, 255), Material = Enum.Material.Neon, Parent = model })
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Choose Floor"
	prompt.ObjectText = "Elevator"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = console
	local signPart = Part({ Name = "FloorSign", Size = Vector3.new(7, 1.6, 0.3), CFrame = at(cf, e.X, 11.3, e.Z - 3.3), Color = DARK, Parent = model })
	BuildKit.SurfaceText(signPart, Enum.NormalId.Front, "🛗 FLOOR " .. F, { PixelsPerStud = 20 })
	BuildKit.SurfaceText(signPart, Enum.NormalId.Back, "🛗 FLOOR " .. F .. " • " .. string.upper(theme.Name), { PixelsPerStud = 20 })

	-- interior lights
	for _, x in { -20, 20 } do
		local lamp = Part({ Name = "Lamp", Size = Vector3.new(6, 0.3, 1), CFrame = at(cf, x, FH - 1.4, 0), Color = Color3.fromRGB(255, 245, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		BuildKit.Light(lamp, Color3.fromRGB(255, 240, 210), 40, 1.2)
	end
	return { VaultPad = pad, VaultLabel = vaultLabel, ElevatorPrompt = prompt }
end

function builders.Dropper(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local k = item.Slot
	local x, z = item.LocalPos.X, item.LocalPos.Z
	local color = theme.Primary:Lerp(theme.Accent, (k - 1) / 9)
	local material = k >= 6 and theme.Drop or Enum.Material.SmoothPlastic
	Part({ Name = "Pillar", Size = Vector3.new(1.2, 13, 1.2), CFrame = at(cf, x, 6.5, z + 4.6), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Arm", Size = Vector3.new(1.2, 1.2, 3.6), CFrame = at(cf, x, 12.4, z + 2.8), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	local body = Part({ Name = "Body", Size = Vector3.new(4.2, 3.6, 4.2), CFrame = at(cf, x, 9.8, z), Color = color, Material = material, Parent = model })
	Part({ Name = "Band", Size = Vector3.new(4.4, 0.5, 4.4), CFrame = at(cf, x, 8.6, z), Color = theme.Accent, Material = Enum.Material.Neon, Parent = model })
	Part({ Name = "Funnel", Size = Vector3.new(2.2, 1.4, 2.2), CFrame = at(cf, x, 7.4, z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	local gem = Part({
		Name = "Gem",
		Size = Vector3.one * 1.3,
		CFrame = at(cf, x, 12.9, z) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin" },
		Parent = model,
	})
	if k >= 5 then
		BuildKit.Particles(body, { Color = ColorSequence.new(color), Size = BuildKit.Size(0.4), Rate = k, Speed = NumberRange.new(1, 2), SpreadAngle = Vector2.new(180, 180) })
	end
	if k >= 8 then
		BuildKit.Light(gem, color, 12, 1.5)
	end
	BuildKit.Billboard(body, item.Name, { Size = UDim2.fromOffset(120, 22), Offset = Vector3.new(0, 4.6, 0), MaxDistance = 36, Color = shade(color, 0.4) })
	local spout = at(cf, x, 6.4, z).Position
	return {
		Spout = spout,
		BeltY = at(cf, 0, 1.2, 0).Position.Y,
		BeltEnd = at(cf, Items.BeltEndX, 1.2, Items.BeltZ).Position,
	}
end

function builders.Mk2(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local x, z = item.LocalPos.X, item.LocalPos.Z
	local ring = Part({
		Name = "Mk2Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, 5.6, 5.6),
		CFrame = at(cf, x, 9.8, z) * FLAT,
		Color = theme.Accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = model,
	})
	BuildKit.Particles(ring, {
		Color = ColorSequence.new(theme.Accent, Color3.new(1, 1, 1)),
		Size = BuildKit.Size(0.5),
		Rate = 10,
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(180, 180),
	})
	BuildKit.Billboard(ring, "MK II", { Size = UDim2.fromOffset(60, 20), Offset = Vector3.new(0, -3.4, 0), MaxDistance = 36, Color = theme.Accent })
	return {}
end

function builders.Upgrader(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local x, z = item.LocalPos.X, item.LocalPos.Z
	local color = Color3.fromHSV((theme.Hue + 0.12 * item.Slot) % 1, 0.8, 1)
	for _, dz in { -3.4, 3.4 } do
		Part({ Name = "Pillar", Size = Vector3.new(1.2, 8, 1.2), CFrame = at(cf, x, 4, z + dz), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	end
	Part({ Name = "Top", Size = Vector3.new(2, 1, 8), CFrame = at(cf, x, 8.4, z), Color = color, Material = Enum.Material.Neon, Parent = model })
	local detector = Part({ Name = "Detector", Size = Vector3.new(1.2, 4, 5), CFrame = at(cf, x, 3.2, z), Color = color, Material = Enum.Material.ForceField, Transparency = 0.2, CanCollide = false, Parent = model })
	BuildKit.Light(detector, color, 12, 1.5)
	local ring = Part({
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2.6, 2.6),
		CFrame = at(cf, x, 10.4, z),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin" },
		Parent = model,
	})
	BuildKit.Billboard(ring, "x" .. tostring(item.Multiplier), { Size = UDim2.fromOffset(70, 26), Offset = Vector3.new(0, 2.2, 0), MaxDistance = 50, Color = shade(color, 0.4) })
	return { BeltPos = at(cf, x, 1.2, z).Position, Color = color }
end

-- 4 generator styles
local generatorStyles = {}

generatorStyles[1] = function(model, cf, x, z, theme, color) -- press
	Part({ Name = "Base", Size = Vector3.new(6, 2, 6), CFrame = at(cf, x, 1, z), Color = theme.Secondary, Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Column", Size = Vector3.new(1, 7, 1), CFrame = at(cf, x - 2.2, 5.5, z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Column", Size = Vector3.new(1, 7, 1), CFrame = at(cf, x + 2.2, 5.5, z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Head", Size = Vector3.new(5.4, 1.2, 3), CFrame = at(cf, x, 9.2, z), Color = color, Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Piston", Size = Vector3.new(2.4, 2, 2.4), CFrame = at(cf, x, 5, z), Color = color, Material = Enum.Material.Metal, Tags = { "Bob" }, Parent = model })
	return Part({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2.4, 2.4), CFrame = at(cf, x, 2.6, z), Color = Color3.fromRGB(255, 210, 40), Material = Enum.Material.Neon, CanCollide = false, Tags = { "Spin" }, Parent = model })
end

generatorStyles[2] = function(model, cf, x, z, theme, color) -- tank
	Part({ Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 6.5, 6.5), CFrame = at(cf, x, 0.5, z) * FLAT, Color = theme.Secondary, Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Tank", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 5, 5), CFrame = at(cf, x, 5, z) * FLAT, Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Glass, Transparency = 0.5, Parent = model })
	local fluid = Part({ Name = "Fluid", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6.5, 4.2, 4.2), CFrame = at(cf, x, 4.6, z) * FLAT, Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
	Part({ Name = "Cap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 5.6, 5.6), CFrame = at(cf, x, 9.2, z) * FLAT, Color = DARK, Material = Enum.Material.Metal, Parent = model })
	return fluid
end

generatorStyles[3] = function(model, cf, x, z, theme, color) -- ring tower
	Part({ Name = "Base", Size = Vector3.new(5, 1, 5), CFrame = at(cf, x, 0.5, z), Color = theme.Secondary, Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "Pole", Size = Vector3.new(0.8, 10, 0.8), CFrame = at(cf, x, 5.5, z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	for i = 1, 3 do
		Part({ Name = "Ring" .. i, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 5 - i, 5 - i), CFrame = at(cf, x, 2 + i * 2.4, z) * CFrame.Angles(0, 0, math.rad(90 - 25 * i)), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Spin" }, Parent = model })
	end
	return Part({ Name = "Orb", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = at(cf, x, 11, z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
end

generatorStyles[4] = function(model, cf, x, z, theme, color) -- printer
	Part({ Name = "Body", Size = Vector3.new(6, 5, 5), CFrame = at(cf, x, 2.5, z), Color = theme.Secondary, Material = Enum.Material.Metal, Parent = model })
	local screen = Part({ Name = "Screen", Size = Vector3.new(4, 2, 0.2), CFrame = at(cf, x, 3.6, z - 2.55), Color = Color3.fromRGB(10, 10, 20), Parent = model })
	BuildKit.SurfaceText(screen, Enum.NormalId.Front, "$$$", { PixelsPerStud = 20, Color = color })
	Part({ Name = "Tray", Size = Vector3.new(4, 0.4, 2), CFrame = at(cf, x, 1.2, z - 3), Color = DARK, Parent = model })
	for i = 1, 3 do
		Part({ Name = "Bill", Size = Vector3.new(3, 0.1, 1.4), CFrame = at(cf, x, 1.45 + i * 0.12, z - 3) * CFrame.Angles(0, math.rad(i * 8 - 16), 0), Color = Color3.fromRGB(110, 200, 110), Parent = model })
	end
	return Part({ Name = "Light", Size = Vector3.new(6.2, 0.4, 5.2), CFrame = at(cf, x, 5.2, z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
end

function builders.Generator(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local x, z = item.LocalPos.X, item.LocalPos.Z
	local color = Color3.fromHSV((theme.Hue + item.Slot * 0.07) % 1, 0.75, 1)
	local style = generatorStyles[(item.Slot - 1) % 4 + 1]
	local top = style(model, cf, x, z, theme, color)
	BuildKit.Particles(top, { Color = ColorSequence.new(color), Size = BuildKit.Size(0.5), Rate = 6, Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top })
	BuildKit.Light(top, color, 12, 1.2)
	BuildKit.Billboard(top, item.Name, { Size = UDim2.fromOffset(130, 24), Offset = Vector3.new(0, 3, 0), MaxDistance = 40, Color = shade(color, 0.4) })
	return { PopPos = at(cf, x, 12, z).Position }
end

-- 17 decor pieces (index = Items.DecorNames index)
local decor = {}

decor[1] = function(model, cf, p, theme) -- crate stack
	Part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = at(cf, p.X - 1.5, 1.5, p.Z), Color = Color3.fromRGB(160, 110, 60), Material = Enum.Material.WoodPlanks, Parent = model })
	Part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = at(cf, p.X + 1.6, 1.5, p.Z + 0.4) * CFrame.Angles(0, 0.3, 0), Color = Color3.fromRGB(150, 100, 55), Material = Enum.Material.WoodPlanks, Parent = model })
	Part({ Name = "Crate", Size = Vector3.new(2.6, 2.6, 2.6), CFrame = at(cf, p.X, 4.3, p.Z) * CFrame.Angles(0, -0.2, 0), Color = Color3.fromRGB(170, 120, 65), Material = Enum.Material.WoodPlanks, Parent = model })
end
decor[2] = function(model, cf, p, theme) -- barrels
	for i, off in { Vector3.new(-1.2, 0, 0), Vector3.new(1.3, 0, 0.6), Vector3.new(0, 0, -1.6) } do
		Part({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 2.2, 2.2), CFrame = at(cf, p.X + off.X, 1.7, p.Z + off.Z) * FLAT, Color = i == 2 and theme.Accent or theme.Secondary, Material = Enum.Material.Metal, Parent = model })
	end
end
decor[3] = function(model, cf, p, theme) -- lamp
	Part({ Name = "Pole", Size = Vector3.new(0.5, 8, 0.5), CFrame = at(cf, p.X, 4, p.Z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	local bulb = Part({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.8, CFrame = at(cf, p.X, 8.4, p.Z), Color = theme.Accent, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
	BuildKit.Light(bulb, theme.Accent, 22, 1.5)
end
decor[4] = function(model, cf, p, theme) -- potted plant
	Part({ Name = "Pot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 2.4, 2.4), CFrame = at(cf, p.X, 1, p.Z) * FLAT, Color = Color3.fromRGB(170, 90, 60), Material = Enum.Material.Slate, Parent = model })
	Part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * 3.6, CFrame = at(cf, p.X, 3.6, p.Z), Color = Color3.fromRGB(60, 160, 70), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
	Part({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = at(cf, p.X + 0.8, 5, p.Z), Color = theme.Accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
end
decor[5] = function(model, cf, p, theme) -- bench
	Part({ Name = "Seat", Size = Vector3.new(6, 0.5, 2), CFrame = at(cf, p.X, 1.6, p.Z), Color = Color3.fromRGB(140, 95, 55), Material = Enum.Material.WoodPlanks, Parent = model })
	Part({ Name = "Back", Size = Vector3.new(6, 2, 0.4), CFrame = at(cf, p.X, 2.8, p.Z + 0.9), Color = Color3.fromRGB(140, 95, 55), Material = Enum.Material.WoodPlanks, Parent = model })
	for _, dx in { -2.6, 2.6 } do
		Part({ Name = "Leg", Size = Vector3.new(0.4, 1.4, 1.8), CFrame = at(cf, p.X + dx, 0.7, p.Z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	end
end
decor[6] = function(model, cf, p, theme) -- table
	Part({ Name = "Top", Size = Vector3.new(5, 0.4, 3.4), CFrame = at(cf, p.X, 3, p.Z), Color = theme.Secondary, Material = Enum.Material.WoodPlanks, Parent = model })
	for _, o in { Vector2.new(-2.2, -1.4), Vector2.new(2.2, -1.4), Vector2.new(-2.2, 1.4), Vector2.new(2.2, 1.4) } do
		Part({ Name = "Leg", Size = Vector3.new(0.4, 2.8, 0.4), CFrame = at(cf, p.X + o.X, 1.4, p.Z + o.Y), Color = DARK, Parent = model })
	end
	Part({ Name = "Cash", Size = Vector3.new(1.4, 0.4, 0.8), CFrame = at(cf, p.X, 3.4, p.Z), Color = Color3.fromRGB(110, 200, 110), Parent = model })
end
decor[7] = function(model, cf, p, theme) -- rug
	Part({ Name = "Rug", Size = Vector3.new(7, 0.1, 5), CFrame = at(cf, p.X, 0.06, p.Z), Color = theme.Accent, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
	Part({ Name = "Pattern", Size = Vector3.new(5, 0.12, 3), CFrame = at(cf, p.X, 0.08, p.Z), Color = theme.Secondary, Material = Enum.Material.Fabric, CanCollide = false, Parent = model })
end
decor[8] = function(model, cf, p, theme) -- shelf
	Part({ Name = "Frame", Size = Vector3.new(5, 7, 1.6), CFrame = at(cf, p.X, 3.5, p.Z), Color = Color3.fromRGB(120, 85, 50), Material = Enum.Material.WoodPlanks, Parent = model })
	for i = 1, 3 do
		Part({ Name = "Goods", Size = Vector3.new(4, 1.2, 1.2), CFrame = at(cf, p.X, i * 2 - 0.3, p.Z - 0.3), Color = Color3.fromHSV((theme.Hue + i * 0.15) % 1, 0.6, 0.9), Parent = model })
	end
end
decor[9] = function(model, cf, p, theme) -- statue
	Part({ Name = "Pedestal", Size = Vector3.new(3, 2, 3), CFrame = at(cf, p.X, 1, p.Z), Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Marble, Parent = model })
	Part({ Name = "Body", Size = Vector3.new(1.8, 3, 1.2), CFrame = at(cf, p.X, 3.5, p.Z), Color = theme.Accent, Material = Enum.Material.Foil, Parent = model })
	Part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = at(cf, p.X, 5.7, p.Z), Color = theme.Accent, Material = Enum.Material.Foil, Parent = model })
end
decor[10] = function(model, cf, p, theme) -- banner
	Part({ Name = "Pole", Size = Vector3.new(0.4, 9, 0.4), CFrame = at(cf, p.X, 4.5, p.Z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	local flag = Part({ Name = "Flag", Size = Vector3.new(3.4, 4, 0.2), CFrame = at(cf, p.X + 1.9, 6.6, p.Z), Color = theme.Accent, Material = Enum.Material.Fabric, Parent = model })
	BuildKit.SurfaceText(flag, Enum.NormalId.Front, "$", { PixelsPerStud = 20 })
end
decor[11] = function(model, cf, p, theme) -- tv screen
	Part({ Name = "Stand", Size = Vector3.new(1, 3, 1), CFrame = at(cf, p.X, 1.5, p.Z), Color = DARK, Parent = model })
	local screen = Part({ Name = "Screen", Size = Vector3.new(6, 3.6, 0.4), CFrame = at(cf, p.X, 4.8, p.Z), Color = Color3.fromRGB(15, 15, 25), Parent = model })
	BuildKit.SurfaceText(screen, Enum.NormalId.Front, "📈 $$$", { PixelsPerStud = 20, Color = theme.Accent })
	screen:AddTag("RainbowSign")
end
decor[12] = function(model, cf, p, theme) -- mini fountain
	Part({ Name = "Basin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.4, 5.6, 5.6), CFrame = at(cf, p.X, 0.7, p.Z) * FLAT, Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Marble, Parent = model })
	local water = Part({ Name = "Water", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 4.8, 4.8), CFrame = at(cf, p.X, 1.45, p.Z) * FLAT, Color = Color3.fromRGB(60, 160, 255), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, Parent = model })
	BuildKit.Particles(water, { Color = ColorSequence.new(Color3.fromRGB(160, 220, 255)), Size = BuildKit.Size(0.4), Rate = 25, Speed = NumberRange.new(5, 7), SpreadAngle = Vector2.new(15, 15), Acceleration = Vector3.new(0, -20, 0), EmissionDirection = Enum.NormalId.Top })
end
decor[13] = function(model, cf, p, theme) -- crystal
	for i, data in { { 1.4, 4, 0 }, { 1, 2.6, 25 }, { 0.9, 2.2, -30 } } do
		Part({
			Name = "Crystal",
			Size = Vector3.new(data[1], data[2], data[1]),
			CFrame = at(cf, p.X + (i - 2) * 0.9, data[2] / 2, p.Z) * CFrame.Angles(0, 0, math.rad(data[3])),
			Color = theme.Accent,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Parent = model,
		})
	end
	local core = Part({ Name = "Glow", Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = at(cf, p.X, 1, p.Z), Color = theme.Accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	BuildKit.Light(core, theme.Accent, 14, 2)
end
decor[14] = function(model, cf, p, theme) -- money pile
	for i = 1, 6 do
		Part({
			Name = "Stack",
			Size = Vector3.new(1.6, 0.6 + (i % 3) * 0.6, 0.9),
			CFrame = at(cf, p.X + ((i - 1) % 3 - 1) * 1.8, 0.3 + (i % 3) * 0.3, p.Z + (i > 3 and 1 or -1)),
			Color = Color3.fromRGB(110, 200, 110),
			Parent = model,
		})
	end
	Part({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.6, 1.6), CFrame = at(cf, p.X, 2.6, p.Z), Color = Color3.fromRGB(255, 210, 40), Material = Enum.Material.Neon, CanCollide = false, Tags = { "Spin", "Bob" }, Parent = model })
end
decor[15] = function(model, cf, p, theme) -- light pillar
	Part({ Name = "Base", Size = Vector3.new(2.4, 1, 2.4), CFrame = at(cf, p.X, 0.5, p.Z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	local pillar = Part({ Name = "Pillar", Size = Vector3.new(1.4, 14, 1.4), CFrame = at(cf, p.X, 8, p.Z), Color = theme.Accent, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
	BuildKit.Light(pillar, theme.Accent, 24, 1.5)
end
decor[16] = function(model, cf, p, theme) -- couch
	Part({ Name = "Seat", Size = Vector3.new(6, 1.4, 2.6), CFrame = at(cf, p.X, 0.9, p.Z), Color = theme.Accent:Lerp(Color3.new(0, 0, 0), 0.3), Material = Enum.Material.Fabric, Parent = model })
	Part({ Name = "Back", Size = Vector3.new(6, 2.2, 0.8), CFrame = at(cf, p.X, 2.4, p.Z + 1), Color = theme.Accent:Lerp(Color3.new(0, 0, 0), 0.4), Material = Enum.Material.Fabric, Parent = model })
	for _, dx in { -3.2, 3.2 } do
		Part({ Name = "Arm", Size = Vector3.new(0.8, 1.8, 2.6), CFrame = at(cf, p.X + dx, 1.5, p.Z), Color = theme.Accent:Lerp(Color3.new(0, 0, 0), 0.4), Material = Enum.Material.Fabric, Parent = model })
	end
end
decor[17] = function(model, cf, p, theme) -- vending machine
	Part({ Name = "Body", Size = Vector3.new(3.4, 7, 2.6), CFrame = at(cf, p.X, 3.5, p.Z), Color = theme.Accent:Lerp(Color3.new(1, 0, 0), 0.3), Parent = model })
	local glass = Part({ Name = "Glass", Size = Vector3.new(2.6, 4.4, 0.2), CFrame = at(cf, p.X, 4.2, p.Z - 1.35), Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.Neon, Transparency = 0.4, Parent = model })
	BuildKit.SurfaceText(glass, Enum.NormalId.Front, "🥤🍫\n🍬🥤", { PixelsPerStud = 20 })
end

function builders.Decor(plot, item, model: Model, cf: CFrame)
	local fn = decor[item.Model] or decor[1]
	fn(model, cf, item.LocalPos, themeOf(item))
	return {}
end

function builders.Wall(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local side = item.Side
	local wallColor = theme.Primary:Lerp(Color3.new(1, 1, 1), 0.3)
	local H = FH - 1
	if side == "Left" or side == "Right" then
		local x = side == "Left" and -41.5 or 41.5
		Part({ Name = "Wall", Size = Vector3.new(1, H, 84), CFrame = at(cf, x, H / 2, 0), Color = wallColor, Material = theme.Wall, Parent = model })
		for i = -2, 2 do
			Part({ Name = "Window", Size = Vector3.new(1.2, 5, 9), CFrame = at(cf, x, 11, i * 16), Color = Color3.fromRGB(150, 210, 255), Material = Enum.Material.Glass, Transparency = 0.4, Parent = model })
		end
	elseif side == "Back" then
		Part({ Name = "Wall", Size = Vector3.new(84, H, 1), CFrame = at(cf, 0, H / 2, 41.5), Color = wallColor, Material = theme.Wall, Parent = model })
	elseif side == "Front" then
		-- glass front with a door gap on the ground floor
		local door = item.Floor == 1
		for _, seg in { { -24, 36 }, { 24, 36 } } do
			Part({ Name = "Glass", Size = Vector3.new(seg[2], H, 0.6), CFrame = at(cf, seg[1], H / 2, -41.5), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.55, Parent = model })
		end
		if door then
			Part({ Name = "DoorTop", Size = Vector3.new(12, H - 12, 0.6), CFrame = at(cf, 0, 12 + (H - 12) / 2, -41.5), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.55, Parent = model })
			Part({ Name = "DoorFrame", Size = Vector3.new(13, 1, 1), CFrame = at(cf, 0, 12, -41.5), Color = theme.Accent, Material = Enum.Material.Neon, Parent = model })
		else
			Part({ Name = "Glass", Size = Vector3.new(12, H, 0.6), CFrame = at(cf, 0, H / 2, -41.5), Color = Color3.fromRGB(170, 220, 255), Material = Enum.Material.Glass, Transparency = 0.55, Parent = model })
		end
		for _, x in { -36, -12, 12, 36 } do
			Part({ Name = "Mullion", Size = Vector3.new(0.8, H, 0.8), CFrame = at(cf, x, H / 2, -41.5), Color = DARK, Material = Enum.Material.Metal, Parent = model })
		end
	elseif side == "Pillars" then
		for _, o in { Vector2.new(-41.5, -41.5), Vector2.new(41.5, -41.5), Vector2.new(-41.5, 41.5), Vector2.new(41.5, 41.5), Vector2.new(0, 41.5), Vector2.new(-41.5, 0), Vector2.new(41.5, 0) } do
			Part({ Name = "Pillar", Size = Vector3.new(2.4, FH, 2.4), CFrame = at(cf, o.X, FH / 2 - 0.5, o.Y), Color = theme.Secondary, Material = Enum.Material.Concrete, Parent = model })
		end
	elseif side == "Trim" then
		for _, y in { 0.3, H - 0.3 } do
			for _, data in {
				{ Vector3.new(84, 0.5, 0.5), Vector3.new(0, y, -42.1) },
				{ Vector3.new(84, 0.5, 0.5), Vector3.new(0, y, 42.1) },
				{ Vector3.new(0.5, 0.5, 84), Vector3.new(-42.1, y, 0) },
				{ Vector3.new(0.5, 0.5, 84), Vector3.new(42.1, y, 0) },
			} do
				Part({ Name = "Trim", Size = data[1], CFrame = at(cf, data[2].X, data[2].Y, data[2].Z), Color = theme.Accent, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
			end
		end
	end
	return {}
end

function builders.Boost(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local p = item.LocalPos
	local color = Color3.fromHSV((theme.Hue + 0.5 + item.Slot * 0.1) % 1, 0.8, 1)
	local sign = Part({ Name = "Sign", Size = Vector3.new(10, 5, 0.6), CFrame = at(cf, p.X, p.Y, p.Z), Color = Color3.fromRGB(20, 20, 30), Parent = model })
	Part({ Name = "Frame", Size = Vector3.new(10.6, 5.6, 0.4), CFrame = at(cf, p.X, p.Y, p.Z + 0.4), Color = color, Material = Enum.Material.Neon, Parent = model })
	BuildKit.SurfaceText(sign, Enum.NormalId.Front, "x" .. item.Multiplier .. " BOOST", { PixelsPerStud = 20, Color = color, Brightness = 3 })
	BuildKit.Light(sign, color, 20, 2)
	return {}
end

function builders.Conveyor(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local color = item.Slot == 1 and theme.Accent or Color3.fromRGB(0, 230, 255)
	for i = 0, 7 do
		local x = Items.BeltStartX + 6 + i * 8.5 + (item.Slot - 1) * 4
		Part({ Name = "Chevron", Size = Vector3.new(0.6, 0.1, 3.6), CFrame = at(cf, x, 1.25, Items.BeltZ) * CFrame.Angles(0, math.rad(item.Slot == 1 and 30 or -30), 0), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	end
	if item.Slot == 2 then
		for _, dz in { -3.3, 3.3 } do
			Part({ Name = "Glow", Size = Vector3.new(Items.BeltEndX - Items.BeltStartX, 0.3, 0.3), CFrame = at(cf, (Items.BeltEndX + Items.BeltStartX) / 2, 2.1, Items.BeltZ + dz), Color = color, Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		end
	end
	return {}
end

-- Specials ---------------------------------------------------------------
local function monument(model, cf, p, color, shape)
	Part({ Name = "Pedestal", Size = Vector3.new(8, 2, 8), CFrame = at(cf, p.X, 1, p.Z), Color = DARK, Material = Enum.Material.Marble, Parent = model })
	local core
	if shape == "Ring" then
		core = Part({ Name = "Portal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.8, 9, 9), CFrame = at(cf, p.X, 7.5, p.Z) * CFrame.Angles(0, math.rad(90), 0), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
		Part({ Name = "Void", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 7.4, 7.4), CFrame = at(cf, p.X, 7.5, p.Z) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(10, 0, 30), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	elseif shape == "Crystal" then
		core = Part({ Name = "Gem", Size = Vector3.new(3.5, 6, 3.5), CFrame = at(cf, p.X, 7, p.Z) * CFrame.Angles(0, math.rad(45), 0), Color = color, Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false, Tags = { "Spin", "Bob" }, Parent = model })
	elseif shape == "Tower" then
		Part({ Name = "Base", Size = Vector3.new(4, 10, 4), CFrame = at(cf, p.X, 7, p.Z), Color = Color3.fromRGB(20, 20, 30), Material = Enum.Material.Metal, Parent = model })
		core = Part({ Name = "Holo", Size = Vector3.new(5, 5, 5), CFrame = at(cf, p.X, 15, p.Z), Color = color, Material = Enum.Material.ForceField, CanCollide = false, Tags = { "Spin" }, Parent = model })
	elseif shape == "Dragon" then
		Part({ Name = "Body", Size = Vector3.new(3, 3, 6), CFrame = at(cf, p.X, 4.5, p.Z), Color = color, Material = Enum.Material.Ice, Parent = model })
		Part({ Name = "Neck", Size = Vector3.new(1.6, 4, 1.6), CFrame = at(cf, p.X, 7, p.Z - 2.6) * CFrame.Angles(math.rad(-25), 0, 0), Color = color, Material = Enum.Material.Ice, Parent = model })
		core = Part({ Name = "Head", Size = Vector3.new(2.2, 2, 3), CFrame = at(cf, p.X, 9.2, p.Z - 3.8), Color = color, Material = Enum.Material.Ice, Parent = model })
		for _, dx in { -3, 3 } do
			Part({ Name = "Wing", Size = Vector3.new(4, 0.3, 3.6), CFrame = at(cf, p.X + dx, 6.4, p.Z + 0.5) * CFrame.Angles(0, 0, math.rad(dx > 0 and -25 or 25)), Color = Color3.fromRGB(150, 220, 255), Material = Enum.Material.Glass, Transparency = 0.3, Parent = model })
		end
	else -- Orb / Fountain / Reactor
		core = Part({ Name = "Orb", Shape = Enum.PartType.Ball, Size = Vector3.one * 5, CFrame = at(cf, p.X, 6.5, p.Z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse", "Bob" }, Parent = model })
		for i = 1, 2 do
			Part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 7 + i, 7 + i), CFrame = at(cf, p.X, 6.5, p.Z) * CFrame.Angles(math.rad(60 * i), 0, 0), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Spin" }, Parent = model })
		end
	end
	BuildKit.Light(core, color, 30, 2.5)
	BuildKit.Particles(core, { Color = ColorSequence.new(color, Color3.new(1, 1, 1)), Size = BuildKit.Size(0.8), Rate = 20, Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(180, 180) })
	return core
end

local SPECIAL_SHAPES = {
	["Money Fountain"] = "Orb",
	["Diamond Vault"] = "Crystal",
	["Lava Reactor"] = "Orb",
	["Ice Dragon Statue"] = "Dragon",
	["Hologram Tower"] = "Tower",
	["Galaxy Portal"] = "Ring",
}

function builders.Special(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local p = item.LocalPos
	if item.Effect == "Bunker" then
		local concrete = Color3.fromRGB(120, 120, 125)
		local W, D, H = 11, 9, 8
		-- walls (door on the -X side)
		Part({ Name = "Roof", Size = Vector3.new(W + 1, 1.2, D + 1), CFrame = at(cf, p.X, H + 0.6, p.Z), Color = concrete, Material = Enum.Material.Concrete, Parent = model })
		Part({ Name = "WallBack", Size = Vector3.new(W, H, 1), CFrame = at(cf, p.X, H / 2, p.Z + D / 2), Color = concrete, Material = Enum.Material.Concrete, Parent = model })
		Part({ Name = "WallFront", Size = Vector3.new(W, H, 1), CFrame = at(cf, p.X, H / 2, p.Z - D / 2), Color = concrete, Material = Enum.Material.Concrete, Parent = model })
		Part({ Name = "WallRight", Size = Vector3.new(1, H, D), CFrame = at(cf, p.X + W / 2, H / 2, p.Z), Color = concrete, Material = Enum.Material.Concrete, Parent = model })
		Part({ Name = "WallLeftA", Size = Vector3.new(1, H, 2.5), CFrame = at(cf, p.X - W / 2, H / 2, p.Z - D / 2 + 1.25), Color = concrete, Material = Enum.Material.Concrete, Parent = model })
		Part({ Name = "WallLeftB", Size = Vector3.new(1, H, 2.5), CFrame = at(cf, p.X - W / 2, H / 2, p.Z + D / 2 - 1.25), Color = concrete, Material = Enum.Material.Concrete, Parent = model })
		Part({ Name = "WallLeftTop", Size = Vector3.new(1, 2, 4), CFrame = at(cf, p.X - W / 2, H - 1, p.Z), Color = concrete, Material = Enum.Material.Concrete, Parent = model })
		local sign = Part({ Name = "Sign", Size = Vector3.new(0.3, 1.6, 4), CFrame = at(cf, p.X - W / 2 - 0.7, H + 1.6, p.Z), Color = Color3.fromRGB(255, 210, 0), Material = Enum.Material.Neon, Parent = model })
		BuildKit.SurfaceText(sign, Enum.NormalId.Left, "☢️ BUNKER", { PixelsPerStud = 20, Color = Color3.new(0, 0, 0) })
		local lamp = Part({ Name = "Lamp", Size = Vector3.new(2, 0.3, 2), CFrame = at(cf, p.X, H - 0.3, p.Z), Color = Color3.fromRGB(255, 80, 60), Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
		BuildKit.Light(lamp, Color3.fromRGB(255, 120, 90), 14, 1.5)
		return {
			ShelterCF = at(cf, p.X, H / 2, p.Z),
			ShelterSize = Vector3.new(W - 1, H, D - 1),
			Door = at(cf, p.X - W / 2 - 2, 2.5, p.Z).Position,
		}
	elseif item.Effect == "Shield" then
		local color = Color3.fromRGB(80, 200, 255)
		Part({ Name = "Base", Size = Vector3.new(6, 1.5, 6), CFrame = at(cf, p.X, 0.75, p.Z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
		Part({ Name = "Pylon", Size = Vector3.new(1.6, 9, 1.6), CFrame = at(cf, p.X, 6, p.Z), Color = Color3.fromRGB(70, 70, 90), Material = Enum.Material.Metal, Parent = model })
		local orb = Part({ Name = "Emitter", Shape = Enum.PartType.Ball, Size = Vector3.one * 3, CFrame = at(cf, p.X, 11.5, p.Z), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
		BuildKit.Light(orb, color, 30, 3)
		BuildKit.Billboard(orb, "🛡️ NUKE SHIELD", { Size = UDim2.fromOffset(150, 28), Offset = Vector3.new(0, 3, 0), Color = color, MaxDistance = 60 })
		local dome = Part({
			Name = "ShieldDome",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * (plot.ShieldRadius * 2),
			Position = plot.ShieldCenter,
			Color = color,
			Material = Enum.Material.ForceField,
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = model,
		})
		dome:AddTag("ShieldDome")
		return { ShieldCenter = plot.ShieldCenter, ShieldRadius = plot.ShieldRadius }
	end
	local color = theme.Accent
	local core = monument(model, cf, p, color, SPECIAL_SHAPES[item.Name] or "Orb")
	BuildKit.Billboard(core, item.Name .. " (+" .. math.floor((item.Bonus or 0) * 100 + 0.5) .. "%)", { Size = UDim2.fromOffset(180, 28), Offset = Vector3.new(0, 5, 0), Color = shade(color, 0.4), MaxDistance = 60 })
	return {}
end

function builders.Trophy(plot, item, model: Model, cf: CFrame)
	local theme = themeOf(item)
	local p = item.LocalPos
	local gold = Color3.fromRGB(255, 205, 40)
	Part({ Name = "Shelf", Size = Vector3.new(8, 0.6, 4), CFrame = at(cf, p.X, p.Y - 3, p.Z + 2), Color = theme.Secondary, Material = Enum.Material.Marble, Parent = model })
	Part({ Name = "Base", Size = Vector3.new(2.6, 1, 2.6), CFrame = at(cf, p.X, p.Y - 2.2, p.Z + 2), Color = DARK, Parent = model })
	Part({ Name = "Stem", Size = Vector3.new(0.8, 1.6, 0.8), CFrame = at(cf, p.X, p.Y - 0.9, p.Z + 2), Color = gold, Material = Enum.Material.Foil, Parent = model })
	local cup = Part({ Name = "Cup", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 3, 3), CFrame = at(cf, p.X, p.Y + 1.4, p.Z + 2) * FLAT, Color = gold, Material = Enum.Material.Foil, Reflectance = 0.3, Tags = { "Spin" }, Parent = model })
	BuildKit.Light(cup, gold, 20, 2)
	BuildKit.Billboard(cup, "🏆 FLOOR " .. item.Floor .. " COMPLETE", { Size = UDim2.fromOffset(190, 28), Offset = Vector3.new(0, 3, 0), Color = gold, MaxDistance = 60 })
	return {}
end

-- Roof -----------------------------------------------------------------------
local roofBuilders = {}

roofBuilders.Helipad = function(plot, model, cf, p, ownerName)
	Part({ Name = "Roof", Size = Vector3.new(84, 1, 84), CFrame = at(cf, 0, -0.5, 0), Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Concrete, Parent = model })
	Part({ Name = "Pad", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 26, 26), CFrame = at(cf, p.X, 0.1, p.Z) * FLAT, Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Asphalt, Parent = model })
	Part({ Name = "H1", Size = Vector3.new(1.6, 0.25, 10), CFrame = at(cf, p.X - 3, 0.2, p.Z), Color = Color3.fromRGB(255, 220, 0), Material = Enum.Material.Neon, Parent = model })
	Part({ Name = "H2", Size = Vector3.new(1.6, 0.25, 10), CFrame = at(cf, p.X + 3, 0.2, p.Z), Color = Color3.fromRGB(255, 220, 0), Material = Enum.Material.Neon, Parent = model })
	Part({ Name = "H3", Size = Vector3.new(6, 0.25, 1.6), CFrame = at(cf, p.X, 0.2, p.Z), Color = Color3.fromRGB(255, 220, 0), Material = Enum.Material.Neon, Parent = model })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local light = Part({ Name = "Light", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = at(cf, p.X + math.cos(a) * 13, 0.5, p.Z + math.sin(a) * 13), Color = Color3.fromRGB(80, 255, 120), Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
		light.Name = "Light" .. i
	end
	-- railing
	for _, data in {
		{ Vector3.new(84, 1, 0.4), Vector3.new(0, 1.5, -42) },
		{ Vector3.new(84, 1, 0.4), Vector3.new(0, 1.5, 42) },
		{ Vector3.new(0.4, 1, 84), Vector3.new(-42, 1.5, 0) },
		{ Vector3.new(0.4, 1, 84), Vector3.new(42, 1.5, 0) },
	} do
		Part({ Name = "Rail", Size = data[1], CFrame = at(cf, data[2].X, data[2].Y, data[2].Z), Color = Color3.fromRGB(200, 200, 210), Material = Enum.Material.Metal, Parent = model })
	end
end
roofBuilders.Antenna = function(plot, model, cf, p)
	local truss = Instance.new("TrussPart")
	truss.Anchored = true
	truss.Size = Vector3.new(2, 40, 2)
	truss.CFrame = at(cf, p.X, 20, p.Z)
	truss.Color = Color3.fromRGB(180, 180, 190)
	truss.Parent = model
	local tip = Part({ Name = "Tip", Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = at(cf, p.X, 41, p.Z), Color = Color3.fromRGB(255, 40, 40), Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
	BuildKit.Light(tip, Color3.fromRGB(255, 40, 40), 40, 3)
end
roofBuilders.Pool = function(plot, model, cf, p)
	Part({ Name = "Rim", Size = Vector3.new(20, 1.4, 14), CFrame = at(cf, p.X, 0.7, p.Z), Color = Color3.fromRGB(230, 230, 235), Material = Enum.Material.Marble, Parent = model })
	Part({ Name = "Water", Size = Vector3.new(18, 0.4, 12), CFrame = at(cf, p.X, 1.25, p.Z), Color = Color3.fromRGB(40, 170, 255), Material = Enum.Material.Glass, Transparency = 0.25, CanCollide = false, Parent = model })
	Part({ Name = "Board", Size = Vector3.new(1.6, 0.3, 6), CFrame = at(cf, p.X, 2.6, p.Z - 8), Color = Color3.fromRGB(240, 240, 240), Parent = model })
end
roofBuilders.Billboard = function(plot, model, cf, p, ownerName)
	for _, dx in { -14, 14 } do
		Part({ Name = "Leg", Size = Vector3.new(1, 12, 1), CFrame = at(cf, p.X + dx, 6, p.Z), Color = DARK, Material = Enum.Material.Metal, Parent = model })
	end
	local board = Part({ Name = "Board", Size = Vector3.new(34, 10, 0.8), CFrame = at(cf, p.X, 17, p.Z), Color = Color3.fromRGB(15, 15, 25), Parent = model })
	local _, label = BuildKit.SurfaceText(board, Enum.NormalId.Front, string.upper(ownerName or "MY") .. "'S EMPIRE", { PixelsPerStud = 14, Brightness = 3 })
	label:SetAttribute("Rainbow", true)
	board:AddTag("RainbowSign")
	BuildKit.Light(board, Color3.fromRGB(255, 220, 120), 40, 2)
end
roofBuilders.Fireworks = function(plot, model, cf, p)
	Part({ Name = "Crate", Size = Vector3.new(5, 2, 5), CFrame = at(cf, p.X, 1, p.Z), Color = Color3.fromRGB(170, 40, 40), Material = Enum.Material.WoodPlanks, Parent = model })
	for i = 1, 4 do
		local tube = Part({ Name = "Tube", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 0.9, 0.9), CFrame = at(cf, p.X + ((i - 1) % 2 - 0.5) * 2, 3.5, p.Z + ((i - 1) // 2 - 0.5) * 2) * FLAT, Color = Color3.fromHSV(i / 4, 0.8, 1), Parent = model })
		tube.Name = "Tube" .. i
	end
	model:AddTag("Fireworks")
	model:SetAttribute("LaunchPos", at(cf, p.X, 5, p.Z).Position)
end
roofBuilders.Crown = function(plot, model, cf, p)
	local gold = Color3.fromRGB(255, 205, 40)
	Part({ Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 12, 12), CFrame = at(cf, p.X, 4, p.Z) * FLAT, Color = gold, Material = Enum.Material.Foil, Reflectance = 0.3, Parent = model })
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Part({ Name = "Spike", Size = Vector3.new(1.4, 4, 1.4), CFrame = at(cf, p.X + math.cos(a) * 5.4, 7.2, p.Z + math.sin(a) * 5.4) * CFrame.Angles(0, -a, 0), Color = gold, Material = Enum.Material.Foil, Parent = model })
		local gem = Part({ Name = "Jewel", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, CFrame = at(cf, p.X + math.cos(a) * 5.9, 4, p.Z + math.sin(a) * 5.9), Color = Color3.fromHSV(i / 8, 0.8, 1), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
		gem.Name = "Jewel" .. i
	end
	BuildKit.Light(model:FindFirstChild("Band") :: BasePart, gold, 40, 3)
end

function builders.Roof(plot, item, model: Model, cf: CFrame, ownerName: string?)
	local fn = roofBuilders[item.Model]
	if fn then
		fn(plot, model, cf, item.LocalPos, ownerName)
	end
	return {}
end

function builders.Secret(plot, item, model: Model)
	local p = item.LocalPos
	local cf = plot.CFrame
	local color = item.Color or Color3.fromRGB(255, 255, 255)
	Part({ Name = "Pedestal", Size = Vector3.new(4, 2, 4), CFrame = at(cf, p.X, 2, p.Z), Color = Color3.fromRGB(35, 35, 45), Material = Enum.Material.Marble, Parent = model })
	Part({ Name = "Trim", Size = Vector3.new(4.4, 0.3, 4.4), CFrame = at(cf, p.X, 3.1, p.Z), Color = color, Material = Enum.Material.Neon, Parent = model })
	local relic = Part({
		Name = "Relic",
		Size = Vector3.one * 1.8,
		CFrame = at(cf, p.X, 5.2, p.Z) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin", "Bob" },
		Parent = model,
	})
	BuildKit.Light(relic, color, 16, 2)
	BuildKit.Particles(relic, { Color = ColorSequence.new(color, Color3.new(1, 1, 1)), Size = BuildKit.Size(0.5), Rate = 10, SpreadAngle = Vector2.new(180, 180) })
	BuildKit.Billboard(relic, "🕵️ " .. item.Name, { Size = UDim2.fromOffset(170, 26), Offset = Vector3.new(0, 2.4, 0), Color = color, MaxDistance = 60 })
	return {}
end

-- Build an item into the plot. Returns (model, extra)
function TycoonBuilder.BuildItem(plot, item, ownerName: string?)
	local model = BuildKit.Model(item.Id, plot.Items)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local floorCF = TycoonBuilder.FloorCF(plot, math.max(item.Floor, 1))
	local builder = builders[item.Kind]
	local extra = {}
	if builder then
		extra = builder(plot, item, model, floorCF, ownerName) or {}
	end
	return model, extra
end

-- world position of an item (for knockouts, tornado hits, effects)
function TycoonBuilder.ItemWorldPos(plot, item): Vector3
	if item.Kind == "Secret" then
		return (plot.CFrame * CFrame.new(item.LocalPos)).Position
	end
	local floorCF = TycoonBuilder.FloorCF(plot, math.max(item.Floor, 1))
	local p = item.LocalPos or Vector3.new(0, 0, 0)
	return (floorCF * CFrame.new(p.X, p.Y + 3, p.Z)).Position
end

return TycoonBuilder
