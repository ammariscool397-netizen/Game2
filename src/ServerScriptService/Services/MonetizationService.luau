--[[
	MonetizationService - game passes + developer products (Robux shop).
	Pass ownership is mirrored to player attributes "Pass_<Key>" = true.
	Unconfigured items (Id = 0) are simulated in Studio for easy testing.
]]
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local MonetizationService = {}
local S

local purchaseHistory: DataStore? = nil
pcall(function()
	purchaseHistory = DataStoreService:GetDataStore(Config.DataStoreName .. "_Purchases")
end)

local passByKey = Config.GamePasses
local passKeyById: { [number]: string } = {}
local productKeyById: { [number]: string } = {}
for key, pass in passByKey do
	if pass.Id ~= 0 then
		passKeyById[pass.Id] = key
	end
end
for key, product in Config.Products do
	if product.Id ~= 0 then
		productKeyById[product.Id] = key
	end
end

local function canSimulate()
	return RunService:IsStudio() and Config.Monetization.SimulateUnconfiguredInStudio
end

function MonetizationService:Init(services)
	S = services

	S.DataService.PlayerLoaded:Connect(function(player, data)
		for key, pass in passByKey do
			local owns = data.Passes[key] == true
			if not owns and pass.Id ~= 0 then
				local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass.Id)
				owns = ok and result == true
			end
			if owns then
				self:_applyPass(player, key, false)
			end
		end
		S.DataService:RefreshMultiplier(player)
		self:RefreshCharacter(player) -- rebirth rank speed and tag (the character may have spawned first)
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			self:_applyCharacterPerks(player, character)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function(character)
			self:_applyCharacterPerks(player, character)
		end)
	end

	Remotes.BuyPass.OnServerEvent:Connect(function(player, key)
		self:PromptPass(player, key)
	end)
	Remotes.BuyProduct.OnServerEvent:Connect(function(player, key)
		self:PromptProduct(player, key)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passKeyById[passId] then
			self:_applyPass(player, passKeyById[passId], true)
		end
	end)

	MarketplaceService.ProcessReceipt = function(receipt)
		return self:_processReceipt(receipt)
	end
end

function MonetizationService:HasPass(player: Player, key: string): boolean
	return player:GetAttribute("Pass_" .. key) == true
end

function MonetizationService:GetBaseSpeed(player: Player): number
	local data = S.DataService:Get(player)
	local perk = data and Config.RebirthPerk(data.Rebirths, "Speed") or 0
	return (self:HasPass(player, "SuperSpeed") and Config.BaseWalkSpeed * 2 or Config.BaseWalkSpeed) + perk
end

-- the rebirth rank tag above a character's head
function MonetizationService:_applyRankTag(player: Player, character: Model)
	local head = character:FindFirstChild("Head")
	local data = S.DataService:Get(player)
	local _, rank = Config.RebirthRank(data and data.Rebirths or 0)
	local tag = head and head:FindFirstChild("RankTag") :: BillboardGui?
	if not head or not rank then
		return
	end
	if not tag then
		tag = Instance.new("BillboardGui")
		assert(tag)
		tag.Name = "RankTag"
		tag.Size = UDim2.fromOffset(120, 24)
		tag.StudsOffset = Vector3.new(0, self:HasPass(player, "VIP") and 3.6 or 2.6, 0)
		tag.MaxDistance = 80
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromRGB(220, 170, 255)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = label
		label.Parent = tag
		tag.Parent = head
	end
	local label = tag:FindFirstChild("Label") :: TextLabel?
	if label then
		label.Text = rank.Icon .. " " .. rank.Name
	end
end

-- re-apply speed and the rank tag to the current character (after a rebirth)
function MonetizationService:RefreshCharacter(player: Player)
	local character = player.Character
	if character then
		task.spawn(self._applyCharacterPerks, self, player, character)
	end
end

-- grant = also store in data (admin / simulated purchases)
function MonetizationService:GrantPass(player: Player, key: string)
	local data = S.DataService:Get(player)
	if data then
		data.Passes[key] = true
	end
	self:_applyPass(player, key, true)
end

function MonetizationService:RevokePass(player: Player, key: string)
	local data = S.DataService:Get(player)
	if data then
		data.Passes[key] = nil
	end
	player:SetAttribute("Pass_" .. key, nil)
	S.DataService:RefreshMultiplier(player)
	if S.TycoonService then
		S.TycoonService:RefreshPlayer(player)
	end
end

function MonetizationService:_applyPass(player: Player, key: string, announce: boolean)
	if not passByKey[key] then
		return
	end
	player:SetAttribute("Pass_" .. key, true)
	S.DataService:RefreshMultiplier(player)
	if S.TycoonService then
		if key == "AutoCollect" then
			S.TycoonService:CollectVault(player)
		end
		S.TycoonService:RefreshPlayer(player)
	end
	if player.Character then
		self:_applyCharacterPerks(player, player.Character)
	end
	if announce then
		local pass = passByKey[key]
		Remotes.Notify:FireClient(player, { Text = "Thanks for buying " .. pass.Name .. "! " .. pass.Icon, Type = "success", Duration = 6 })
		Remotes.VFX:FireAllClients("Purchase", { Position = player.Character and player.Character:GetPivot().Position, Color = pass.Color, Big = true })
		Remotes.Announce:FireAllClients({ Title = "🎉 " .. player.DisplayName .. " bought " .. pass.Name .. "!", Text = pass.Description, Color = pass.Color })
	end
end

