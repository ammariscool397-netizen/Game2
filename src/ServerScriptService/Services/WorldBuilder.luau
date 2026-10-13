--[[
	WorldBuilder - builds the lobby, lighting, ground, paths, boards and
	decorations entirely from code so the place works with zero assets.
]]
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BuildKit = require(script.Parent.BuildKit)

local Part = BuildKit.Part

local WorldBuilder = {}
WorldBuilder.Folder = nil :: Folder?
WorldBuilder.LeaderboardGui = nil :: SurfaceGui?

local PLAZA_RADIUS = 50

local function setupLighting()
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") or child:IsA("Sky") then
			child:Destroy()
		end
	end
	Lighting.ClockTime = 14.5
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
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(199, 220, 255)
	atmosphere.Decay = Color3.fromRGB(106, 112, 160)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2
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
end

local function setupCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Drops")
		PhysicsService:RegisterCollisionGroup("Players")
		PhysicsService:CollisionGroupSetCollidable("Drops", "Players", false)
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

local function tree(parent: Instance, position: Vector3, scale: number)
	local model = BuildKit.Model("Tree", parent)
	local trunkHeight = 8 * scale
	Part({
		Name = "Trunk",
		ClassName = "Part",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(trunkHeight, 1.6 * scale, 1.6 * scale),
		CFrame = CFrame.new(position + Vector3.new(0, trunkHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(110, 75, 45),
		Material = Enum.Material.Wood,
		Parent = model,
	})
	local leafColor = Color3.fromHSV(0.28 + math.random() * 0.08, 0.6, 0.55 + math.random() * 0.2)
	for i = 1, 3 do
		local size = (7 - i * 1.3) * scale
		Part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * size,
			Position = position + Vector3.new((math.random() - 0.5) * 2 * scale, trunkHeight + (i - 1) * 2.4 * scale, (math.random() - 0.5) * 2 * scale),
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
	local bulb = Part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.2,
		Position = position + Vector3.new(0, 12.6, 0),
		Color = color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Pulse" },
		Parent = model,
	})
	BuildKit.Light(bulb, color, 24, 1.5)
end

-- Board standing on the ground at `position`, facing `lookAt`
function WorldBuilder.Board(parent: Instance, position: Vector3, lookAt: Vector3, title: string, color: Color3)
	local model = BuildKit.Model(title .. "Board", parent)
	local cf = CFrame.lookAt(position + Vector3.new(0, 13, 0), Vector3.new(lookAt.X, position.Y + 13, lookAt.Z))
	local board = Part({
		Name = "Screen",
		Size = Vector3.new(26, 20, 1),
		CFrame = cf,
		Color = Color3.fromRGB(20, 22, 35),
		Material = Enum.Material.SmoothPlastic,
		Parent = model,
	})
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
	return gui, body, model
end

local function infoText(body: Frame, lines: { string })
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = body
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 52)
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

