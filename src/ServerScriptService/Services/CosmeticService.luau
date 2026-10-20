--[[
	CosmeticService - trails, auras and hats (Config.Cosmetics). Owned and
	equipped cosmetics are saved. One of each kind can be worn at a time. They
	are built on the character on the server, so everybody sees them.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local CC = Config.Cosmetics

local CosmeticService = {}
local S

local lastAction: { [Player]: number } = {}

local function count(map: any): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

---------------------------------------------------------------------------
-- Building the visuals
---------------------------------------------------------------------------
local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Shape = shape or Enum.PartType.Block
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	return p
end

-- parts of a hat, as { Part, offset from the top of the head }
local function hatParts(shape: string, color: Color3): { { Part: Part, Offset: CFrame } }
	local list = {}
	local function add(p: Part, offset: CFrame)
		table.insert(list, { Part = p, Offset = offset })
	end
	local upright = CFrame.Angles(0, 0, math.rad(90)) -- cylinders lie along X: stand them up
	local function disc(name: string, radius: number, height: number, y: number, c: Color3, material: Enum.Material?)
		add(part(name, Vector3.new(height, radius * 2, radius * 2), c, material or Enum.Material.SmoothPlastic, Enum.PartType.Cylinder), CFrame.new(0, y, 0) * upright)
	end
	if shape == "Cone" then
		for i = 1, 4 do
			disc("Layer" .. i, 1.15 - (i - 1) * 0.28, 0.5, 0.25 + (i - 1) * 0.5, color)
		end
		add(part("Pom", Vector3.new(0.5, 0.5, 0.5), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, Enum.PartType.Ball), CFrame.new(0, 2.3, 0))
	elseif shape == "Wizard" then
		disc("Brim", 1.6, 0.15, 0.1, color)
		for i = 1, 5 do
			disc("Layer" .. i, 1.0 - (i - 1) * 0.2, 0.55, 0.45 + (i - 1) * 0.55, color)
		end
		add(part("Star", Vector3.new(0.45, 0.45, 0.45), Color3.fromRGB(255, 230, 90), Enum.Material.Neon, Enum.PartType.Ball), CFrame.new(0, 3.2, 0))
	elseif shape == "TopHat" then
		disc("Brim", 1.5, 0.15, 0.1, color)
		disc("Tube", 0.95, 1.4, 0.85, color)
		disc("Band", 0.98, 0.3, 0.4, Color3.fromRGB(200, 40, 40))
	elseif shape == "Crown" then
		disc("Ring", 1.05, 0.5, 0.25, color, Enum.Material.Metal)
		for i = 0, 4 do
			local angle = i / 5 * math.pi * 2
			add(part("Spike" .. i, Vector3.new(0.35, 0.8, 0.35), color, Enum.Material.Metal), CFrame.new(math.cos(angle) * 0.95, 0.9, math.sin(angle) * 0.95))
			add(part("Gem" .. i, Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(255, 60, 90), Enum.Material.Neon, Enum.PartType.Ball), CFrame.new(math.cos(angle) * 0.95, 1.4, math.sin(angle) * 0.95))
		end
	elseif shape == "Halo" then
		for i = 0, 11 do
			local angle = i / 12 * math.pi * 2
			add(part("Bead" .. i, Vector3.new(0.35, 0.2, 0.5), color, Enum.Material.Neon), CFrame.new(math.cos(angle) * 1.25, 1.5, math.sin(angle) * 1.25) * CFrame.Angles(0, -angle, 0))
		end
	elseif shape == "Horns" then
		for side = -1, 1, 2 do
			add(part("HornBase", Vector3.new(0.4, 0.6, 0.4), color, Enum.Material.SmoothPlastic), CFrame.new(side * 0.6, 0.35, 0) * CFrame.Angles(0, 0, math.rad(-side * 15)))
			add(part("HornTip", Vector3.new(0.25, 0.6, 0.25), color, Enum.Material.SmoothPlastic), CFrame.new(side * 0.85, 0.95, 0) * CFrame.Angles(0, 0, math.rad(-side * 30)))
		end
	end
	return list
end

local function buildHat(character: Model, cosmetic)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local model = Instance.new("Model")
	model.Name = "Cosmetic_Hat"
	for _, entry in hatParts(cosmetic.Shape, cosmetic.Color) do
		local p = entry.Part
		-- offsets are from the top of the head
		p.CFrame = head.CFrame * CFrame.new(0, head.Size.Y / 2, 0) * entry.Offset
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = p
		weld.Parent = p
	end
	model.Parent = character
end

local function buildTrail(root: BasePart, cosmetic)
	local top = Instance.new("Attachment")
	top.Name = "CosmeticTrailTop"
	top.Position = Vector3.new(0, 0.9, 0)
	top.Parent = root
	local bottom = Instance.new("Attachment")
	bottom.Name = "CosmeticTrailBottom"
	bottom.Position = Vector3.new(0, -0.9, 0)
	bottom.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "Cosmetic_Trail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = 0.7
	trail.LightEmission = 1
	trail.FaceCamera = true
	if cosmetic.Rainbow then
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
			ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 40)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(80, 255, 90)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(60, 200, 255)),
			ColorSequenceKeypoint.new(0.8, Color3.fromRGB(120, 80, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 200)),
		})
	else
		trail.Color = ColorSequence.new(cosmetic.C1, cosmetic.C2)
	end
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = root
end

