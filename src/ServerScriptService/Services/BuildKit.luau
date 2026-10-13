--[[ BuildKit - helpers to build geometry from code (no assets needed) ]]
local CollectionService = game:GetService("CollectionService")

local BuildKit = {}

-- BuildKit.Part({ Size=, CFrame=, Color=, Material=, Parent=, ... })
function BuildKit.Part(props: { [string]: any }): BasePart
	local className = props.ClassName or "Part"
	local part = Instance.new(className) :: any
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		if key ~= "Parent" and key ~= "ClassName" and key ~= "Tags" then
			part[key] = value
		end
	end
	if props.Tags then
		for _, tag in props.Tags do
			CollectionService:AddTag(part, tag)
		end
	end
	part.Parent = props.Parent
	return part
end

function BuildKit.Model(name: string, parent: Instance?): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- Floating text above a part
function BuildKit.Billboard(adornee: BasePart, text: string, props: { [string]: any }?)
	props = props or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = props.Name or "Billboard"
	gui.Size = props.Size or UDim2.fromOffset(200, 50)
	gui.StudsOffset = props.Offset or Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = props.AlwaysOnTop or false
	gui.MaxDistance = props.MaxDistance or 120
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = props.Font or Enum.Font.FredokaOne
	label.TextColor3 = props.Color or Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
	return gui, label
end

-- Text painted on the face of a part
function BuildKit.SurfaceText(part: BasePart, face: Enum.NormalId, text: string, props: { [string]: any }?)
	props = props or {}
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = props.PixelsPerStud or 30
	gui.LightInfluence = 0
	gui.Brightness = props.Brightness or 1.5
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = props.Font or Enum.Font.FredokaOne
	label.TextColor3 = props.Color or Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = part
	return gui, label
end

function BuildKit.Particles(parent: Instance, props: { [string]: any }): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.LightEmission = 1
	emitter.Rate = 10
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(30, 30)
	for key, value in props do
		(emitter :: any)[key] = value
	end
	emitter.Parent = parent
	return emitter
end

function BuildKit.Light(parent: Instance, color: Color3, range: number?, brightness: number?)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range or 12
	light.Brightness = brightness or 2
	light.Shadows = false
	light.Parent = parent
	return light
end

function BuildKit.Size(n: number, from: number?, to: number?)
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, from or n), NumberSequenceKeypoint.new(1, to or 0) })
end

-- Is `hit` part of a character? Returns (player, humanoid)
function BuildKit.PlayerFromHit(hit: BasePart): (Player?, Humanoid?)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil, nil
	end
	return game:GetService("Players"):GetPlayerFromCharacter(model), humanoid
end

return BuildKit
