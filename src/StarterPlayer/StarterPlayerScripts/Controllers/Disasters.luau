--[[
	Disasters (client) - everything you see and hear during disasters:
	  nuke siren, countdown, red vignette, green beam to the nearest bunker,
	  missile, flash, mushroom cloud, shockwave, ash fall-out;
	  meteor warning circles + fireballs; tornado funnels; UFOs with tractor
	  beams. Also the character effects sent by the server:
	  fling / tornado / abduct / launch / vaporized.
]]
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Disasters = {}
local C

local fxFolder: Folder
local banner: Frame
local bannerTitle: TextLabel
local bannerSub: TextLabel
local countdown: TextLabel
local statusChip: TextLabel
local vignette: Frame
local siren: Sound?
local sirenConn: RBXScriptConnection?
local beamParts = {}
local shelters = { Boxes = {}, Spheres = {}, Doors = {} }
local missile: Model?
local nukeActive = false

local function camera()
	return workspace.CurrentCamera
end

local function getRoot(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function localPart(props): BasePart
	local part = Instance.new(props.ClassName or "Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" then
			(part :: any)[k] = v
		end
	end
	part.Parent = fxFolder
	return part
end

local function shake(intensity: number, duration: number)
	if C.VFX and C.VFX.Shake then
		C.VFX:Shake(intensity, duration)
	end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local function buildUI()
	banner = UIKit.new("Frame", {
		Name = "DisasterBanner",
		Size = UDim2.fromOffset(460, 64),
		Position = UDim2.new(0.5, 0, 0, 214),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(60, 15, 15),
		BackgroundTransparency = 0.1,
		Visible = false,
		Parent = C.UI.FX,
	})
	UIKit.Corner(banner, 12)
	UIKit.Stroke(banner, Theme.Red, 3)
	bannerTitle = UIKit.Label({ Text = "", Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 4), TextColor3 = Color3.fromRGB(255, 220, 120), Parent = banner })
	bannerSub = UIKit.Label({ Text = "", Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 39), Font = Theme.BodyFont, Parent = banner })

	countdown = UIKit.Label({
		Text = "",
		Size = UDim2.fromOffset(300, 110),
		Position = UDim2.new(0.5, 0, 0, 282),
		AnchorPoint = Vector2.new(0.5, 0),
		TextColor3 = Color3.fromRGB(255, 60, 40),
		Visible = false,
		Parent = C.UI.FX,
	})
	UIKit.new("UIScale", { Parent = countdown })
	statusChip = UIKit.Label({
		Text = "",
		Size = UDim2.fromOffset(320, 34),
		Position = UDim2.new(0.5, 0, 0, 392),
		AnchorPoint = Vector2.new(0.5, 0),
		Visible = false,
		Parent = C.UI.FX,
	})

	-- red vignette (4 edge gradients)
	vignette = UIKit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 2, Parent = C.UI.FX })
	for i, data in {
		{ UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.25, 0), UDim2.new(0, 0, 0.75, 0), -90 },
		{ UDim2.new(0.2, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.2, 0, 1, 0), UDim2.new(0.8, 0, 0, 0), 180 },
	} do
		local edge = UIKit.new("Frame", { Name = "Edge" .. i, Size = data[1], Position = data[2], BackgroundColor3 = Color3.fromRGB(255, 0, 0), BorderSizePixel = 0, ZIndex = 2, Parent = vignette })
		UIKit.new("UIGradient", { Rotation = data[3], Transparency = NumberSequence.new(0.35, 1), Parent = edge })
	end
end

local function showBanner(title: string, sub: string, color: Color3?)
	banner.Visible = true
	bannerTitle.Text = title
	bannerSub.Text = sub
	local stroke = banner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color or Theme.Red
	end
end

local function hideAll()
	banner.Visible = false
	countdown.Visible = false
	statusChip.Visible = false
	vignette.Visible = false
end

---------------------------------------------------------------------------
-- Shelters
---------------------------------------------------------------------------
local function insideBox(position: Vector3, cf: CFrame, size: Vector3): boolean
	local p = cf:PointToObjectSpace(position)
	return math.abs(p.X) <= size.X / 2 and math.abs(p.Y) <= size.Y / 2 + 2 and math.abs(p.Z) <= size.Z / 2
end

