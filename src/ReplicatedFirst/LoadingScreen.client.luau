--[[
	Loading screen - animated background, spinning logo, progress bar with
	asset preloading, rotating tips, loading music and a skip button.
]]
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

ReplicatedFirst:RemoveDefaultLoadingScreen()

-- defaults until the shared config replicates
local GAME_NAME = "MEGA TYCOON"
local TIPS = { "Loading the money printers..." }

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function stroke(parent: Instance, thickness: number?)
	return new("UIStroke", { Thickness = thickness or 3, Color = Color3.new(0, 0, 0), Parent = parent })
end

local gui = new("ScreenGui", {
	Name = "LoadingScreen",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	DisplayOrder = 1000,
	Parent = playerGui,
})

local background = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	Parent = gui,
})
local bgGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 20, 70)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 30, 140)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 90, 120)),
	}),
	Rotation = 45,
	Parent = background,
})

-- floating money in the background
local floaters = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = background })
local EMOJIS = { "💵", "💰", "🪙", "💎", "⭐" }

local title = new("TextLabel", {
	Text = GAME_NAME,
	Size = UDim2.new(0.8, 0, 0.16, 0),
	Position = UDim2.fromScale(0.5, 0.3),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = Color3.new(1, 1, 1),
	Parent = background,
})
stroke(title, 5)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 140)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 120, 0)),
	}),
	Rotation = 90,
	Parent = title,
})
local titleScale = new("UIScale", { Scale = 0, Parent = title })
new("UISizeConstraint", { MaxSize = Vector2.new(900, 160), Parent = title })

local subtitle = new("TextLabel", {
	Text = "Build your empire. Rule the server.",
	Size = UDim2.new(0.6, 0, 0, 30),
	Position = UDim2.fromScale(0.5, 0.41),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(220, 220, 255),
	TextTransparency = 1,
	Parent = background,
})

-- spinner (two rotating rounded squares)
local spinnerHolder = new("Frame", {
	Size = UDim2.fromOffset(70, 70),
	Position = UDim2.fromScale(0.5, 0.58),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	Parent = background,
})
local spinA = new("Frame", { Size = UDim2.fromScale(1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(255, 196, 0), Parent = spinnerHolder })
new("UICorner", { CornerRadius = UDim.new(0, 14), Parent = spinA })
stroke(spinA, 3)
local spinB = new("Frame", { Size = UDim2.fromScale(0.55, 0.55), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(0, 200, 255), Parent = spinnerHolder })
new("UICorner", { CornerRadius = UDim.new(0, 8), Parent = spinB })
stroke(spinB, 3)
local coin = new("TextLabel", { Text = "$", Size = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, TextScaled = true, Font = Enum.Font.FredokaOne, TextColor3 = Color3.new(1, 1, 1), Parent = spinB })
stroke(coin, 2)

-- progress bar
local barBack = new("Frame", {
	Size = UDim2.new(0.5, 0, 0, 26),
	Position = UDim2.fromScale(0.5, 0.72),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = Color3.fromRGB(20, 15, 40),
	Parent = background,
})
new("UICorner", { CornerRadius = UDim.new(0, 13), Parent = barBack })
stroke(barBack, 3)
new("UISizeConstraint", { MinSize = Vector2.new(260, 26), MaxSize = Vector2.new(600, 26), Parent = barBack })
local barFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = barBack })
new("UICorner", { CornerRadius = UDim.new(0, 13), Parent = barFill })
local fillGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 255, 140)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 230, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 255, 140)),
	}),
	Parent = barFill,
})
local percent = new("TextLabel", {
	Text = "0%",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = Color3.new(1, 1, 1),
	ZIndex = 3,
	Parent = barBack,
})
stroke(percent, 2)

local status = new("TextLabel", {
	Text = "Connecting...",
	Size = UDim2.new(0.6, 0, 0, 22),
	Position = UDim2.fromScale(0.5, 0.77),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(200, 200, 230),
	Parent = background,
})

local tip = new("TextLabel", {
	Text = "",
	Size = UDim2.new(0.8, 0, 0, 26),
	Position = UDim2.fromScale(0.5, 0.9),
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundTransparency = 1,
	TextScaled = true,
	Font = Enum.Font.GothamBold,
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Parent = background,
})
stroke(tip, 2)

local skip = new("TextButton", {
	Text = "SKIP ▶",
	Size = UDim2.fromOffset(130, 44),
	Position = UDim2.new(1, -20, 1, -20),
	AnchorPoint = Vector2.new(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 196, 0),
	TextScaled = true,
	Font = Enum.Font.FredokaOne,
	TextColor3 = Color3.new(1, 1, 1),
	Visible = false,
	Parent = background,
})
new("UICorner", { CornerRadius = UDim.new(0, 10), Parent = skip })
stroke(skip, 3)
new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), Parent = skip })

local blur = new("BlurEffect", { Name = "LoadingBlur", Size = 24, Parent = Lighting })

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

---------------------------------------------------------------------------
-- Animation loop
---------------------------------------------------------------------------
local finished = false
local skipped = false
local displayed = 0
local target = 0

