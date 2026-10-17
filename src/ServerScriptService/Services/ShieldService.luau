--[[
	ShieldService - the personal shield (see Config.Shield). While it's on you
	are protected from disaster damage (DisasterService:IsProtected) and wear a
	force-field bubble. The activation time is saved, so the cooldown can't be
	skipped by rejoining and an active shield survives a rejoin.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)

local SC = Config.Shield

local ShieldService = {}
local S

function ShieldService:_times(player: Player): (number, number)
	local data = S.DataService:Get(player)
	local start = data and data.Shield.Start or 0
	local pro = S.MonetizationService:HasPass(player, "ShieldPro")
	return start + SC.Seconds * (pro and 2 or 1), start + SC.Cooldown / (pro and 2 or 1) -- (shield ends, ready again)
end

function ShieldService:IsShielded(player: Player): boolean
	local untilTime = self:_times(player)
	return SC.Enabled and os.time() < untilTime
end

-- the bubble and the attributes the client shows
function ShieldService:_apply(player: Player)
	local untilTime, readyAt = self:_times(player)
	player:SetAttribute("ShieldEnd", untilTime)
	player:SetAttribute("ShieldReadyAt", readyAt)
	local character = player.Character
	if not character then
		return
	end
	local field = character:FindFirstChild("ShieldBubble") -- (other force-fields, like the admin ;ff, are left alone)
	if self:IsShielded(player) then
		if not field then
			field = Instance.new("ForceField")
			field.Name = "ShieldBubble"
			field.Visible = true
			field.Parent = character
		end
	elseif field then
		field:Destroy()
	end
end

function ShieldService:Activate(player: Player): (boolean, string)
	local data = S.DataService:Get(player)
	if not data then
		return false, "Data still loading..."
	end
	local _, readyAt = self:_times(player)
	if os.time() < readyAt then
		return false, "Your shield is recharging: " .. Util.FormatTime(readyAt - os.time())
	end
	data.Shield.Start = os.time()
	self:_apply(player)
	Remotes.VFX:FireAllClients("ShieldHit", { Center = player.Character and player.Character:GetPivot().Position or Vector3.zero, Radius = 8 })
	return true, "🛡️ Shield on for " .. Util.FormatTime(SC.Seconds) .. " - disasters can't hurt you!"
end

function ShieldService:Init(services)
	S = services
	Remotes.ActivateShield.OnServerInvoke = function(player)
		if not SC.Enabled then
			return false, "Shields are turned off."
		end
		return self:Activate(player)
	end
	S.DataService.PlayerLoaded:Connect(function(player)
		self:_apply(player)
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				self:_apply(player)
			end)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

-- the bubble goes away when the time is up
function ShieldService:Start()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			if S.DataService:Get(player) then
				Util.Try("Shield", self._apply, self, player)
			end
		end
	end
end

return ShieldService