local function buildAura(root: BasePart, cosmetic)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Cosmetic_Aura"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(cosmetic.Color)
	emitter.LightEmission = 1
	emitter.Rate = cosmetic.Rate or 12
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Parent = root
end

local function clearVisuals(character: Model, kind: string?)
	for _, descendant in character:GetDescendants() do
		local name = descendant.Name
		if (kind == nil and name:sub(1, 9) == "Cosmetic_") or (kind ~= nil and name == "Cosmetic_" .. kind) then
			descendant:Destroy()
		end
	end
	if kind == nil or kind == "Trail" then
		for _, descendant in character:GetDescendants() do
			if descendant.Name == "CosmeticTrailTop" or descendant.Name == "CosmeticTrailBottom" then
				descendant:Destroy()
			end
		end
	end
end

-- (re)builds what the player wears on their current character
function CosmeticService:Apply(player: Player)
	local character = player.Character
	local data = S.DataService:Get(player)
	if not character or not data then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	clearVisuals(character, nil)
	for _, kind in CC.Kinds do
		local cosmetic = CC.ById[data.Cosmetics.Equipped[kind.Id]]
		if cosmetic and data.Cosmetics.Owned[cosmetic.Id] then
			if kind.Id == "Trail" then
				buildTrail(root, cosmetic)
			elseif kind.Id == "Aura" then
				buildAura(root, cosmetic)
			else
				buildHat(character, cosmetic)
			end
		end
	end
	player:SetAttribute("CosmeticHat", data.Cosmetics.Equipped.Hat)
	player:SetAttribute("CosmeticTrail", data.Cosmetics.Equipped.Trail)
	player:SetAttribute("CosmeticAura", data.Cosmetics.Equipped.Aura)
end

---------------------------------------------------------------------------
-- Owning
---------------------------------------------------------------------------
function CosmeticService:Give(player: Player, id: string, announce: boolean?): boolean
	local data = S.DataService:Get(player)
	local cosmetic = CC.ById[id]
	if not data or not cosmetic then
		return false
	end
	local fresh = not data.Cosmetics.Owned[id]
	data.Cosmetics.Owned[id] = true
	if fresh and announce then
		Remotes.Notify:FireClient(player, { Text = "✨ New cosmetic: " .. cosmetic.Icon .. " " .. cosmetic.Name .. "! Equip it in the Style menu.", Type = "success", Duration = 6 })
	end
	if S.ProgressService then
		S.ProgressService:Record(player, "Cosmetic", 0)
	end
	return fresh