local function isSheltered(position: Vector3): boolean
	for _, box in shelters.Boxes do
		if insideBox(position, box.CFrame, box.Size) then
			return true
		end
	end
	for _, sphere in shelters.Spheres do
		if (position - sphere.Center).Magnitude <= sphere.Radius then
			return true
		end
	end
	return false
end

local function clearBeam()
	for _, inst in beamParts do
		inst:Destroy()
	end
	beamParts = {}
end

local function updateBeam()
	local root = getRoot()
	if not root then
		clearBeam()
		return
	end
	local best, bestD = nil, math.huge
	for _, door in shelters.Doors do
		local d = (door - root.Position).Magnitude
		if d < bestD then
			best, bestD = door, d
		end
	end
	if not best or isSheltered(root.Position) then
		clearBeam()
		return
	end
	if #beamParts == 0 then
		local anchor = localPart({ Size = Vector3.one, Transparency = 1, Position = best })
		local a0 = Instance.new("Attachment")
		a0.Name = "ShelterBeamAttachment"
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(Color3.fromRGB(80, 255, 120))
		beam.LightEmission = 1
		beam.Width0 = 1.4
		beam.Width1 = 1.4
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new(0.2)
		beam.Parent = anchor
		local marker = localPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Position = best + Vector3.new(0, 3, 0), Color = Color3.fromRGB(80, 255, 120), Material = Enum.Material.Neon, Transparency = 0.3 })
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(160, 40)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.Parent = marker
		UIKit.Label({ Text = "🛡️ BUNKER", Size = UDim2.fromScale(1, 1), TextColor3 = Color3.fromRGB(120, 255, 150), Parent = gui })
		beamParts = { anchor, a0, marker }
	else
		(beamParts[1] :: BasePart).Position = best
		;(beamParts[3] :: BasePart).Position = best + Vector3.new(0, 3, 0)
		local a0 = beamParts[2] :: Attachment
		if a0.Parent ~= root then
			a0.Parent = root
		end
	end
end

---------------------------------------------------------------------------
-- Siren
---------------------------------------------------------------------------
local function startSiren()
	if siren then
		return
	end
	local custom = Config.Sounds.Siren
	local sound = Instance.new("Sound")
	sound.SoundId = (custom and custom ~= "") and custom or "rbxasset://sounds/electronicpingshort.wav"
	sound.Looped = true
	sound.Volume = 0.55
	sound.Parent = SoundService
	sound:Play()
	siren = sound
	if not custom or custom == "" then
		-- fake an air-raid wail by sweeping the pitch
		sirenConn = RunService.Heartbeat:Connect(function()
			sound.PlaybackSpeed = 0.55 + (math.sin(os.clock() * 1.6) + 1) * 0.35
		end)
	end
end

local function stopSiren()
	if sirenConn then
		sirenConn:Disconnect()
		sirenConn = nil
	end
	if siren then
		local s = siren
		siren = nil
		TweenService:Create(s, TweenInfo.new(1), { Volume = 0 }):Play()
		Debris:AddItem(s, 1.1)
	end
end

---------------------------------------------------------------------------
-- Nuke visuals
---------------------------------------------------------------------------
local function spawnMissile(target: Vector3, flightTime: number)
	if missile then
		missile:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Missile"
	local start = target + Vector3.new(80, 700, -40)
	local look = CFrame.lookAt(start, target)
	local body = localPart({ Size = Vector3.new(4, 4, 30), CFrame = look, Color = Color3.fromRGB(200, 200, 205), Material = Enum.Material.Metal })
	body.Parent = model
	local nose = localPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4.4, CFrame = look * CFrame.new(0, 0, -15), Color = Color3.fromRGB(220, 30, 30), Material = Enum.Material.SmoothPlastic })
	nose.Parent = model
	for i = 0, 3 do
		local fin = localPart({ Size = Vector3.new(0.4, 6, 5), CFrame = look * CFrame.Angles(0, 0, i * math.pi / 2) * CFrame.new(0, 3.5, 12), Color = Color3.fromRGB(60, 60, 70), Material = Enum.Material.Metal })
		fin.Parent = model
	end
	local tail = localPart({ Size = Vector3.one, CFrame = look * CFrame.new(0, 0, 16), Transparency = 1 })
	tail.Parent = model
	local fire = Instance.new("Fire")
	fire.Size = 18
	fire.Heat = 25
	fire.Color = Color3.fromRGB(255, 140, 30)
	fire.Parent = tail
	local trail = Instance.new("ParticleEmitter")
	trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
	trail.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 16) })
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Lifetime = NumberRange.new(3, 4)
	trail.Rate = 80
	trail.Speed = NumberRange.new(2, 4)
	trail.Parent = tail
	model.PrimaryPart = body
	model.Parent = fxFolder
	missile = model
	local startTime = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local alpha = math.min((os.clock() - startTime) / flightTime, 1)
		if not model.Parent then
			conn:Disconnect()
			return
		end
		local eased = alpha * alpha
		model:PivotTo(CFrame.lookAt(start:Lerp(target, eased), target))
		if alpha >= 1 then
			conn:Disconnect()
		end
	end)
	-- whistle
	UIKit.PlaySound("Whoosh", 0.8, 0.5)
