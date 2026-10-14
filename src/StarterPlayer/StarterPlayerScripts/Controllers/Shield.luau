--[[
	Shield (client) - the personal shield panel: activate it, see how long it
	lasts and when it can be used again. Times come from the server's saved
	values, so rejoining doesn't change them.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme
local SC = Config.Shield

local Shield = {}
local C

local statusLabel: TextLabel
local activateButton: TextButton
local busy = false

-- "active" (seconds left), "recharging" (seconds left) or "ready"
function Shield:GetState(): (string, number)
	local now = Util.ServerNow()
	local untilTime = player:GetAttribute("ShieldEnd") or 0
	local readyAt = player:GetAttribute("ShieldReadyAt") or 0
	if now < untilTime then
		return "active", untilTime - now
	elseif now < readyAt then
		return "recharging", readyAt - now
	end
	return "ready", 0
end

local function refresh()
	local state, left = Shield:GetState()
	if state == "active" then
		statusLabel.Text = "🛡️ SHIELD ACTIVE - " .. Util.Clock(left) .. " left"
		statusLabel.TextColor3 = Theme.Accent2
		activateButton.Text = "ACTIVE"
		activateButton.BackgroundColor3 = Theme.PanelLight
	elseif state == "recharging" then
		statusLabel.Text = "Recharging: " .. Util.Clock(left)
		statusLabel.TextColor3 = Theme.SubText
		activateButton.Text = "RECHARGING"
		activateButton.BackgroundColor3 = Theme.PanelLight
	else
		statusLabel.Text = "Your shield is ready!"
		statusLabel.TextColor3 = Theme.Green
		activateButton.Text = "🛡️ ACTIVATE"
		activateButton.BackgroundColor3 = Theme.Green
	end
	if C.HUD and C.HUD.SetBadge then
		C.HUD:SetBadge("Shield", state == "ready")
	end
end

function Shield:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Shield", "🛡️ SHIELD", Theme.Accent2, 520, 340)
	UIKit.List(content, 14)
	UIKit.new("TextLabel", {
		Text = "A shield protects you from every disaster for " .. Util.FormatTime(SC.Seconds) .. ", wherever you are. It recharges for " .. Util.FormatTime(SC.Cooldown) .. " after you use it - leaving and rejoining doesn't reset that.",
		Size = UDim2.new(1, -20, 0, 90),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 18,
		Font = Theme.BodyFont,
		TextColor3 = Theme.SubText,
		LayoutOrder = 1,
		ZIndex = 7,
		Parent = content,
	})
	statusLabel = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, ZIndex = 7, Parent = content })
	activateButton = UIKit.Button({
		Name = "ActivateShield",
		Text = "...",
		Color = Theme.Green,
		Size = UDim2.fromOffset(280, 56),
		LayoutOrder = 3,
		ZIndex = 7,
		Parent = content,
		Callback = function()
			if busy or Shield:GetState() ~= "ready" then
				return
			end
			busy = true
			local ok, message = Remotes.ActivateShield:InvokeServer()
			busy = false
			C.Notifications:Toast(tostring(message), ok and "success" or "error")
			refresh()
		end,
	})
	player:GetAttributeChangedSignal("ShieldEnd"):Connect(refresh)
	player:GetAttributeChangedSignal("ShieldReadyAt"):Connect(refresh)
	refresh()
end

function Shield:Start()
	while true do
		task.wait(1)
		Util.Try("Shield", refresh)
	end
end

return Shield