function WorldBuilder:Init()
	setupLighting()
	setupCollisionGroups()

	local world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	self.Folder = world

	-- remove a default baseplate if one exists
	local old = workspace:FindFirstChild("Baseplate")
	if old then
		old:Destroy()
	end

	Part({
		Name = "Ground",
		Size = Vector3.new(2048, 4, 2048),
		Position = Vector3.new(0, -2, 0),
		Color = Color3.fromRGB(86, 160, 70),
		Material = Enum.Material.Grass,
		Parent = world,
	})

	-- central plaza
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

	-- giant floating title
	local titleAnchor = Part({
		Name = "Title",
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 30, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = lobby,
	})
	local _, titleLabel = BuildKit.Billboard(titleAnchor, Config.GameName, {
		Size = UDim2.fromScale(40, 8),
		Offset = Vector3.zero,
		MaxDistance = 600,
		Color = Color3.fromRGB(255, 210, 40),
	})
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 120)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 170, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 240, 120)),
	})
	gradient.Rotation = 90
	gradient.Parent = titleLabel

	-- center fountain feature with sparkles
	local core = Part({
		Name = "Crystal",
		Size = Vector3.new(4, 4, 4),
		CFrame = CFrame.new(0, 18, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = Color3.fromRGB(255, 196, 0),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin", "Bob" },
		Parent = lobby,
	})
	BuildKit.Light(core, Color3.fromRGB(255, 200, 60), 40, 3)
	BuildKit.Particles(core, {
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 80)),
		Size = BuildKit.Size(1),
		Rate = 25,
		Speed = NumberRange.new(4, 8),
		SpreadAngle = Vector2.new(180, 180),
		Lifetime = NumberRange.new(1, 2),
	})

	-- paths to the plots
	local pathColor = Color3.fromRGB(170, 150, 120)
	for _, sign in { -1, 1 } do
		Part({ Name = "Path", Size = Vector3.new(14, 0.4, 70), Position = Vector3.new(0, 0.2, sign * 75), Color = pathColor, Material = Enum.Material.Cobblestone, Parent = lobby })
		Part({ Name = "Path", Size = Vector3.new(380, 0.4, 14), Position = Vector3.new(0, 0.2, sign * 95), Color = pathColor, Material = Enum.Material.Cobblestone, Parent = lobby })
		for _, x in { -150, 150 } do
			Part({ Name = "Path", Size = Vector3.new(14, 0.4, 16), Position = Vector3.new(x, 0.2, sign * 104), Color = pathColor, Material = Enum.Material.Cobblestone, Parent = lobby })
		end
		for x = -180, 180, 45 do
			if x ~= 0 then
				lamp(lobby, Vector3.new(x, 0, sign * 86), Color3.fromHSV(((x + 180) / 360), 0.7, 1))
			end
		end
	end
	-- path to obby (west) and minigame board area (east)
	Part({ Name = "Path", Size = Vector3.new(160, 0.4, 14), Position = Vector3.new(-125, 0.2, 0), Color = pathColor, Material = Enum.Material.Cobblestone, Parent = lobby })

	-- boards
	local lbGui, lbBody = WorldBuilder.Board(lobby, Vector3.new(-62, 0, -26), Vector3.new(0, 0, 0), "🏆 TOP EARNERS", Color3.fromRGB(255, 180, 0))
	self.LeaderboardGui = lbGui
	self.LeaderboardBody = lbBody

	local _, infoBody = WorldBuilder.Board(lobby, Vector3.new(62, 0, -26), Vector3.new(0, 0, 0), "📜 HOW TO PLAY", Color3.fromRGB(0, 170, 255))
	infoText(infoBody, {
		"💵 Step on buttons in your tycoon to buy",
		"⬇️ Droppers make cash, upgraders multiply",
		"🏦 Step on the vault pad to collect cash",
		"🔄 Rebirth for a permanent multiplier",
		"🎮 Join minigames for big rewards",
		"🏃 Beat the obby (west) for cash",
		"🎁 Daily rewards + codes in the menu",
	})

	local _, mgBody = WorldBuilder.Board(lobby, Vector3.new(62, 0, 26), Vector3.new(0, 0, 0), "🎮 MINIGAMES", Color3.fromRGB(170, 70, 255))
	local mgLines = {}
	for _, mg in Config.Minigames.Games do
		table.insert(mgLines, "• " .. mg.DisplayName .. ": " .. mg.Description)
	end
	table.insert(mgLines, "Every " .. math.floor(Config.Minigames.Intermission / 60 * 10) / 10 .. " min - press JOIN!")
	infoText(mgBody, mgLines)

	local _, credBody = WorldBuilder.Board(lobby, Vector3.new(-62, 0, 26), Vector3.new(0, 0, 0), "⭐ VIP & SHOP", Color3.fromRGB(255, 80, 160))
	infoText(credBody, {
		"👑 VIP: +50% cash, aura & chat tag",
		"💵 2x Cash: double all income",
		"🧲 Auto Collect: skip the vault",
		"⚡ Fast Droppers: 2x drop speed",
		"Open the SHOP button on the left!",
	})

	-- trees around the map (deterministic)
	local rng = Random.new(1337)
	local trees = BuildKit.Model("Trees", world)
	for _ = 1, 140 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(290, 700)
		local pos = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		-- keep the obby lane (west) clear
		if not (pos.X < -200 and math.abs(pos.Z) < 60) then
			tree(trees, pos, rng:NextNumber(0.9, 1.8))
		end
	end
	for _, pos in { Vector3.new(-90, 0, -50), Vector3.new(90, 0, -50), Vector3.new(-90, 0, 50), Vector3.new(90, 0, 50), Vector3.new(-40, 0, -60), Vector3.new(40, 0, 60) } do
		tree(lobby, pos, 1.2)
	end
end

return WorldBuilder