end

local function grow(part: BasePart, size: Vector3, duration: number, props: { [string]: any }?)
	local goal = { Size = size }
	if props then
		for k, v in props do
			goal[k] = v
		end
	end
	TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), goal):Play()
end

local function nukeImpact(target: Vector3, shockSpeed: number)
	if missile then
		missile:Destroy()
		missile = nil
	end
	stopSiren()
	clearBeam()
	countdown.Visible = false
	statusChip.Visible = false
	vignette.Visible = false

	local cam = camera()
	local distance = (cam.CFrame.Position - target).Magnitude
	-- flash
	if C.VFX then
		C.VFX:Flash(Color3.new(1, 1, 1), 3)
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.8
	cc.TintColor = Color3.fromRGB(255, 200, 150)
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(5), { Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
	Debris:AddItem(cc, 5.2)
	task.delay(math.min(distance / shockSpeed, 4), function()
		shake(math.clamp(4 - distance / 300, 0.6, 4), 1.6)
	end)

	local boom = Instance.new("Explosion")
	boom.Position = target + Vector3.new(0, 4, 0)
	boom.BlastRadius = 0
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.Parent = workspace

	-- fireball
	local fireball = localPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 10, Position = target + Vector3.new(0, 10, 0), Color = Color3.fromRGB(255, 170, 60), Material = Enum.Material.Neon })
	grow(fireball, Vector3.one * 170, 2.5, { Position = target + Vector3.new(0, 70, 0) })
	task.delay(2.5, function()
		TweenService:Create(fireball, TweenInfo.new(6), { Transparency = 1, Color = Color3.fromRGB(120, 60, 40) }):Play()
	end)
	Debris:AddItem(fireball, 9)
	-- stem
	local stem = localPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 30, 30), CFrame = CFrame.new(target + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(110, 95, 90), Material = Enum.Material.SmoothPlastic, Transparency = 0.25 })
	TweenService:Create(stem, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(240, 46, 46),
		CFrame = CFrame.new(target + Vector3.new(0, 120, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	}):Play()
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 100, 90))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 20), NumberSequenceKeypoint.new(1, 40) })
	smoke.Transparency = NumberSequence.new(0.4, 1)
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Rate = 40
	smoke.Speed = NumberRange.new(10, 20)
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.Parent = stem
	task.delay(8, function()
		smoke.Enabled = false
		TweenService:Create(stem, TweenInfo.new(8), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(stem, 17)
	-- cap
	local cap = localPart({ Size = Vector3.one, Position = target + Vector3.new(0, 30, 0), Color = Color3.fromRGB(255, 140, 50), Material = Enum.Material.Neon })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(40, 18, 40)
	mesh.Parent = cap
	TweenService:Create(cap, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = target + Vector3.new(0, 250, 0), Color = Color3.fromRGB(140, 110, 100) }):Play()
	TweenService:Create(mesh, TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = Vector3.new(300, 110, 300) }):Play()
	local capSmoke = smoke:Clone()
	capSmoke.Rate = 60
	capSmoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 40), NumberSequenceKeypoint.new(1, 70) })
	capSmoke.SpreadAngle = Vector2.new(180, 30)
	capSmoke.Parent = cap
	task.delay(9, function()
		capSmoke.Enabled = false
		TweenService:Create(cap, TweenInfo.new(8), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(cap, 18)
	-- shockwave rings
	for i, color in { Color3.fromRGB(255, 240, 220), Color3.fromRGB(180, 150, 120) } do
		local ring = localPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(i == 1 and 2 or 6, 10, 10),
			CFrame = CFrame.new(target + Vector3.new(0, 1 + i, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = i == 1 and Enum.Material.Neon or Enum.Material.SmoothPlastic,
			Transparency = i == 1 and 0.2 or 0.4,
		})
		local radius = 1500
		TweenService:Create(ring, TweenInfo.new(radius / shockSpeed * (i == 1 and 1 or 1.15), Enum.EasingStyle.Linear), {
			Size = Vector3.new(ring.Size.X, radius * 2, radius * 2),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, radius / shockSpeed * 1.2 + 0.2)
	end
	UIKit.PlaySound("Boom", 1, 0.4)
end

local function aftermath(duration: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(255, 205, 170)
	cc.Saturation = -0.2
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(duration), { TintColor = Color3.new(1, 1, 1), Saturation = 0 }):Play()
	Debris:AddItem(cc, duration + 0.2)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local density, color = atmosphere.Density, atmosphere.Color
		atmosphere.Density = math.min(density + 0.25, 0.8)
		atmosphere.Color = Color3.fromRGB(200, 150, 120)
		TweenService:Create(atmosphere, TweenInfo.new(duration), { Density = density, Color = color }):Play()
	end
	-- ash falling around the camera
	local ashHolder = localPart({ Size = Vector3.new(120, 1, 120), Transparency = 1 })
	local ash = Instance.new("ParticleEmitter")
	ash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	ash.Color = ColorSequence.new(Color3.fromRGB(110, 105, 100))
	ash.Size = NumberSequence.new(0.25)
	ash.Lifetime = NumberRange.new(5, 7)
	ash.Rate = 90
	ash.Speed = NumberRange.new(3, 6)
	ash.EmissionDirection = Enum.NormalId.Bottom
	ash.RotSpeed = NumberRange.new(-60, 60)
	ash.Parent = ashHolder
	local startTime = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		ashHolder.Position = camera().CFrame.Position + Vector3.new(0, 40, 0)
		if os.clock() - startTime > duration then
			conn:Disconnect()
			ash.Enabled = false
			Debris:AddItem(ashHolder, 7)
		end
	end)
end

---------------------------------------------------------------------------
-- Meteors
---------------------------------------------------------------------------
local function meteor(target: Vector3, delay: number, radius: number, shielded: boolean)
	if (camera().CFrame.Position - target).Magnitude > 700 then
		return
	end
	local warning = localPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		CFrame = CFrame.new(target + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = shielded and Color3.fromRGB(80, 200, 255) or Color3.fromRGB(255, 40, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	})
	TweenService:Create(warning, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.15 }):Play()
	local start = target + Vector3.new(math.random(-60, 60), 260, math.random(-60, 60))
	local rock = localPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Position = start, Color = Color3.fromRGB(120, 50, 20), Material = Enum.Material.CrackedLava })
	local fire = Instance.new("Fire")
	fire.Size = 12
	fire.Heat = 20
	fire.Parent = rock
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 0)
	light.Range = 30
	light.Brightness = 3
	light.Parent = rock
	local tween = TweenService:Create(rock, TweenInfo.new(delay, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = target })
	tween:Play()
	tween.Completed:Connect(function()
		rock:Destroy()
		warning:Destroy()
		local boom = Instance.new("Explosion")
		boom.Position = target
		boom.BlastRadius = 0
		boom.BlastPressure = 0
		boom.DestroyJointRadiusPercent = 0
		boom.Parent = workspace
		if C.VFX then
			C.VFX:Ring(target + Vector3.new(0, 1, 0), shielded and Color3.fromRGB(80, 200, 255) or Color3.fromRGB(255, 120, 0), radius * 3, 0.6)
			C.VFX:Burst(target, Color3.fromRGB(255, 140, 40), 30, 1.5)
		end
		local d = (camera().CFrame.Position - target).Magnitude
		if d < 80 then
			shake((80 - d) / 80 * 1.2, 0.35)
		end
	end)
