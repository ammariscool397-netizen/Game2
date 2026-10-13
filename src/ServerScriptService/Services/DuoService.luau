--[[
	DuoService - invite a friend to build ONE tower together with ONE shared
	wallet. Progress saves to the tower owner (host). When the duo ends,
	the partner gets their own tower back with their own saved progress.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local DuoService = {}
local S

local invites: { [Player]: { Host: Player, Expires: number } } = {}
local cooldown: { [Player]: number } = {}

local function inDuo(player: Player): boolean
	return player:GetAttribute("DuoHost") ~= nil or player:GetAttribute("DuoPartner") ~= nil
end

function DuoService:Init(services)
	S = services
	if not Config.Duo.Enabled then
		return
	end

	Remotes.DuoInvite.OnServerEvent:Connect(function(host, targetUserId)
		local target = typeof(targetUserId) == "number" and Players:GetPlayerByUserId(targetUserId)
		if target then
			self:Invite(host, target)
		end
	end)
	Remotes.DuoRespond.OnServerEvent:Connect(function(player, hostUserId, accept)
		self:Respond(player, hostUserId, accept == true)
	end)
	Remotes.DuoLeave.OnServerEvent:Connect(function(player)
		self:Leave(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		invites[player] = nil
		cooldown[player] = nil
	end)
end

function DuoService:Invite(host: Player, target: Player): (boolean, string)
	local function fail(message: string)
		Remotes.Notify:FireClient(host, { Text = message, Type = "error" })
		return false, message
	end
	if host == target then
		return fail("You can't invite yourself!")
	end
	if cooldown[host] and os.clock() - cooldown[host] < 4 then
		return fail("Wait a moment before inviting again.")
	end
	local plot = S.TycoonService:GetPlot(host)
	if not plot or plot.Owner ~= host then
		return fail("You need your own tower to invite someone.")
	end
	if plot.Partner then
		return fail("You already have a duo partner!")
	end
	if inDuo(target) then
		return fail(target.DisplayName .. " is already in a duo.")
	end
	if not S.DataService:IsLoaded(target) then
		return fail(target.DisplayName .. " is still loading.")
	end
	cooldown[host] = os.clock()
	invites[target] = { Host = host, Expires = os.clock() + Config.Duo.InviteTimeout }
	Remotes.DuoInvited:FireClient(target, { HostName = host.DisplayName, HostUserId = host.UserId, Timeout = Config.Duo.InviteTimeout })
	Remotes.Notify:FireClient(host, { Text = "Duo invite sent to " .. target.DisplayName .. "!", Type = "success" })
	return true, "Invite sent"
end

function DuoService:Respond(player: Player, hostUserId: any, accept: boolean)
	local invite = invites[player]
	invites[player] = nil
	if not invite or invite.Host.UserId ~= hostUserId then
		return
	end
	local host = invite.Host
	if not accept then
		if host.Parent then
			Remotes.Notify:FireClient(host, { Text = player.DisplayName .. " declined your duo invite.", Type = "info" })
		end
		return
	end
	if os.clock() > invite.Expires or not host.Parent then
		Remotes.Notify:FireClient(player, { Text = "That invite expired.", Type = "error" })
		return
	end
	self:Join(host, player)
end

function DuoService:Join(host: Player, partner: Player): (boolean, string)
	if inDuo(host) then
		return false, host.DisplayName .. " is already in a duo"
	end
	if inDuo(partner) then
		return false, partner.DisplayName .. " is already in a duo"
	end
	if partner:GetAttribute("InMinigame") then
		return false, partner.DisplayName .. " is in a minigame"
	end
	local ok = S.TycoonService:AddPartner(host, partner)
	if not ok then
		Remotes.Notify:FireClient(partner, { Text = "Couldn't join that tower.", Type = "error" })
		return false, "Couldn't join"
	end
	Remotes.Notify:FireClient(partner, { Text = "👥 You're now building with " .. host.DisplayName .. "! You share one wallet. Your own tower is saved for later.", Type = "success", Duration = 8 })
	Remotes.Notify:FireClient(host, { Text = "👥 " .. partner.DisplayName .. " joined your tower!", Type = "success", Duration = 6 })
	Remotes.Announce:FireAllClients({ Title = "👥 NEW DUO!", Text = host.DisplayName .. " & " .. partner.DisplayName .. " are building together", Color = Color3.fromRGB(0, 200, 255) })
	Remotes.VFX:FireClient(host, "Confetti", {})
	Remotes.VFX:FireClient(partner, "Confetti", {})
	return true, "Duo formed"
end

-- partner leaves, or host kicks their partner
function DuoService:Leave(player: Player)
	local plot = S.TycoonService:GetPlot(player)
	if not plot or not plot.Partner then
		return
	end
	local partner = plot.Partner
	local host = plot.Owner
	S.TycoonService:RemovePartner(plot, true)
	if host and host.Parent then
		Remotes.Notify:FireClient(host, { Text = (player == host and "You ended the duo." or (partner.DisplayName .. " left your duo.")), Type = "info" })
	end
	if partner.Parent then
		Remotes.Notify:FireClient(partner, { Text = (player == partner and "You left the duo. Back to your own tower!" or (host.DisplayName .. " ended the duo. Back to your own tower!")), Type = "info", Duration = 6 })
	end
end

return DuoService
