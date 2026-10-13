--[[
	WorldBuilder - builds the whole map from code (terrain + parts):

	  centre        lobby plaza, spawn, boards, PUBLIC NUKE BUNKER
	  ring (r=270)  8 tycoon towers (TycoonService) + ring road
	  north         terraced snowy mountain with a hidden cave
	  north-east    waterfall cliff
	  south         lake with an island and a dock
	  east          dense forest, giant tree house, launch pad -> cloud island
	  north-west    graveyard
	  west          obby (ObbyService)
	  far corner    the world's edge

	Secret spots are exposed in WorldBuilder.SecretSpots for SecretService.
]]
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local BuildKit = require(script.Parent.BuildKit)

local Part = BuildKit.Part

local WorldBuilder = {}
WorldBuilder.Folder = nil :: Folder?
WorldBuilder.LeaderboardBody = nil :: Frame?
WorldBuilder.SecretSpots = {} :: { [string]: Vector3 }
WorldBuilder.LaunchPads = {}
WorldBuilder.Shelter = nil -- public bunker { CFrame, Size, Door }

local PLAZA_RADIUS = 70
local MAP_HALF = 1000
local MOUNTAIN = Vector3.new(0, 0, -720)
local LAKE = Vector3.new(0, 0, 650)
local LAKE_RADIUS = 150
local ISLAND = Vector3.new(40, 0, 690)
local CAVE = Vector3.new(0, 0, -620)
local WATERFALL = Vector3.new(240, 0, -560)
local GIANT_TREE = Vector3.new(620, 0, -150)
local LAUNCH_PAD = Vector3.new(560, 0, 380)
local CLOUD = Vector3.new(720, 222, 300)
local GRAVEYARD = Vector3.new(-540, 0, -420)
local EDGE = Vector3.new(965, 0, 965)
local BUNKER = Vector3.new(-88, 0, -88)

local terrain = workspace.Terrain

---------------------------------------------------------------------------
-- Lighting / physics setup
---------------------------------------------------------------------------
local function setupLighting()
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	Lighting.ClockTime = Config.DayNight.StartTime or 14
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(90, 90, 110)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 160)
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GeographicLatitude = 30

	local sky = Instance.new("Sky")
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 9
	sky.StarCount = 3000
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(199, 220, 255)
	atmosphere.Decay = Color3.fromRGB(106, 112, 160)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.7
	bloom.Size = 28
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.06
	rays.Spread = 0.8
	rays.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "BaseColorCorrection"
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	cc.Brightness = 0.02
	cc.Parent = Lighting

	terrain.WaterColor = Color3.fromRGB(40, 140, 200)
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.4
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 8
end

local function setupCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Players")
		PhysicsService:CollisionGroupSetCollidable("Players", "Players", true)
	end)
	local function setGroup(character: Model)
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") then
				d.CollisionGroup = "Players"
			end
		end
		character.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.CollisionGroup = "Players"
			end
		end)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(setGroup)
		if player.Character then
			setGroup(player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

---------------------------------------------------------------------------
-- Small builders
---------------------------------------------------------------------------
local function tree(parent: Instance, position: Vector3, scale: number, rng: Random, dead: boolean?)
	local model = BuildKit.Model("Tree", parent)
	local trunkHeight = 8 * scale
	Part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = dead and Color3.fromRGB(60, 50, 45) or Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
		Parent = model,
	})
	if dead then
		for i = 1, 3 do
			local a = rng:NextNumber(0, math.pi * 2)
			Part({
				Name = "Branch",
				Size = Vector3.new(0.6 * scale, 4 * scale, 0.6 * scale),
				CFrame = CFrame.new(position + Vector3.new(math.cos(a), trunkHeight * (0.55 + i * 0.12), math.sin(a))) * CFrame.Angles(math.cos(a) * 0.9, 0, math.sin(a) * 0.9),
				Color = Color3.fromRGB(60, 50, 45),
				Material = Enum.Material.Wood,
				CanCollide = false,
				Parent = model,
			})
		end
		return model
	end
	local leafColor = Color3.fromHSV(0.26 + rng:NextNumber() * 0.1, 0.6, 0.5 + rng:NextNumber() * 0.25)
	for i = 1, 3 do
		local size = (7 - i * 1.3) * scale
		Part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			Position = position + Vector3.new((rng:NextNumber() - 0.5) * 2 * scale, trunkHeight + (i - 1) * 2.4 * scale, (rng:NextNumber() - 0.5) * 2 * scale),
			Color = leafColor,
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
	end
	return model
end

local function lamp(parent: Instance, position: Vector3, color: Color3)
	local model = BuildKit.Model("Lamp", parent)
	Part({ Size = Vector3.new(0.8, 12, 0.8), Position = position + Vector3.new(0, 6, 0), Color = Color3.fromRGB(40, 40, 50), Material = Enum.Material.Metal, Parent = model })
	local bulb = Part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2, Position = position + Vector3.new(0, 12.6, 0), Color = color, Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
	BuildKit.Light(bulb, color, 26, 1.5)
end

