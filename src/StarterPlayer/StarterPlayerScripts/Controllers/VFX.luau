--[[
	VFX - all client-side visual effects: cash popups, purchase bursts,
	build-in animations, shockwaves, confetti, cash rain, rebirth flash,
	camera shake, speed lines and more. Triggered by Remotes.VFX.
]]
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local VFX = {}
local C
local fxFolder: Folder
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 200, 40),
	Color3.fromRGB(80, 220, 120),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(200, 90, 255),
	Color3.fromRGB(255, 130, 200),
}

local function camera()
	return workspace.CurrentCamera
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

local function sound3D(name: string, position: Vector3, volume: number?, pitch: number?)
	local id = Config.Sounds[name]
	if not id or UIKit.SFXEnabled == false then
		return
	end
	local anchor = localPart({ Size = Vector3.one, Transparency = 1, Position = position })
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.6
	s.PlaybackSpeed = pitch or 1
	s.RollOffMaxDistance = 150
	s.Parent = anchor
	s:Play()
	Debris:AddItem(anchor, 4)
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
function VFX:Shake(intensity: number, duration: number)
	local start = os.clock()
	local name = "VFXShake" .. tostring(start)
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
		local t = os.clock() - start
		if t > duration then
			RunService:UnbindFromRenderStep(name)
			return
		end
		local falloff = 1 - t / duration
		local cam = camera()
		local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * intensity * falloff
		cam.CFrame = cam.CFrame * CFrame.new(offset)
	end)
end

function VFX:Flash(color: Color3?, duration: number?)
	local frame = UIKit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color or Color3.new(1, 1, 1),
		BackgroundTransparency = 0.2,
		ZIndex = 50,
		Parent = C.UI.FX,
	})
	local tween = TweenService:Create(frame, TweenInfo.new(duration or 0.6), { BackgroundTransparency = 1 })
	tween:Play()
	Debris:AddItem(frame, (duration or 0.6) + 0.1)
end

function VFX:Burst(position: Vector3, color: Color3, count: number?, size: number?)
	local anchor = localPart({ Size = Vector3.one, Transparency = 1, Position = position })
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 1.2), NumberSequenceKeypoint.new(1, 0) })
	emitter.Speed = NumberRange.new(10, 24)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Drag = 4
	emitter.Rate = 0
	emitter.Parent = anchor
	emitter:Emit(count or 40)
	Debris:AddItem(anchor, 2)
end

function VFX:Sphere(position: Vector3, color: Color3, size: number)
	local sphere = localPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one,
		Position = position,
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
	})
	TweenService:Create(sphere, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(sphere, 0.6)
end

function VFX:Ring(position: Vector3, color: Color3, size: number, duration: number?)
	local ring = localPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2, 2),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	TweenService:Create(ring, TweenInfo.new(duration or 0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, size, size),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, (duration or 0.7) + 0.1)
end

function VFX:FloatText(position: Vector3, text: string, color: Color3, size: number?)
	local anchor = localPart({ Size = Vector3.one, Transparency = 1, Position = position })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 50)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 150
	gui.LightInfluence = 0
	gui.Parent = anchor
	local label = UIKit.Label({ Text = text, Size = UDim2.fromScale(1, 1), TextColor3 = color, Parent = gui })
	local scale = UIKit.new("UIScale", { Scale = 0.3 * (size or 1), Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = size or 1 }):Play()
	TweenService:Create(anchor, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = position + Vector3.new(0, 6, 0) }):Play()
	task.delay(0.8, function()
		TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end)
	Debris:AddItem(anchor, 1.5)
end

-- Screen confetti falling from the top
function VFX:ScreenConfetti(count: number)
	for _ = 1, count do
		local piece = UIKit.new("Frame", {
			Size = UDim2.fromOffset(math.random(8, 14), math.random(14, 22)),
			Position = UDim2.new(math.random(), 0, 0, -30),
			BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)],
			Rotation = math.random(0, 360),
			BorderSizePixel = 0,
			ZIndex = 40,
			Parent = C.UI.FX,
		})
		local duration = math.random(18, 32) / 10
		TweenService:Create(piece, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(piece.Position.X.Scale + (math.random() - 0.5) * 0.2, 0, 1.1, 0),
			Rotation = piece.Rotation + math.random(-540, 540),
		}):Play()
		Debris:AddItem(piece, duration + 0.1)
	end