end

function CosmeticService:Take(player: Player, id: string): boolean
	local data = S.DataService:Get(player)
	if not data or not data.Cosmetics.Owned[id] then
		return false
	end
	data.Cosmetics.Owned[id] = nil
	for kind, equipped in data.Cosmetics.Equipped do
		if equipped == id then
			data.Cosmetics.Equipped[kind] = nil
		end
	end
	self:Apply(player)
	return true
end

function CosmeticService:Equip(player: Player, id: any): (boolean, string)
	local data = S.DataService:Get(player)
	local cosmetic = type(id) == "string" and CC.ById[id]
	if not data or not cosmetic then
		return false, "Unknown cosmetic."
	end
	if not data.Cosmetics.Owned[id] then
		return false, "You don't own that yet."
	end
	data.Cosmetics.Equipped[cosmetic.Kind] = id
	self:Apply(player)
	return true, "Wearing " .. cosmetic.Name .. "!"
end

function CosmeticService:Unequip(player: Player, kind: any): (boolean, string)
	local data = S.DataService:Get(player)
	if not data or type(kind) ~= "string" or data.Cosmetics.Equipped[kind] == nil then
		return false, "Nothing to take off."
	end
	data.Cosmetics.Equipped[kind] = nil
	self:Apply(player)
	return true, "Taken off."
end

local function canSimulate()
	return RunService:IsStudio() and Config.Monetization.SimulateUnconfiguredInStudio
end

function CosmeticService:Buy(player: Player, id: any): (boolean, string)
	local data = S.DataService:Get(player)
	local cosmetic = type(id) == "string" and CC.ById[id]
	if not data or not cosmetic then
		return false, "Unknown cosmetic."
	end
	if data.Cosmetics.Owned[id] then
		return false, "You already own it!"
	end
	if cosmetic.Source then
		return false, "You can't buy this one - it's a " .. string.lower(cosmetic.Source) .. " reward."
	end
	if cosmetic.Price then
		if not S.DataService:SpendCash(player, cosmetic.Price) then
			return false, "You need " .. Util.Money(cosmetic.Price) .. "!"
		end
		self:Give(player, id)
		return true, "Bought " .. cosmetic.Name .. "!"
	end
	-- Robux
	if cosmetic.ProductId and cosmetic.ProductId ~= 0 then
		MarketplaceService:PromptProductPurchase(player, cosmetic.ProductId)
		return true, "Follow the purchase prompt..."
	elseif canSimulate() then
		self:Give(player, id)
		return true, "[Studio] Simulated purchase of " .. cosmetic.Name
	end
	return false, "This cosmetic isn't available yet!"
end

function CosmeticService:GetState(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return nil
	end
	return { Owned = Util.DeepCopy(data.Cosmetics.Owned), Equipped = Util.DeepCopy(data.Cosmetics.Equipped), Count = count(data.Cosmetics.Owned) }
end

function CosmeticService:Init(services)
	S = services
	Remotes.CosmeticsGet.OnServerInvoke = function(player)
		return self:GetState(player)
	end
	Remotes.CosmeticsAction.OnServerInvoke = function(player, action, arg)
		local now = os.clock()
		if lastAction[player] and now - lastAction[player] < 0.25 then
			return false, "Slow down!"
		end
		lastAction[player] = now
		if action == "Buy" then
			return self:Buy(player, arg)
		elseif action == "Equip" then
			return self:Equip(player, arg)
		elseif action == "Unequip" then
			return self:Unequip(player, arg)
		end
		return false, "Unknown action."
	end
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.3)
			if player.Parent then
				self:Apply(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		-- drop equipped cosmetics that no longer exist
		local data = S.DataService:Get(player)
		for kind, id in data.Cosmetics.Equipped do
			if not CC.ById[id] or not data.Cosmetics.Owned[id] then
				data.Cosmetics.Equipped[kind] = nil
			end
		end
		self:Apply(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return CosmeticService