end

---------------------------------------------------------------------------
-- Tornado + UFO visuals (follow server cores)
---------------------------------------------------------------------------
local function tornadoVisual(core: BasePart)
	local model = Instance.new("Model")
	model.Name = "TornadoVisual"
	model.Parent = fxFolder
	local segments = {}
	for i = 0, 11 do
		local r = 5 + i * 2.6
		local seg = localPart({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(14, r * 2, r * 2),
			Color = Color3.fromRGB(140 - i * 3, 140 - i * 3, 150 - i * 3),
			Material = Enum.Material.SmoothPlastic,
			Transparency = 0.55 + i * 0.02,
		})
		seg.Parent = model
		segments[i + 1] = { Part = seg, Height = 7 + i * 13, Phase = i * 0.5 }
	end
	local dust = localPart({ Size = Vector3.new(30, 1, 30), Transparency = 1 })
	dust.Parent = model
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(150, 130, 110))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 20) })
	emitter.Transparency = NumberSequence.new(0.3, 1)
	emitter.Lifetime = NumberRange.new(2, 3)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(10, 20)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Parent = dust
	local debris = emitter:Clone()
	debris.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	debris.Color = ColorSequence.new(Color3.fromRGB(90, 60, 40))
	debris.Size = NumberSequence.new(1)
	debris.Rate = 30
	debris.Speed = NumberRange.new(30, 50)
	debris.RotSpeed = NumberRange.new(-200, 200)
	debris.Parent = dust
	local pos = core.Position
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not core.Parent then
			conn:Disconnect()
			for _, s in segments do
				TweenService:Create(s.Part, TweenInfo.new(1.5), { Transparency = 1 }):Play()
			end
			emitter.Enabled = false
			debris.Enabled = false
			Debris:AddItem(model, 3)
			return
		end
		pos = pos:Lerp(core.Position, math.min(dt * 6, 1))
		local t = os.clock()
		for _, s in segments do
			local sway = Vector3.new(math.sin(t * 2 + s.Phase) * s.Height * 0.06, 0, math.cos(t * 1.7 + s.Phase) * s.Height * 0.06)
			s.Part.CFrame = CFrame.new(pos + Vector3.new(0, s.Height, 0) + sway) * CFrame.Angles(0, t * 4 + s.Phase, math.rad(90))
		end
		dust.Position = pos + Vector3.new(0, 1, 0)
	end)
