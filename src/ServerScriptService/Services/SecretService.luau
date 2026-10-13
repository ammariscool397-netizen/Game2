--[[
	SecretService - 12 secrets hidden around the map (see Config.Secrets and
	the spots in WorldBuilder / ObbyService). Finding one gives cash and
	permanently builds a relic in your tower (+5% income, survives rebirths).
]]
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local BuildKit = require(script.Parent.BuildKit)

local SecretService = {}
local S

local byId = {}
for _, secret in Config.Secrets do
	byId[secret.Id] = secret
end

function SecretService:Init(services)
	S = services
	local folder = Instance.new("Folder")
	folder.Name = "Secrets"
	folder.Parent = workspace

	local spots = table.clone(S.WorldBuilder.SecretSpots)
	if S.ObbyService and S.ObbyService.SecretSpot then
		spots.Obby = S.ObbyService.SecretSpot
	end

	for _, secret in Config.Secrets do
		local pos = spots[secret.Id]
		if pos then
			self:_spawnGem(folder, secret, pos)
		else
			warn("[Secrets] No spot for secret " .. secret.Id)
		end
	end
end

function SecretService:_spawnGem(folder: Folder, secret, position: Vector3)
	local model = BuildKit.Model("Secret_" .. secret.Id, folder)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local gem = BuildKit.Part({
		Name = "SecretGem",
		Size = Vector3.one * 1.6,
		CFrame = CFrame.new(position) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = secret.Color,
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin", "Bob" },
		Parent = model,
	})
	BuildKit.Light(gem, secret.Color, 10, 1.5)
	BuildKit.Particles(gem, {
		Color = ColorSequence.new(secret.Color, Color3.new(1, 1, 1)),
		Size = BuildKit.Size(0.4),
		Rate = 8,
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(180, 180),
	})
	-- generous touch box so it's easy to grab
	local hitbox = BuildKit.Part({ Name = "Hitbox", Size = Vector3.new(5, 6, 5), Position = position, Transparency = 1, CanCollide = false, Parent = model })
	local busy = {}
	hitbox.Touched:Connect(function(hit)
		local player = BuildKit.PlayerFromHit(hit)
		if player and not busy[player] and BuildKit.IsNear(player, hitbox) then
			busy[player] = true
			self:Find(player, secret.Id)
			task.delay(2, function()
				busy[player] = nil
			end)
		end
	end)
end

function SecretService:Count(player: Player): number
	local data = S.DataService:Get(player)
	if not data then
		return 0
	end
	local n = 0
	for _ in data.Secrets do
		n += 1
	end
	return n
end

function SecretService:Find(player: Player, secretId: string, silent: boolean?): boolean
	local data = S.DataService:Get(player)
	local secret = byId[secretId]
	if not data or not secret then
		return false
	end
	if data.Secrets[secretId] then
		if not silent then
			Remotes.Notify:FireClient(player, { Text = "You already found " .. secret.Name .. ".", Type = "info", Duration = 2 })
		end
		return false
	end
	data.Secrets[secretId] = true
	local count = self:Count(player)
	local rewards = Config.SecretRewards
	local cash = math.max(rewards.MinCash * (1 + data.Rebirths), S.TycoonService:GetIncome(player) * rewards.IncomeSeconds)
	S.DataService:AddCash(player, cash, false)
	S.DataService:Sync(player)
	S.TycoonService:OnSecretFound(player, secretId)
	if S.QuestService then
		S.QuestService:Progress(player, "Secret", 1)
	end
	if secret.BadgeId and secret.BadgeId ~= 0 then
		task.spawn(pcall, BadgeService.AwardBadge, BadgeService, player.UserId, secret.BadgeId)
	end
	if not silent then
		Remotes.VFX:FireClient(player, "SecretFound", { Name = secret.Name, Count = count, Total = #Config.Secrets, Color = secret.Color, Cash = cash })
		Remotes.Notify:FireClient(player, {
			Text = "🕵️ SECRET FOUND: " .. secret.Name .. " (" .. count .. "/" .. #Config.Secrets .. ") +" .. Util.Money(cash) .. " and +" .. rewards.BonusPercent .. "% income forever!",
			Type = "success",
			Duration = 8,
		})
		Remotes.Announce:FireAllClients({ Title = "🕵️ " .. player.DisplayName .. " found a secret!", Text = secret.Name .. " (" .. count .. "/" .. #Config.Secrets .. ")", Color = secret.Color })
		if count == #Config.Secrets then
			Remotes.Announce:FireAllClients({ Title = "🏅 SECRET MASTER!", Text = player.DisplayName .. " found ALL " .. count .. " secrets!", Color = Color3.fromRGB(255, 215, 0) })
		end
	end
	return true
end

function SecretService:FindAll(player: Player)
	for _, secret in Config.Secrets do
		self:Find(player, secret.Id, true)
	end
end

function SecretService:Reset(player: Player)
	local data = S.DataService:Get(player)
	if data then
		data.Secrets = {}
		S.DataService:Sync(player)
		S.TycoonService:Rebuild(player)
	end
end

return SecretService