end

-- 3D confetti burst at a position
function VFX:WorldConfetti(position: Vector3, count: number)
	for _ = 1, count do
		local piece = localPart({
			Size = Vector3.new(0.4, 0.05, 0.6),
			Position = position,
			Color = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)],
			Material = Enum.Material.Neon,
		})
		piece.Anchored = false
		piece.AssemblyLinearVelocity = Vector3.new(math.random(-25, 25), math.random(25, 50), math.random(-25, 25))
		piece.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))
		Debris:AddItem(piece, 3)
	end
end

-- Cash icons flying from the middle of the screen to the cash counter
function VFX:CashToCounter(amount: number)
	local target = C.HUD and C.HUD.CashFrame
	local targetPos = target and (target.AbsolutePosition + target.AbsoluteSize / 2) or Vector2.new(camera().ViewportSize.X / 2, 40)
	local center = camera().ViewportSize / 2
	for i = 1, 10 do
		local icon = UIKit.new("TextLabel", {
			Text = "💵",
			TextScaled = true,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(36, 36),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(center.X + math.random(-120, 120), center.Y + math.random(-80, 80)),
			ZIndex = 45,
			Parent = C.UI.FX,
		})
		task.delay(0.15 + i * 0.04, function()
			local tween = TweenService:Create(icon, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(targetPos.X, targetPos.Y),
				Size = UDim2.fromOffset(16, 16),
			})
			tween:Play()
			tween.Completed:Wait()
			icon:Destroy()
		end)
	end
	local label = UIKit.Label({
		Text = "+" .. Util.Money(amount),
		Size = UDim2.fromOffset(400, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		TextColor3 = Color3.fromRGB(120, 255, 140),
		ZIndex = 46,
		Parent = C.UI.FX,
	})
	local scale = UIKit.new("UIScale", { Scale = 0.2, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1, function()
		TweenService:Create(label, TweenInfo.new(0.4), { TextTransparency = 1, Position = UDim2.fromScale(0.5, 0.35) }):Play()
		Debris:AddItem(label, 0.5)
	end)
	UIKit.PlaySound("Cash", 0.5, 1.2)
end

---------------------------------------------------------------------------
-- Named effects (from the server)
---------------------------------------------------------------------------
local effects = {}

function effects.CashPop(params)
	local text = "+" .. Util.Money(params.Amount)
	VFX:FloatText(params.Position, text, params.Vault and Color3.fromRGB(255, 220, 80) or Color3.fromRGB(120, 255, 140), 0.9)
end

function effects.CashBurst(params)
	VFX:CashToCounter(params.Amount or 0)
end

function effects.Purchase(params)
	if not params.Position then
		return
	end
	local color = params.Color or Theme.Accent
	VFX:Burst(params.Position, color, params.Big and 80 or 40)
	VFX:Sphere(params.Position, color, params.Big and 24 or 12)
	VFX:Ring(params.Position - Vector3.new(0, 2, 0), color, params.Big and 40 or 20)
	sound3D("Purchase", params.Position, 0.6)
end

function effects.BuildIn(params)
	local model: Instance? = params.Model
	local color = params.Color or Theme.Accent
	if params.Position then
		VFX:Burst(params.Position, color, 50)
		VFX:Sphere(params.Position, color, 16)
		VFX:Ring(params.Position, color, 26)
		sound3D("Purchase", params.Position, 0.7, 1.1)
	end
	if not model then
		return
	end
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and not d:HasTag("Spin") and not d:HasTag("Bob") then
			table.insert(parts, d)
		end
	end
	for i, part in parts do
		local cf = part.CFrame
		local transparency = part.Transparency
		part.CFrame = cf * CFrame.new(0, 6, 0)
		part.Transparency = 1
		task.delay(i * 0.02, function()
			if not part.Parent then
				return
			end
			TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = cf, Transparency = transparency }):Play()
		end)
	end