end

local function ufoVisual(core: BasePart)
	local model = Instance.new("Model")
	model.Name = "UFOVisual"
	model.Parent = fxFolder
	local disc = localPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 30, 30), Color = Color3.fromRGB(170, 175, 190), Material = Enum.Material.Metal })
	disc.Parent = model
	local dome = localPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 13, Color = Color3.fromRGB(120, 255, 200), Material = Enum.Material.Glass, Transparency = 0.3 })
	dome.Parent = model
	local lights = {}
	for i = 1, 10 do
		local l = localPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, Color = Color3.fromHSV(i / 10, 0.8, 1), Material = Enum.Material.Neon })
		l.Parent = model
		lights[i] = l
	end
	local beam = localPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(120, 14, 14), Color = Color3.fromRGB(120, 255, 120), Material = Enum.Material.Neon, Transparency = 1 })
	beam.Parent = model
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(120, 255, 150)
	glow.Range = 50
	glow.Brightness = 2
	glow.Parent = disc
	local pos = core.Position
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not core.Parent then
			conn:Disconnect()
			TweenService:Create(disc, TweenInfo.new(1), { Transparency = 1 }):Play()
			Debris:AddItem(model, 1.2)
			return
		end
		pos = pos:Lerp(core.Position, math.min(dt * 5, 1))
		local t = os.clock()
		local center = pos + Vector3.new(0, math.sin(t * 2) * 1.5, 0)
		local tilt = CFrame.Angles(math.sin(t) * 0.08, 0, math.cos(t * 1.3) * 0.08)
		disc.CFrame = CFrame.new(center) * tilt * CFrame.Angles(0, 0, math.rad(90))
		dome.CFrame = CFrame.new(center + Vector3.new(0, 3, 0))
		for i, l in lights do
			local a = i / #lights * math.pi * 2 + t * 2
			l.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 14.5, -0.5, math.sin(a) * 14.5))
			l.Color = Color3.fromHSV((i / #lights + t * 0.3) % 1, 0.8, 1)
		end
		local beamOn = core:GetAttribute("BeamOn") == true
		beam.Transparency = beamOn and (0.55 + math.sin(t * 12) * 0.08) or 1
		beam.CFrame = CFrame.new(center - Vector3.new(0, 62, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end)
end

---------------------------------------------------------------------------
-- Character effects (from the server)
---------------------------------------------------------------------------
local busy = false

local function fling(velocity: Vector3)
	local root, humanoid = getRoot(), getHumanoid()
	if not root or not humanoid or busy then
		return
	end
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = velocity
	root.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-6, 6), math.random(-6, 6))
	task.delay(1.2, function()
		if humanoid.Parent and not busy then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function tornadoPull(center: Vector3)
	local root = getRoot()
	if not root then
		return
	end
	local flat = (root.Position - center) * Vector3.new(1, 0, 1)
	local radial = flat.Magnitude > 0.5 and flat.Unit or Vector3.new(1, 0, 0)
	local tangent = Vector3.new(-radial.Z, 0, radial.X)
	fling(tangent * 70 - radial * 18 + Vector3.new(0, 55, 0))
end

-- move the character along a path while anchored (abduction / launch pad)
local function carry(duration: number, pathFn: (number) -> Vector3, onDone: (() -> ())?)
	local root, humanoid = getRoot(), getHumanoid()
	if not root or not humanoid or busy then
		return
	end
	busy = true
	root.Anchored = true
	local startTime = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local alpha = math.min((os.clock() - startTime) / duration, 1)
		if not root.Parent then
			conn:Disconnect()
			busy = false
			return
		end
		local p = pathFn(alpha)
		local ahead = pathFn(math.min(alpha + 0.02, 1))
		local dir = (ahead - p) * Vector3.new(1, 0, 1)
		root.CFrame = dir.Magnitude > 0.01 and CFrame.lookAt(p, p + dir) or CFrame.new(p) * root.CFrame.Rotation
		if alpha >= 1 then
			conn:Disconnect()
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			busy = false
			if onDone then
				onDone()
			end
		end
	end)
end

local function abduct(target: Vector3, duration: number)
	local root = getRoot()
	if not root then
		return
	end
	local start = root.Position
	UIKit.PlaySound("Whoosh", 0.7, 0.6)
	carry(duration, function(alpha)
		local p = start:Lerp(target, alpha * alpha)
		return p + Vector3.new(math.sin(alpha * 20) * 1.5, 0, math.cos(alpha * 20) * 1.5)
	end, function()
		C.Notifications:Toast("🛸 You were abducted by aliens! Grab the alien cash they drop!", "info", 4)
	end)
end

local function launch(target: Vector3)
	local root = getRoot()
	if not root then
		return
	end
	local start = root.Position
	local apex = math.max(start.Y, target.Y) + 60
	UIKit.PlaySound("Whoosh", 0.8, 0.8)
	if C.VFX then
		C.VFX:Play("SpeedLines", { Duration = 3 })
	end
	carry(3, function(alpha)
		local flat = Vector3.new(start.X, 0, start.Z):Lerp(Vector3.new(target.X, 0, target.Z), alpha)
		-- quadratic bezier for height
		local y = (1 - alpha) ^ 2 * start.Y + 2 * (1 - alpha) * alpha * apex + alpha ^ 2 * target.Y
		return Vector3.new(flat.X, y, flat.Z)
	end)
end

local function vaporized()
	if C.VFX then
		C.VFX:Flash(Color3.fromRGB(255, 200, 150), 2)
	end
	local label = UIKit.Label({
		Text = "☠️ VAPORIZED! ☠️",
		Size = UDim2.fromOffset(600, 90),
		Position = UDim2.fromScale(0.5, 0.38),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = Color3.fromRGB(255, 90, 40),
		ZIndex = 49,
		Parent = C.UI.FX,
	})
	local sub = UIKit.Label({
		Text = "Next time follow the green beam to a bunker!",
		Size = UDim2.fromOffset(600, 34),
		Position = UDim2.fromScale(0.5, 0.46),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Font = Theme.BodyFont,
		ZIndex = 49,
		Parent = C.UI.FX,
	})
	task.delay(4, function()
		TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		TweenService:Create(sub, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		Debris:AddItem(label, 0.7)
		Debris:AddItem(sub, 0.7)
	end)
end

---------------------------------------------------------------------------
-- State handling
---------------------------------------------------------------------------
local ACTIVE_TEXT = {
	Meteors = { "☄️ METEOR STORM", "Dodge the red circles • grab cash crystals", Color3.fromRGB(255, 120, 30) },
	Tornado = { "🌪️ TORNADO", "Stay away from the funnel!", Color3.fromRGB(170, 180, 200) },
	UFO = { "🛸 UFO INVASION", "Avoid the tractor beams • grab alien cash", Color3.fromRGB(120, 255, 80) },
}

local function onState(state)
	local phase, kind = state.Phase, state.Kind
	if phase == "Warning" and kind == "Nuke" then
		nukeActive = true
		shelters = state.Shelters or shelters
		showBanner("☢️ NUKE INCOMING ☢️", state.By and ("Launched by " .. state.By) or "Find a bunker NOW!", Theme.Red)
		countdown.Visible = true
		countdown.Text = tostring(state.TimeLeft)
		local scale = countdown:FindFirstChildOfClass("UIScale") :: UIScale
		scale.Scale = 1.4
		TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		vignette.Visible = true
		statusChip.Visible = true
		startSiren()
		updateBeam()
		if state.TimeLeft <= 3 and not missile then
			spawnMissile(state.Target, state.TimeLeft)
		end
		UIKit.PlaySound("Countdown", 0.4, state.TimeLeft <= 5 and 1.4 or 1)
	elseif phase == "Impact" and kind == "Nuke" then
		nukeImpact(state.Target, state.ShockSpeed or 320)
		showBanner("☢️ IMPACT ☢️", "Stay in cover until the shockwave passes!", Theme.Red)
	elseif phase == "Aftermath" then
		aftermath(state.Duration or 25)
		task.delay(3, hideAll)
		nukeActive = false
	elseif phase == "Active" then
		local text = ACTIVE_TEXT[kind]
		if text then
			showBanner(text[1] .. "  " .. tostring(state.TimeLeft) .. "s", text[2], text[3])
		end
	elseif phase == "Meteor" then
		meteor(state.Target, state.Delay or 1.4, state.Radius or 12, state.Shield == true)
	elseif phase == "End" then
		stopSiren()
		clearBeam()
		nukeActive = false
		if missile then
			missile:Destroy()
			missile = nil
		end
		task.delay(1.5, hideAll)
	end
end

function Disasters:Init(controllers)
	C = controllers
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "DisasterFX"
	fxFolder.Parent = workspace
	buildUI()

	Remotes.Disaster.OnClientEvent:Connect(function(state)
		local ok, err = pcall(onState, state)
		if not ok then
			warn("[Disasters] " .. tostring(err))
		end
	end)

	Remotes.ClientCommand.OnClientEvent:Connect(function(command, a, b)
		if command == "fling" and typeof(a) == "Vector3" then
			fling(a)
		elseif command == "tornado" and typeof(a) == "Vector3" then
			tornadoPull(a)
		elseif command == "abduct" and typeof(a) == "Vector3" then
			abduct(a, tonumber(b) or 2.5)
		elseif command == "launch" and typeof(a) == "Vector3" then
			launch(a)
		elseif command == "vaporized" then
			vaporized()
		end
	end)

	for _, core in CollectionService:GetTagged("Tornado") do
		tornadoVisual(core)
	end
	CollectionService:GetInstanceAddedSignal("Tornado"):Connect(tornadoVisual)
	for _, core in CollectionService:GetTagged("UFO") do
		ufoVisual(core)
	end
	CollectionService:GetInstanceAddedSignal("UFO"):Connect(ufoVisual)

	player.CharacterAdded:Connect(function()
		busy = false
		clearBeam()
	end)
end

local function updateStatus()
	if nukeActive and statusChip.Visible then
		local root = getRoot()
		if root then
			local safe = isSheltered(root.Position)
			statusChip.Text = safe and "✅ YOU ARE SAFE" or "⚠️ EXPOSED - GET TO A BUNKER!"
			statusChip.TextColor3 = safe and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 110, 80)
			updateBeam()
		end
	end
end

function Disasters:Start()
	-- live shelter status + beam while a nuke is coming
	while true do
		task.wait(0.25)
		Util.Try("Disasters", updateStatus)
	end
end

return Disasters