-- Board standing on the ground at `position`, facing `lookAt`
function WorldBuilder.Board(parent: Instance, position: Vector3, lookAt: Vector3, title: string, color: Color3)
	local model = BuildKit.Model(title .. "Board", parent)
	local cf = CFrame.lookAt(position + Vector3.new(0, 13, 0), Vector3.new(lookAt.X, position.Y + 13, lookAt.Z))
	local board = Part({ Name = "Screen", Size = Vector3.new(26, 20, 1), CFrame = cf, Color = Color3.fromRGB(20, 22, 35), Parent = model })
	Part({ Name = "Frame", Size = Vector3.new(28, 22, 0.8), CFrame = cf * CFrame.new(0, 0, 0.6), Color = color, Material = Enum.Material.Neon, Parent = model })
	for _, x in { -9, 9 } do
		Part({ Name = "Leg", Size = Vector3.new(1.5, 3, 1.5), CFrame = cf * CFrame.new(x, -11.5, 0.6), Color = Color3.fromRGB(40, 40, 50), Material = Enum.Material.Metal, Parent = model })
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 25
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = board
	local header = Instance.new("TextLabel")
	header.Name = "Title"
	header.Size = UDim2.new(1, 0, 0.16, 0)
	header.BackgroundColor3 = color
	header.Text = title
	header.TextScaled = true
	header.Font = Enum.Font.FredokaOne
	header.TextColor3 = Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = header
	header.Parent = gui
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -30, 0.82, -10)
	body.Position = UDim2.new(0, 15, 0.17, 5)
	body.BackgroundTransparency = 1
	body.Parent = gui
	return gui, body, model, cf
end

local function infoText(body: Frame, lines: { string })
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 46)
		label.BackgroundTransparency = 1
		label.Text = line
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.LayoutOrder = i
		label.Parent = body
	end
end

local function pathSegment(parent: Instance, a: Vector3, b: Vector3, width: number)
	local mid = (a + b) / 2
	local length = (b - a).Magnitude
	Part({
		Name = "Path",
		Size = Vector3.new(width, 0.4, length),
		CFrame = CFrame.lookAt(Vector3.new(mid.X, 0.2, mid.Z), Vector3.new(b.X, 0.2, b.Z)),
		Color = Color3.fromRGB(170, 150, 120),
		Material = Enum.Material.Cobblestone,
		Parent = parent,
	})
end

---------------------------------------------------------------------------
-- Terrain
---------------------------------------------------------------------------
local function buildTerrain()
	terrain:Clear()
	terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(MAP_HALF * 2 + 48, 16, MAP_HALF * 2 + 48), Enum.Material.Grass)

	-- terraced mountain (walkable: 4-stud steps)
	for i = 0, 40 do
		local radius = 230 - i * 5.2
		local material = i < 8 and Enum.Material.Grass or (i < 30 and Enum.Material.Rock or Enum.Material.Snow)
		terrain:FillCylinder(CFrame.new(MOUNTAIN.X, i * 4 + 2, MOUNTAIN.Z), 4, radius, material)
	end
	-- cave: tunnel + room
	terrain:FillBlock(CFrame.new(CAVE.X, 6, -540), Vector3.new(12, 12, 124), Enum.Material.Air)
	terrain:FillBall(Vector3.new(CAVE.X, 22, CAVE.Z), 22, Enum.Material.Air)

	-- lake
	local lakeCF = CFrame.new(LAKE.X, 0, LAKE.Z)
	terrain:FillCylinder(lakeCF * CFrame.new(0, -12, 0), 28, LAKE_RADIUS, Enum.Material.Air)
	terrain:FillCylinder(lakeCF * CFrame.new(0, -1, 0), 2, LAKE_RADIUS + 16, Enum.Material.Sand)
	terrain:FillCylinder(lakeCF * CFrame.new(0, -12, 0), 28, LAKE_RADIUS, Enum.Material.Air)
	terrain:FillCylinder(lakeCF * CFrame.new(0, -22, 0), 4, LAKE_RADIUS, Enum.Material.Sand)
	terrain:FillCylinder(lakeCF * CFrame.new(0, -11, 0), 18, LAKE_RADIUS, Enum.Material.Water)
	-- island
	terrain:FillCylinder(CFrame.new(ISLAND.X, -11, ISLAND.Z), 22, 32, Enum.Material.Sand)
	terrain:FillCylinder(CFrame.new(ISLAND.X, 0, ISLAND.Z), 4, 26, Enum.Material.Grass)
end