end

function effects.ButtonPop(params)
	VFX:Ring(params.Position, params.Color or Theme.Green, 14, 0.5)
	VFX:Burst(params.Position, params.Color or Theme.Green, 20, 0.8)
end

function effects.Shockwave(params)
	local pos = params.Position
	if not pos then
		return
	end
	local color = params.Color or Theme.Accent
	VFX:Ring(pos, color, params.Size or 60, 0.9)
	VFX:Sphere(pos, color, (params.Size or 60) * 0.3)
	local cam = camera()
	local distance = (cam.CFrame.Position - pos).Magnitude
	if distance < 120 then
		VFX:Shake(math.clamp((120 - distance) / 120, 0, 1) * 1.2, 0.4)
	end
end

function effects.Confetti(params)
	if params.Position then
		VFX:WorldConfetti(params.Position, params.Small and 25 or 60)
	else
		VFX:ScreenConfetti(70)
	end
	UIKit.PlaySound("Win", 0.35)
end

function effects.Rebirth(params)
	VFX:Flash(Color3.fromRGB(255, 230, 120), 1.2)
	VFX:Shake(1.5, 1)
	VFX:ScreenConfetti(120)
	UIKit.PlaySound("Rebirth", 0.6)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(255, 220, 150)
	cc.Brightness = 0.3
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(2), { TintColor = Color3.new(1, 1, 1), Brightness = 0 }):Play()
	Debris:AddItem(cc, 2.1)
	local label = UIKit.Label({
		Text = "🔄 REBIRTH " .. tostring(params.Rebirths or "") .. "! 🔄",
		Size = UDim2.fromOffset(700, 110),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		TextColor3 = Color3.fromRGB(255, 215, 60),
		ZIndex = 48,
		Parent = C.UI.FX,
	})
	UIKit.Gradient(label, Color3.fromRGB(255, 250, 180), Color3.fromRGB(255, 160, 0), 90)
	local scale = UIKit.new("UIScale", { Scale = 0, Parent = label })
	TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.4, function()
		TweenService:Create(scale, TweenInfo.new(0.3), { Scale = 0 }):Play()
		Debris:AddItem(label, 0.4)
	end)
end

function effects.CashRain(params)
	local duration = params.Duration or 8
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < duration do
			local cam = camera()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local origin = root and root.Position or cam.CFrame.Position
			for _ = 1, 6 do
				local bill = localPart({
					Size = Vector3.new(2, 0.08, 1),
					Position = origin + Vector3.new(math.random(-50, 50), math.random(35, 55), math.random(-50, 50)),
					Color = Color3.fromRGB(80, 190, 90),
					Material = Enum.Material.SmoothPlastic,
				})
				local gui = Instance.new("SurfaceGui")
				gui.Face = Enum.NormalId.Top
				gui.Parent = bill
				UIKit.Label({ Text = "$", Size = UDim2.fromScale(1, 1), TextColor3 = Color3.fromRGB(220, 255, 220), Parent = gui })
				bill.Anchored = false
				bill.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
				bill.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), math.random(-5, 5), math.random(-5, 5))
				Debris:AddItem(bill, 5)
			end
			-- screen emoji
			local icon = UIKit.new("TextLabel", {
				Text = "💵",
				TextScaled = true,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.new(math.random(), 0, 0, -40),
				ZIndex = 40,
				Parent = C.UI.FX,
			})
			TweenService:Create(icon, TweenInfo.new(2.5, Enum.EasingStyle.Linear), { Position = UDim2.new(icon.Position.X.Scale, 0, 1.1, 0), Rotation = math.random(-180, 180) }):Play()
			Debris:AddItem(icon, 2.6)
			task.wait(0.15)
		end
	end)
	VFX:ScreenConfetti(40)
	UIKit.PlaySound("Cash", 0.6)
end