function MonetizationService:_applyCharacterPerks(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = self:GetBaseSpeed(player)
	self:_applyRankTag(player, character)
	if self:HasPass(player, "VIP") then
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and not root:FindFirstChild("VIPAura") then
			local attachment = Instance.new("Attachment")
			attachment.Name = "VIPAura"
			attachment.Parent = root
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
			sparkle.LightEmission = 1
			sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
			sparkle.Rate = 8
			sparkle.Lifetime = NumberRange.new(1, 1.5)
			sparkle.Speed = NumberRange.new(1, 2)
			sparkle.SpreadAngle = Vector2.new(180, 180)
			sparkle.Parent = attachment
		end
		local head = character:FindFirstChild("Head")
		if head and not head:FindFirstChild("VIPTag") then
			local tag = Instance.new("BillboardGui")
			tag.Name = "VIPTag"
			tag.Size = UDim2.fromOffset(80, 26)
			tag.StudsOffset = Vector3.new(0, 2.6, 0)
			tag.AlwaysOnTop = false
			tag.MaxDistance = 80
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = "👑 VIP"
			label.TextScaled = true
			label.Font = Enum.Font.FredokaOne
			label.TextColor3 = Color3.fromRGB(255, 210, 0)
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Parent = label
			label.Parent = tag
			tag.Parent = head
		end
	end
end

function MonetizationService:PromptPass(player: Player, key: any)
	local pass = type(key) == "string" and passByKey[key]
	if not pass then
		return
	end
	if self:HasPass(player, key) then
		Remotes.Notify:FireClient(player, { Text = "You already own " .. pass.Name .. "!", Type = "info" })
		return
	end
	if pass.Id == 0 then
		if canSimulate() then
			Remotes.Notify:FireClient(player, { Text = "[Studio] Simulated purchase of " .. pass.Name, Type = "info" })
			self:GrantPass(player, key)
		else
			Remotes.Notify:FireClient(player, { Text = "This pass isn't available yet!", Type = "error" })
		end
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, pass.Id)
end

function MonetizationService:PromptProduct(player: Player, key: any)
	local product = type(key) == "string" and Config.Products[key]
	if not product then
		return
	end
	if product.Id == 0 then
		if canSimulate() then
			Remotes.Notify:FireClient(player, { Text = "[Studio] Simulated purchase of " .. product.Name, Type = "info" })
			self:_grantProduct(player, key)
		else
			Remotes.Notify:FireClient(player, { Text = "This product isn't available yet!", Type = "error" })
		end
		return
	end
	MarketplaceService:PromptProductPurchase(player, product.Id)
end

function MonetizationService:_grantProduct(player: Player, key: string): boolean
	local product = Config.Products[key]
	local data = S.DataService:Get(player)
	if not product or not data then
		return false
	end
	if product.Minutes then
		local amount = math.max(product.MinCash * (1 + data.Rebirths), S.TycoonService:GetIncome(player) * product.Minutes * 60)
		S.DataService:AddCash(player, amount, false)
		Remotes.Notify:FireClient(player, { Text = "+" .. Util.Money(amount) .. " added! Thank you! 💰", Type = "success", Duration = 6 })
		Remotes.VFX:FireClient(player, "CashBurst", { Amount = amount })
	end
	if product.Repair then
		local count = S.TycoonService:RepairAll(player)
		Remotes.Notify:FireClient(player, { Text = count > 0 and ("🔧 Repaired " .. count .. " upgrades!") or "🔧 Nothing was broken - your tower is fine!", Type = "success", Duration = 6 })
	end
	if product.BoostSeconds then
		S.DataService:AddBoost(player, product.BoostSeconds)
		Remotes.Notify:FireClient(player, { Text = "2x Boost activated! 🚀", Type = "success", Duration = 6 })
	end
	if product.ServerEvent == "CashRain" then
		self:CashRain(player.DisplayName)
	elseif product.ServerEvent and S.DisasterService then
		local message = S.DisasterService:Trigger(product.ServerEvent, player.DisplayName)
		Remotes.Notify:FireClient(player, { Text = message, Type = "info" })
	end
	Remotes.VFX:FireClient(player, "Confetti", {})
	return true
end

-- Everybody in the server gets cash, with a big falling-cash effect
function MonetizationService:CashRain(byName: string)
	Remotes.Announce:FireAllClients({
		Title = "🌧️ CASH RAIN! 🌧️",
		Text = byName .. " made it rain for the whole server!",
		Color = Color3.fromRGB(80, 220, 120),
	})
	Remotes.VFX:FireAllClients("CashRain", { Duration = 8 })
	for _, p in Players:GetPlayers() do
		local data = S.DataService:Get(p)
		if data then
			local amount = math.max(5_000 * (1 + data.Rebirths), S.TycoonService:GetIncome(p) * 120)
			S.DataService:AddCash(p, amount, false)
			Remotes.Notify:FireClient(p, { Text = "Cash Rain: +" .. Util.Money(amount), Type = "success" })
		end
	end
end

function MonetizationService:_processReceipt(receipt)
	local key = productKeyById[receipt.ProductId]
	if not key then
		warn("[Monetization] Unknown product id " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not S.DataService:IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local historyKey = receipt.PlayerId .. "_" .. receipt.PurchaseId
	if purchaseHistory then
		local ok, already = pcall(function()
			return (purchaseHistory :: DataStore):GetAsync(historyKey)
		end)
		if not ok then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if already then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	local granted = self:_grantProduct(player, key)
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- persist the player's data right away so the purchase is never lost
	S.DataService:Save(player)
	if purchaseHistory then
		pcall(function()
			(purchaseHistory :: DataStore):SetAsync(historyKey, true)
		end)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return MonetizationService