---------------------------------------------------------------------------
-- Lobby
---------------------------------------------------------------------------
local function buildLobby(world: Folder)
	local lobby = BuildKit.Model("Lobby", world)
	Part({
		Name = "Plaza",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, PLAZA_RADIUS * 2, PLAZA_RADIUS * 2),
		CFrame = CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(205, 205, 215),
		Material = Enum.Material.Slate,
		Parent = lobby,
	})
	Part({
		Name = "PlazaRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, PLAZA_RADIUS * 2 + 4, PLAZA_RADIUS * 2 + 4),
		CFrame = CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 196, 0),
		Material = Enum.Material.Neon,
		Parent = lobby,
	})

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = Vector3.new(0, 1, 0)
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(0, 200, 255)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	local titleAnchor = Part({ Name = "Title", Size = Vector3.one, Position = Vector3.new(0, 34, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, Parent = lobby })
	local _, titleLabel = BuildKit.Billboard(titleAnchor, Config.GameName, { Size = UDim2.fromScale(44, 9), Offset = Vector3.zero, MaxDistance = 900, Color = Color3.fromRGB(255, 210, 40) })
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 120)),
	})
	gradient.Rotation = 90
	gradient.Parent = titleLabel

	local core = Part({
		Name = "Crystal",
		Size = Vector3.new(4, 4, 4),
		CFrame = CFrame.new(0, 20, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = Color3.fromRGB(255, 196, 0),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin", "Bob" },
		Parent = lobby,
	})
	BuildKit.Light(core, Color3.fromRGB(255, 200, 60), 40, 3)
	BuildKit.Particles(core, { Color = ColorSequence.new(Color3.fromRGB(255, 220, 80)), Size = BuildKit.Size(1), Rate = 25, Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(180, 180) })

	-- boards
	local _, lbBody, _, lbCF = WorldBuilder.Board(lobby, Vector3.new(65, 0, 65), Vector3.zero, "🏆 TOP EARNERS", Color3.fromRGB(255, 180, 0))
	WorldBuilder.LeaderboardBody = lbBody
	-- secret: something is hiding behind the leaderboard...
	WorldBuilder.SecretSpots.Board = (lbCF * CFrame.new(6, -10.5, 3.5)).Position

	local _, howBody = WorldBuilder.Board(lobby, Vector3.new(-82, 0, 48), Vector3.zero, "📜 HOW TO PLAY", Color3.fromRGB(0, 170, 255))
	infoText(howBody, {
		"🏢 8-floor tower, 500+ upgrades",
		"💵 Step on buttons or open BUILD",
		"🏦 Collect cash at any VAULT pad",
		"🛗 Elevator = travel between floors",
		"👥 DUO: build one tower with a friend",
		"🔄 Rebirth for a permanent multiplier",
		"🕵️ Find 12 secrets for +5% each!",
		"💤 Your tower earns while you're offline",
	})
	local _, mgBody = WorldBuilder.Board(lobby, Vector3.new(-48, 0, 82), Vector3.zero, "🎮 MINIGAMES", Color3.fromRGB(170, 70, 255))
	local mgLines = {}
	for _, mg in Config.Minigames.Games do
		table.insert(mgLines, "• " .. mg.DisplayName .. ": " .. mg.Description)
	end
	table.insert(mgLines, "Every " .. math.floor(Config.Minigames.Intermission / 60 * 10) / 10 .. " min - press JOIN!")
	table.insert(mgLines, "🏃 Obby: follow the west road")
	infoText(mgBody, mgLines)
	local _, dzBody = WorldBuilder.Board(lobby, Vector3.new(65, 0, -65), Vector3.zero, "☢️ DISASTERS", Color3.fromRGB(255, 70, 40))
	infoText(dzBody, {
		"☢️ NUKES: get inside a bunker in 30s!",
		"🟩 Follow the green beam to safety",
		"☄️ Meteor storms leave cash crystals",
		"🌪️ Tornadoes fling you and wreck stuff",
		"🛸 UFOs abduct players & drop cash",
		"🛡️ Nuke Shield (floor 2) protects all",
		"🔧 Wrecked upgrades repair themselves",
	})

	-- ring road + lanes
	for i = 0, 47 do
		local a1 = i / 48 * math.pi * 2
		local a2 = (i + 1) / 48 * math.pi * 2
		pathSegment(lobby, Vector3.new(math.cos(a1) * 195, 0, math.sin(a1) * 195), Vector3.new(math.cos(a2) * 195, 0, math.sin(a2) * 195), 12)
		if i % 4 == 2 then
			lamp(lobby, Vector3.new(math.cos(a1) * 185, 0, math.sin(a1) * 185), Color3.fromHSV(i / 48, 0.7, 1))
		end
	end
	local lanes = {
		{ Vector3.new(0, 0, -PLAZA_RADIUS), Vector3.new(0, 0, -480) }, -- north: mountain
		{ Vector3.new(0, 0, PLAZA_RADIUS), Vector3.new(0, 0, 486) }, -- south: lake
		{ Vector3.new(-PLAZA_RADIUS, 0, 0), Vector3.new(-410, 0, 0) }, -- west: obby
		{ Vector3.new(PLAZA_RADIUS, 0, 0), Vector3.new(430, 0, 0) }, -- east: forest
	}
	for _, lane in lanes do
		pathSegment(lobby, lane[1], lane[2], 14)
		local dir = (lane[2] - lane[1]).Unit
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local length = (lane[2] - lane[1]).Magnitude
		for d = 40, length, 50 do
			local p = lane[1] + dir * d
			if math.abs(p.Magnitude - 195) > 16 then
				lamp(lobby, p + side * 11, Color3.fromRGB(255, 230, 160))
			end
		end
	end
	-- spokes from the ring road to every plot gate
	for index = 1, Config.MaxPlots do
		local a = math.rad(22.5 + (index - 1) * (360 / Config.MaxPlots))
		pathSegment(lobby, Vector3.new(math.cos(a) * 195, 0, math.sin(a) * 195), Vector3.new(math.cos(a) * 212, 0, math.sin(a) * 212), 12)
	end
	-- signposts
	for _, data in { { Vector3.new(14, 0, -110), "⛰️ MOUNTAIN" }, { Vector3.new(-14, 0, 110), "🌊 LAKE" }, { Vector3.new(-110, 0, -14), "🏃 OBBY" }, { Vector3.new(110, 0, 14), "🌲 FOREST" } } do
		local post = Part({ Name = "SignPost", Size = Vector3.new(0.8, 7, 0.8), Position = data[1] + Vector3.new(0, 3.5, 0), Color = Color3.fromRGB(110, 75, 45), Material = Enum.Material.Wood, Parent = lobby })
		BuildKit.Billboard(post, data[2], { Size = UDim2.fromOffset(160, 36), Offset = Vector3.new(0, 5, 0), MaxDistance = 150 })
	end
	return lobby
end

local function buildBunker(world: Folder)
	local model = BuildKit.Model("PublicBunker", world)
	local cf = CFrame.lookAt(BUNKER, Vector3.new(0, 0, 0))
	local concrete = Color3.fromRGB(125, 125, 130)
	local W, H, T = 36, 12, 2
	local function wall(size: Vector3, offset: Vector3)
		return Part({ Name = "Wall", Size = size, CFrame = cf * CFrame.new(offset), Color = concrete, Material = Enum.Material.Concrete, Parent = model })
	end
	Part({ Name = "Floor", Size = Vector3.new(W, 0.6, W), CFrame = cf * CFrame.new(0, 0.3, 0), Color = Color3.fromRGB(80, 80, 85), Material = Enum.Material.Concrete, Parent = model })
	wall(Vector3.new(W + 2, T, W + 2), Vector3.new(0, H + T / 2, 0)) -- roof
	wall(Vector3.new(W, H, T), Vector3.new(0, H / 2, W / 2)) -- back
	wall(Vector3.new(T, H, W), Vector3.new(-W / 2, H / 2, 0)) -- sides
	wall(Vector3.new(T, H, W), Vector3.new(W / 2, H / 2, 0))
	wall(Vector3.new(14, H, T), Vector3.new(-11, H / 2, -W / 2)) -- front with door gap
	wall(Vector3.new(14, H, T), Vector3.new(11, H / 2, -W / 2))
	wall(Vector3.new(8, 3, T), Vector3.new(0, H - 1.5, -W / 2))
	for i = -3, 3 do
		Part({ Name = "Stripe", Size = Vector3.new(1.4, 0.3, 4), CFrame = cf * CFrame.new(i * 2.4, 0.5, -W / 2 - 3) * CFrame.Angles(0, math.rad(35), 0), Color = i % 2 == 0 and Color3.fromRGB(255, 210, 0) or Color3.fromRGB(30, 30, 30), Parent = model })
	end
	local sign = Part({ Name = "Sign", Size = Vector3.new(20, 4, 0.6), CFrame = cf * CFrame.new(0, H + 4, -W / 2), Color = Color3.fromRGB(255, 210, 0), Material = Enum.Material.Neon, Parent = model })
	BuildKit.SurfaceText(sign, Enum.NormalId.Front, "☢️ PUBLIC BUNKER ☢️", { PixelsPerStud = 16, Color = Color3.new(0, 0, 0) })
	for i = 1, 4 do
		local lampPart = Part({ Name = "Lamp", Size = Vector3.new(3, 0.3, 3), CFrame = cf * CFrame.new(i % 2 == 0 and 8 or -8, H - 0.3, i <= 2 and -6 or 8), Color = Color3.fromRGB(255, 120, 90), Material = Enum.Material.Neon, CanCollide = false, Tags = { "Pulse" }, Parent = model })
		BuildKit.Light(lampPart, Color3.fromRGB(255, 160, 120), 24, 1.5)
	end
	for _, offset in { Vector3.new(-12, 1.8, 10), Vector3.new(12, 1.8, 2), Vector3.new(-12, 1.8, -2) } do
		Part({ Name = "Bench", Size = Vector3.new(8, 1, 2.5), CFrame = cf * CFrame.new(offset) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(110, 80, 50), Material = Enum.Material.WoodPlanks, Parent = model })
	end
	-- supply crates (the stash secret hides behind them)
	for i, offset in { Vector3.new(12, 1.5, 12.5), Vector3.new(9, 1.5, 13), Vector3.new(12, 4.3, 12.5), Vector3.new(14.5, 1.5, 9.5) } do
		local crate = Part({ Name = "Crate", Size = Vector3.new(3, 3, 3), CFrame = cf * CFrame.new(offset) * CFrame.Angles(0, i * 0.3, 0), Color = Color3.fromRGB(150, 110, 60), Material = Enum.Material.WoodPlanks, Parent = model })
		crate.Name = "Crate" .. i
	end
	WorldBuilder.SecretSpots.Bunker = (cf * CFrame.new(15.6, 1.4, 15.6)).Position
	WorldBuilder.Shelter = {
		CFrame = cf * CFrame.new(0, H / 2, 0),
		Size = Vector3.new(W - T, H, W - T),
		Door = (cf * CFrame.new(0, 3, -W / 2 - 4)).Position,
	}
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------
local function buildMountainExtras(world: Folder, rng: Random)
	local model = BuildKit.Model("Mountain", world)
	-- hide the cave entrance behind trees and bushes
	for _, x in { -12, 12, -22, 22 } do
		tree(model, Vector3.new(CAVE.X + x, 0, -476 + math.abs(x) * 0.2), 1.6, rng)
	end
	for _, x in { -6, 6 } do
		Part({ Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Position = Vector3.new(CAVE.X + x, 2, -480), Color = Color3.fromRGB(60, 140, 60), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
	end
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local crystal = Part({
			Name = "CaveCrystal",
			Size = Vector3.new(1.6, rng:NextNumber(3, 7), 1.6),
			CFrame = CFrame.new(CAVE.X + math.cos(a) * 16, 2, CAVE.Z + math.sin(a) * 16) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)),
			Color = Color3.fromHSV(0.7 + rng:NextNumber() * 0.15, 0.7, 1),
			Material = Enum.Material.Neon,
			Parent = model,
		})
		BuildKit.Light(crystal, crystal.Color, 18, 1.5)
	end
	for z = -500, -590, -18 do
		local torch = Part({ Name = "Torch", Size = Vector3.new(0.6, 3, 0.6), Position = Vector3.new(CAVE.X - 5.4, 5, z), Color = Color3.fromRGB(90, 60, 40), Material = Enum.Material.Wood, Parent = model })
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 4
		fire.Parent = torch
		BuildKit.Light(torch, Color3.fromRGB(255, 160, 60), 16, 1.5)
	end
	WorldBuilder.SecretSpots.Cave = Vector3.new(CAVE.X, 2.5, CAVE.Z - 6)
	local pole = Part({ Name = "SummitPole", Size = Vector3.new(0.6, 14, 0.6), Position = Vector3.new(MOUNTAIN.X + 4, 171, MOUNTAIN.Z), Color = Color3.fromRGB(220, 220, 220), Material = Enum.Material.Metal, Parent = model })
	Part({ Name = "SummitFlag", Size = Vector3.new(0.2, 3.5, 6), Position = pole.Position + Vector3.new(0, 5, 3), Color = Color3.fromRGB(255, 60, 60), Material = Enum.Material.Fabric, Parent = model })
	WorldBuilder.SecretSpots.Summit = Vector3.new(MOUNTAIN.X, 167, MOUNTAIN.Z)
end

local function buildWaterfall(world: Folder)
	local model = BuildKit.Model("Waterfall", world)
	local rock = Color3.fromRGB(105, 100, 95)
	local x, z = WATERFALL.X, WATERFALL.Z
	-- cliff with a hidden pocket behind the falls
	Part({ Name = "CliffLeft", Size = Vector3.new(26, 60, 22), Position = Vector3.new(x - 17, 30, z - 14), Color = rock, Material = Enum.Material.Slate, Parent = model })
	Part({ Name = "CliffRight", Size = Vector3.new(26, 60, 22), Position = Vector3.new(x + 17, 30, z - 14), Color = rock, Material = Enum.Material.Slate, Parent = model })
	Part({ Name = "CliffTop", Size = Vector3.new(8, 50, 22), Position = Vector3.new(x, 35, z - 14), Color = rock, Material = Enum.Material.Slate, Parent = model })
	Part({ Name = "CliffBack", Size = Vector3.new(8, 10, 12), Position = Vector3.new(x, 5, z - 19), Color = rock, Material = Enum.Material.Slate, Parent = model })
	local fall = Part({ Name = "Waterfall", Size = Vector3.new(14, 58, 1), Position = Vector3.new(x, 29, z - 2.4), Color = Color3.fromRGB(150, 210, 255), Material = Enum.Material.Glass, Transparency = 0.35, CanCollide = false, Parent = model })
	BuildKit.Particles(fall, {
		Color = ColorSequence.new(Color3.fromRGB(220, 240, 255)),
		Size = BuildKit.Size(2, 1, 3),
		Rate = 40,
		Speed = NumberRange.new(20, 30),
		Lifetime = NumberRange.new(1.5, 2),
		EmissionDirection = Enum.NormalId.Bottom,
		SpreadAngle = Vector2.new(5, 5),
		Transparency = NumberSequence.new(0.4, 1),
	})
	local pool = Part({ Name = "Pool", Size = Vector3.new(34, 0.6, 18), Position = Vector3.new(x, 0.3, z + 8), Color = Color3.fromRGB(60, 160, 230), Material = Enum.Material.Glass, Transparency = 0.3, CanCollide = false, Parent = model })
	BuildKit.Particles(pool, { Color = ColorSequence.new(Color3.new(1, 1, 1)), Size = BuildKit.Size(3, 2, 5), Rate = 15, Speed = NumberRange.new(2, 4), Lifetime = NumberRange.new(2, 3), Transparency = NumberSequence.new(0.6, 1), EmissionDirection = Enum.NormalId.Top })
	WorldBuilder.SecretSpots.Waterfall = Vector3.new(x, 2.5, z - 8)
end

local function buildLake(world: Folder, rng: Random)
	local model = BuildKit.Model("Lake", world)
	for i = 0, 9 do
		Part({ Name = "Plank", Size = Vector3.new(8, 0.5, 2.6), Position = Vector3.new(0, 0.6, LAKE.Z - LAKE_RADIUS - 14 + i * 3), Color = Color3.fromRGB(140, 100, 60), Material = Enum.Material.WoodPlanks, Parent = model })
	end
	for _, dx in { -3.6, 3.6 } do
		for i = 0, 3 do
			Part({ Name = "Post", Size = Vector3.new(0.8, 6, 0.8), Position = Vector3.new(dx, -1, LAKE.Z - LAKE_RADIUS - 13 + i * 9), Color = Color3.fromRGB(110, 80, 50), Material = Enum.Material.Wood, Parent = model })
		end
	end
	-- the island's hollow tree (trunk ring with a gap facing +X)
	local cx, cz = ISLAND.X, ISLAND.Z
	for i = 1, 9 do
		local a = i / 10 * math.pi * 2
		Part({
			Name = "Bark",
			Size = Vector3.new(2.8, 16, 1.4),
			CFrame = CFrame.new(cx + math.cos(a) * 4.2, 10, cz + math.sin(a) * 4.2) * CFrame.Angles(0, -a + math.pi / 2, 0),
			Color = Color3.fromRGB(100, 70, 45),
			Material = Enum.Material.Wood,
			Parent = model,
		})
	end
	for i = 1, 4 do
		Part({ Name = "Canopy", Shape = Enum.PartType.Ball, Size = Vector3.one * (16 - i * 2), Position = Vector3.new(cx + rng:NextNumber(-3, 3), 18 + i * 2.5, cz + rng:NextNumber(-3, 3)), Color = Color3.fromRGB(70, 160, 70), Material = Enum.Material.Grass, CanCollide = false, Parent = model })
	end
	WorldBuilder.SecretSpots.Island = Vector3.new(cx, 3.5, cz)
	WorldBuilder.SecretSpots.LakeFloor = Vector3.new(-70, -18, LAKE.Z - 30)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + 0.6
		tree(model, Vector3.new(cx + math.cos(a) * 16, 2, cz + math.sin(a) * 16), 1, rng)
	end
end

local function buildForest(world: Folder, rng: Random)
	local model = BuildKit.Model("Forest", world)
	-- giant tree house (door faces west, toward the lobby)
	local gx, gz = GIANT_TREE.X, GIANT_TREE.Z
	local segments = 16
	for i = 0, segments - 1 do
		if i ~= 8 then
			local a = i / segments * math.pi * 2
			Part({
				Name = "GiantBark",
				Size = Vector3.new(5.2, 70, 3),
				CFrame = CFrame.new(gx + math.cos(a) * 12, 35, gz + math.sin(a) * 12) * CFrame.Angles(0, -a + math.pi / 2, 0),
				Color = Color3.fromRGB(95, 65, 40),
				Material = Enum.Material.Wood,
				Parent = model,
			})
		end
	end
	Part({ Name = "DoorFrame", Size = Vector3.new(2, 2, 7), Position = Vector3.new(gx - 12, 12, gz), Color = Color3.fromRGB(70, 45, 30), Material = Enum.Material.Wood, Parent = model })
	for _ = 1, 6 do
		Part({
			Name = "GiantCanopy",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * rng:NextNumber(40, 60),
			Position = Vector3.new(gx + rng:NextNumber(-25, 25), 80 + rng:NextNumber(0, 25), gz + rng:NextNumber(-25, 25)),
			Color = Color3.fromRGB(50, 140, 60),
			Material = Enum.Material.Grass,
			CanCollide = false,
			Parent = model,
		})
	end
	local glow = Part({ Name = "Lantern", Size = Vector3.new(1.2, 1.6, 1.2), Position = Vector3.new(gx, 8, gz), Color = Color3.fromRGB(255, 200, 100), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	BuildKit.Light(glow, Color3.fromRGB(255, 200, 120), 20, 1.5)
	WorldBuilder.SecretSpots.GiantTree = Vector3.new(gx + 2, 2.5, gz)

	-- launch pad (hidden among trees) -> cloud island
	local pad = Part({ Name = "LaunchPad", Size = Vector3.new(7, 0.6, 7), Position = LAUNCH_PAD + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(170, 70, 255), Material = Enum.Material.Neon, Tags = { "Pulse" }, Parent = model })
	BuildKit.Particles(pad, { Color = ColorSequence.new(Color3.fromRGB(200, 120, 255)), Size = BuildKit.Size(0.6), Rate = 20, Speed = NumberRange.new(6, 10), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(10, 10) })
	table.insert(WorldBuilder.LaunchPads, { Part = pad, Target = CLOUD + Vector3.new(0, 5, 0) })

	-- cloud island
	local cloud = BuildKit.Model("CloudIsland", world)
	cloud.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	Part({ Name = "CloudTop", Size = Vector3.new(36, 2, 36), Position = CLOUD, Color = Color3.fromRGB(245, 245, 255), Parent = cloud })
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		Part({ Name = "Puff", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(12, 18), Position = CLOUD + Vector3.new(math.cos(a) * 17, rng:NextNumber(-4, 1), math.sin(a) * 17), Color = Color3.fromRGB(250, 250, 255), CanCollide = false, Parent = cloud })
	end
	Part({ Name = "Rainbow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 30, 30), CFrame = CFrame.new(CLOUD + Vector3.new(0, 6, 12)) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(255, 120, 200), Material = Enum.Material.Neon, Transparency = 0.6, CanCollide = false, Tags = { "Pulse" }, Parent = cloud })
	WorldBuilder.SecretSpots.Cloud = CLOUD + Vector3.new(0, 3.5, 0)

	-- dense forest
	local count, tries = 0, 0
	while count < 220 and tries < 3000 do
		tries += 1
		local p = Vector3.new(rng:NextNumber(440, 960), 0, rng:NextNumber(-620, 620))
		if (p - GIANT_TREE).Magnitude > 40 and (p - LAUNCH_PAD).Magnitude > 9 and math.abs(p.Z) > 12 then
			tree(model, p, rng:NextNumber(1.1, 2.2), rng)
			count += 1
		end
	end
end

local function buildGraveyard(world: Folder, rng: Random)
	local model = BuildKit.Model("Graveyard", world)
	local gx, gz = GRAVEYARD.X, GRAVEYARD.Z
	for i = -6, 6 do
		for _, offset in { Vector3.new(i * 5, 0, -32), Vector3.new(i * 5, 0, 32), Vector3.new(-32, 0, i * 5), Vector3.new(32, 0, i * 5) } do
			if not (offset.Z == 32 and math.abs(offset.X) < 6) then
				Part({ Name = "Fence", Size = Vector3.new(0.5, 4, 0.5), Position = Vector3.new(gx, 2, gz) + offset, Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal, Parent = model })
			end
		end
	end
	for row = -2, 2 do
		for col = -3, 3 do
			if not (row == 0 and col == 0) then
				local p = Vector3.new(gx + col * 8 + rng:NextNumber(-1, 1), 0, gz + row * 10 + rng:NextNumber(-1, 1))
				local stone = Part({ Name = "Tombstone", Size = Vector3.new(3, 4, 0.8), CFrame = CFrame.new(p + Vector3.new(0, 2, 0)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.15, 0.15)), Color = Color3.fromRGB(130, 130, 135), Material = Enum.Material.Slate, Parent = model })
				stone.Name = "Tombstone"
				Part({ Name = "Mound", Size = Vector3.new(3, 0.8, 5), Position = p + Vector3.new(0, 0.4, 3), Color = Color3.fromRGB(90, 70, 50), Material = Enum.Material.Ground, Parent = model })
			end
		end
	end
	-- the open grave in the middle
	local stone = Part({ Name = "OddTombstone", Size = Vector3.new(3, 4, 0.8), Position = Vector3.new(gx, 2, gz), Color = Color3.fromRGB(110, 110, 115), Material = Enum.Material.Slate, Parent = model })
	BuildKit.SurfaceText(stone, Enum.NormalId.Back, "R.I.P.\nNOOB", { PixelsPerStud = 20, Color = Color3.fromRGB(60, 60, 60) })
	Part({ Name = "Coffin", Size = Vector3.new(3, 1.2, 6), Position = Vector3.new(gx, 0.6, gz + 3.5), Color = Color3.fromRGB(70, 45, 30), Material = Enum.Material.WoodPlanks, Parent = model })
	Part({ Name = "CoffinLid", Size = Vector3.new(3, 0.3, 6), CFrame = CFrame.new(gx + 2.8, 1.2, gz + 3.5) * CFrame.Angles(0, 0, math.rad(-30)), Color = Color3.fromRGB(70, 45, 30), Material = Enum.Material.WoodPlanks, Parent = model })
	WorldBuilder.SecretSpots.Graveyard = Vector3.new(gx, 2.2, gz + 3.5)
	for _ = 1, 8 do
		tree(model, Vector3.new(gx + rng:NextNumber(-45, 45), 0, gz + rng:NextNumber(-45, 45)), rng:NextNumber(1, 1.6), rng, true)
	end
	for i = 1, 6 do
		local wisp = Part({ Name = "Wisp", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, Position = Vector3.new(gx + rng:NextNumber(-25, 25), 3, gz + rng:NextNumber(-25, 25)), Color = Color3.fromRGB(120, 255, 140), Material = Enum.Material.Neon, CanCollide = false, Tags = { "Bob" }, Parent = model })
		BuildKit.Light(wisp, Color3.fromRGB(120, 255, 140), 14, 1.5)
		wisp.Name = "Wisp" .. i
	end
	local gate = Part({ Name = "GateSign", Size = Vector3.new(12, 2, 0.4), Position = Vector3.new(gx, 6, gz + 32), Color = Color3.fromRGB(30, 30, 35), Parent = model })
	BuildKit.SurfaceText(gate, Enum.NormalId.Back, "🪦 GRAVEYARD", { PixelsPerStud = 20, Color = Color3.fromRGB(150, 255, 150) })
end

local function buildEdge(world: Folder)
	local model = BuildKit.Model("WorldEdge", world)
	for _, data in {
		{ Vector3.new(MAP_HALF * 2, 800, 4), Vector3.new(0, 400, -MAP_HALF) },
		{ Vector3.new(MAP_HALF * 2, 800, 4), Vector3.new(0, 400, MAP_HALF) },
		{ Vector3.new(4, 800, MAP_HALF * 2), Vector3.new(-MAP_HALF, 400, 0) },
		{ Vector3.new(4, 800, MAP_HALF * 2), Vector3.new(MAP_HALF, 400, 0) },
	} do
		Part({ Name = "Boundary", Size = data[1], Position = data[2], Transparency = 1, CanQuery = false, Parent = model })
	end
	for i = 1, 5 do
		Part({ Name = "Boulder", Shape = Enum.PartType.Ball, Size = Vector3.one * (6 + i), Position = EDGE + Vector3.new(-12 + i * 3, 2, -6 - i * 2), Color = Color3.fromRGB(110, 105, 100), Material = Enum.Material.Rock, Parent = model })
	end
	local sign = Part({ Name = "EdgeSign", Size = Vector3.new(0.6, 6, 10), Position = EDGE + Vector3.new(-20, 5, -20), Color = Color3.fromRGB(90, 70, 50), Material = Enum.Material.WoodPlanks, Parent = model })
	BuildKit.SurfaceText(sign, Enum.NormalId.Left, "⚠️ THE END OF THE WORLD ⚠️", { PixelsPerStud = 16 })
	WorldBuilder.SecretSpots.Edge = EDGE + Vector3.new(14, 2, 14)
end

local function scatterTrees(world: Folder, rng: Random)
	local model = BuildKit.Model("Trees", world)
	local placed, tries = 0, 0
	while placed < 160 and tries < 4000 do
		tries += 1
		local p = Vector3.new(rng:NextNumber(-950, 430), 0, rng:NextNumber(-950, 950))
		local ok = p.Magnitude > 360
			and (p - MOUNTAIN).Magnitude > 270
			and (p - LAKE).Magnitude > LAKE_RADIUS + 30
			and not (p.X < -380 and math.abs(p.Z) < 70)
			and (p - GRAVEYARD).Magnitude > 60
			and math.abs(p.X) > 14
			and math.abs(p.Z) > 14
			and (p - WATERFALL).Magnitude > 50
		if ok then
			tree(model, p, rng:NextNumber(0.9, 1.9), rng)
			placed += 1
		end
	end
	for _, deg in { 45, 135, 315 } do
		local a = math.rad(deg)
		tree(model, Vector3.new(math.cos(a) * 150, 0, math.sin(a) * 150), 1.3, rng)
	end
end

---------------------------------------------------------------------------
function WorldBuilder:Init()
	setupLighting()
	setupCollisionGroups()

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	self.Folder = world

	local old = workspace:FindFirstChild("Baseplate")
	if old then
		old:Destroy()
	end

	local rng = Random.new(1337)
	buildTerrain()
	buildLobby(world)
	buildBunker(world)
	buildMountainExtras(world, rng)
	buildWaterfall(world)
	buildLake(world, rng)
	buildForest(world, rng)
	buildGraveyard(world, rng)
	buildEdge(world)
	scatterTrees(world, rng)

	for _, pad in WorldBuilder.LaunchPads do
		local debounce = {}
		pad.Part.Touched:Connect(function(hit)
			local player = BuildKit.PlayerFromHit(hit)
			if player and not debounce[player] and BuildKit.IsNear(player, pad.Part) then
				debounce[player] = true
				Remotes.ClientCommand:FireClient(player, "launch", pad.Target)
				task.delay(4, function()
					debounce[player] = nil
				end)
			end
		end)
	end
end

function WorldBuilder:Start()
	if not Config.DayNight.Enabled then
		return
	end
	-- advance the clock twice a second (no need to replicate every frame)
	local speed = 24 / (Config.DayNight.MinutesPerDay * 60)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.5 then
			Lighting.ClockTime = (Lighting.ClockTime + acc * speed) % 24
			acc = 0
		end
	end)
end

return WorldBuilder