function effects.CoinPop(params)
	VFX:Burst(params.Position, Color3.fromRGB(255, 210, 40), 15, 0.7)
	VFX:FloatText(params.Position, "+1 🪙", Color3.fromRGB(255, 220, 60), 0.7)
	UIKit.PlaySound("Coin", 0.4, 1.3 + math.random() * 0.3)
end

function effects.Error()
	UIKit.PlaySound("Error", 0.3)
end

function effects.PurchaseSound()
	UIKit.PlaySound("Purchase", 0.5)
end

function effects.WinSound()
	UIKit.PlaySound("Win", 0.6)
end

function effects.Flash()
	VFX:Flash(Color3.new(1, 1, 1), 0.5)
end

function effects.ShieldHit(params)
	local center, radius = params.Center, params.Radius or 130
	if typeof(center) ~= "Vector3" then
		return
	end
	local sphere = localPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * radius * 2,
		Position = center,
		Color = Color3.fromRGB(120, 220, 255),
		Material = Enum.Material.ForceField,
		Transparency = 0,
	})
	TweenService:Create(sphere, TweenInfo.new(2.5, Enum.EasingStyle.Quad), { Transparency = 1, Size = Vector3.one * radius * 2.08 }):Play()
	Debris:AddItem(sphere, 2.6)
end

function effects.SecretFound(params)
	local color = params.Color or Color3.fromRGB(255, 220, 80)
	VFX:Flash(color, 0.8)
	VFX:ScreenConfetti(90)
	UIKit.PlaySound("Win", 0.6, 1.1)
	local label = UIKit.Label({
		Text = "🕵️ SECRET FOUND!",
		Size = UDim2.fromOffset(640, 90),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		TextColor3 = color,
		ZIndex = 48,
		Parent = C.UI.FX,
	})
	local sub = UIKit.Label({
		Text = tostring(params.Name) .. "  (" .. tostring(params.Count) .. "/" .. tostring(params.Total) .. ")",
		Size = UDim2.fromOffset(640, 40),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		ZIndex = 48,
		Parent = C.UI.FX,
	})
	for _, l in { label, sub } do
		local scale = UIKit.new("UIScale", { Scale = 0, Parent = l })
		TweenService:Create(scale, TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(3, function()
		for _, l in { label, sub } do
			TweenService:Create(l, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			Debris:AddItem(l, 0.6)
		end
	end)
	if params.Cash then
		VFX:CashToCounter(params.Cash)
	end
end

function effects.SpeedLines(params)
	local cam = camera()
	local baseFov = 70
	TweenService:Create(cam, TweenInfo.new(0.3), { FieldOfView = 88 }):Play()
	local stop = os.clock() + (params.Duration or 5)
	task.spawn(function()
		while os.clock() < stop do
			local line = UIKit.new("Frame", {
				Size = UDim2.fromOffset(3, math.random(60, 160)),
				Position = UDim2.new(math.random(), 0, math.random(), 0),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				ZIndex = 30,
				Parent = C.UI.FX,
			})
			TweenService:Create(line, TweenInfo.new(0.25), { BackgroundTransparency = 1, Position = line.Position + UDim2.fromOffset(0, 120) }):Play()
			Debris:AddItem(line, 0.3)
			task.wait(0.05)
		end
		TweenService:Create(cam, TweenInfo.new(0.5), { FieldOfView = baseFov }):Play()
	end)
	UIKit.PlaySound("Whoosh", 0.5)
end

---------------------------------------------------------------------------
function VFX:Init(controllers)
	C = controllers
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "LocalFX"
	fxFolder.Parent = workspace

	Remotes.VFX.OnClientEvent:Connect(function(name, params)
		local fn = effects[name]
		if fn then
			local ok, err = pcall(fn, params or {})
			if not ok then
				warn("[VFX] " .. tostring(name) .. ": " .. tostring(err))
			end
		end
	end)
end

function VFX:Play(name: string, params)
	local fn = effects[name]
	if fn then
		fn(params or {})
	end
end

return VFX