TweenService:Create(titleScale, TweenInfo.new(0.9, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
task.delay(0.5, function()
	TweenService:Create(subtitle, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
end)

local renderConn = RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	bgGradient.Rotation = (bgGradient.Rotation + dt * 12) % 360
	spinA.Rotation = (t * 180) % 360
	spinB.Rotation = -(t * 260) % 360
	titleScale.Scale = finished and titleScale.Scale or (titleScale.Scale > 0.95 and (1 + math.sin(t * 2.5) * 0.03) or titleScale.Scale)
	fillGradient.Offset = Vector2.new(math.sin(t * 2) * 0.5, 0)
	displayed += (target - displayed) * math.min(dt * 6, 1)
	barFill.Size = UDim2.fromScale(math.clamp(displayed, 0, 1), 1)
	percent.Text = math.floor(displayed * 100 + 0.5) .. "%"
end)

task.spawn(function()
	while not finished do
		local label = new("TextLabel", {
			Text = EMOJIS[math.random(1, #EMOJIS)],
			Size = UDim2.fromOffset(math.random(26, 54), math.random(26, 54)),
			Position = UDim2.new(math.random(), 0, 1.1, 0),
			BackgroundTransparency = 1,
			TextScaled = true,
			TextTransparency = 0.35,
			Rotation = math.random(-30, 30),
			Parent = floaters,
		})
		local duration = math.random(40, 80) / 10
		TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
			Position = UDim2.new(label.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, -0.15, 0),
			Rotation = math.random(-180, 180),
		}):Play()
		task.delay(duration, function()
			label:Destroy()
		end)
		task.wait(0.25)
	end
end)

-- loading music + config
local music: Sound? = nil
task.spawn(function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 20)
	local configModule = shared and shared:WaitForChild("Config", 10)
	if not configModule then
		return
	end
	local Config = require(configModule) :: any
	GAME_NAME = Config.GameName
	title.Text = GAME_NAME
	TIPS = Config.Tips
	if Config.Music.Loading and not finished then
		local sound = Instance.new("Sound")
		sound.SoundId = Config.Music.Loading.Id
		sound.Volume = 0
		sound.Looped = true
		sound.Parent = SoundService
		sound:Play()
		TweenService:Create(sound, TweenInfo.new(2), { Volume = 0.3 }):Play()
		music = sound
	end
end)

task.spawn(function()
	local i = 0
	while not finished do
		i = i % #TIPS + 1
		tip.Text = "💡 TIP: " .. TIPS[i]
		tip.TextTransparency = 1
		TweenService:Create(tip, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
		task.wait(4)
	end
end)

task.delay(6, function()
	if not finished then
		skip.Visible = true
	end
end)
skip.Activated:Connect(function()
	skipped = true
end)

---------------------------------------------------------------------------
-- Actual loading
---------------------------------------------------------------------------
local startTime = os.clock()

status.Text = "Loading game..."
if not game:IsLoaded() then
	game.Loaded:Wait()
end
target = 0.2

-- wait for the server to finish building the world
status.Text = "Building the world..."
local waited = 0
while not workspace:GetAttribute("ServerReady") and waited < 20 and not skipped do
	waited += task.wait(0.2)
end
target = 0.35

-- preload assets (in chunks so the bar moves)
status.Text = "Loading assets..."
local assets = {}
for _, d in workspace:GetDescendants() do
	if d:IsA("ParticleEmitter") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("MeshPart") or d:IsA("Sound") then
		table.insert(assets, d)
	end
end
local total = math.max(#assets, 1)
local chunk = 25
for i = 1, #assets, chunk do
	if skipped then
		break
	end
	local slice = {}
	for j = i, math.min(i + chunk - 1, #assets) do
		table.insert(slice, assets[j])
	end
	pcall(function()
		ContentProvider:PreloadAsync(slice)
	end)
	target = 0.35 + 0.45 * (math.min(i + chunk, total) / total)
	status.Text = string.format("Loading assets... %d / %d", math.min(i + chunk - 1, #assets), #assets)
end
target = 0.8

-- wait for player data
status.Text = "Loading your tycoon..."
waited = 0
while not player:GetAttribute("DataLoaded") and waited < 25 and not skipped do
	waited += task.wait(0.2)
end
target = 1
status.Text = "Ready!"

-- minimum time so the screen doesn't just flash
while os.clock() - startTime < 3.5 and not skipped do
	task.wait(0.1)
end
task.wait(0.4)

---------------------------------------------------------------------------
-- Fade out
---------------------------------------------------------------------------
finished = true
skip.Visible = false
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
end)
local fadeInfo = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
TweenService:Create(titleScale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
TweenService:Create(background, fadeInfo, { BackgroundTransparency = 1 }):Play()
TweenService:Create(blur, TweenInfo.new(1.2), { Size = 0 }):Play()
for _, d in background:GetDescendants() do
	if d:IsA("TextLabel") or d:IsA("TextButton") then
		TweenService:Create(d, fadeInfo, { TextTransparency = 1 }):Play()
	end
	if d:IsA("Frame") then
		TweenService:Create(d, fadeInfo, { BackgroundTransparency = 1 }):Play()
	end
	if d:IsA("UIStroke") then
		TweenService:Create(d, fadeInfo, { Transparency = 1 }):Play()
	end
end
if music then
	TweenService:Create(music, TweenInfo.new(1), { Volume = 0 }):Play()
end
player:SetAttribute("LoadingDone", true)
task.wait(1.3)
renderConn:Disconnect()
blur:Destroy()
gui:Destroy()
if music then
	music:Destroy()
end
