--[[ Duo (client) - invite players to build one tower together + invite popups ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Duo = {}
local C

local statusLabel: TextLabel
local leaveButton: TextButton
local list: ScrollingFrame
local popup: Frame
local popupText: TextLabel
local popupTimer: TextLabel
local pendingHost: number? = nil
local popupToken = 0

local function nameOf(userId: number?): string
	local p = userId and Players:GetPlayerByUserId(userId)
	return p and p.DisplayName or "someone"
end

local function refresh()
	local host = player:GetAttribute("DuoHost")
	local partner = player:GetAttribute("DuoPartner")
	if host then
		statusLabel.Text = "👥 You're building with " .. nameOf(host) .. " (shared wallet)"
		leaveButton.Text = "LEAVE DUO"
		leaveButton.Visible = true
	elseif partner then
		statusLabel.Text = "👥 " .. nameOf(partner) .. " is building in your tower"
		leaveButton.Text = "END DUO"
		leaveButton.Visible = true
	else
		statusLabel.Text = "Invite someone to build ONE tower together. You share one wallet; it saves to the tower owner."
		leaveButton.Visible = false
	end

	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local order = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			order += 1
			local row = UIKit.new("Frame", { Size = UDim2.new(1, -10, 0, 52), BackgroundColor3 = order % 2 == 0 and Theme.PanelLight or Theme.Panel, LayoutOrder = order, ZIndex = 7, Parent = list })
			UIKit.Corner(row, 8)
			UIKit.Label({ Text = other.DisplayName, Size = UDim2.new(1, -200, 0, 26), Position = UDim2.fromOffset(12, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = row })
			local busy = other:GetAttribute("DuoHost") or other:GetAttribute("DuoPartner")
			UIKit.Label({
				Text = busy and "in a duo" or ("Rebirth " .. (other:GetAttribute("Rebirths") or 0)),
				Size = UDim2.new(1, -200, 0, 16),
				Position = UDim2.fromOffset(12, 31),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.BodyFont,
				TextColor3 = Theme.SubText,
				Stroke = false,
				ZIndex = 8,
				Parent = row,
			})
			local canInvite = not busy and not host and not partner
			UIKit.Button({
				Text = canInvite and "INVITE 👥" or "—",
				Color = canInvite and Theme.Accent2 or Color3.fromRGB(80, 80, 95),
				Size = UDim2.fromOffset(150, 38),
				Position = UDim2.new(1, -160, 0, 7),
				ZIndex = 8,
				Parent = row,
				Callback = function()
					if canInvite then
						Remotes.DuoInvite:FireServer(other.UserId)
					end
				end,
			})
		end
	end
	if order == 0 then
		local row = UIKit.new("Frame", { Size = UDim2.new(1, -10, 0, 52), BackgroundTransparency = 1, ZIndex = 7, Parent = list })
		UIKit.Label({ Text = "Nobody else is here yet - invite a friend to the server!", Size = UDim2.new(1, 0, 1, 0), Font = Theme.BodyFont, ZIndex = 8, Parent = row })
	end
end

local function buildPanel()
	local _, content = C.UI:MakePanel("Duo", "👥 DUO BUILD", Color3.fromRGB(0, 190, 255), 620, 480, refresh)
	statusLabel = UIKit.new("TextLabel", {
		Text = "",
		Size = UDim2.new(1, -190, 0, 46),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 16,
		Font = Theme.BodyFont,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 7,
		Parent = content,
	})
	leaveButton = UIKit.Button({ Text = "LEAVE DUO", Color = Theme.Red, Size = UDim2.fromOffset(170, 42), Position = UDim2.new(1, -170, 0, 2), ZIndex = 7, Parent = content, Callback = function()
		Remotes.DuoLeave:FireServer()
		task.delay(0.5, refresh)
	end })
	list = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -58), Position = UDim2.fromOffset(0, 56), Parent = content })
	UIKit.List(list, 6)
end

local function buildPopup()
	popup = UIKit.new("Frame", {
		Size = UDim2.fromOffset(400, 150),
		Position = UDim2.new(0.5, 0, 0, -170),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Panel,
		ZIndex = 30,
		Parent = C.UI.FX,
	})
	UIKit.Corner(popup, 16)
	UIKit.Stroke(popup, Theme.Accent2, 3)
	UIKit.Gradient(popup, Theme.PanelLight, Theme.Panel, 90)
	UIKit.Label({ Text = "👥 DUO INVITE", Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 8), TextColor3 = Theme.Accent2, ZIndex = 31, Parent = popup })
	popupText = UIKit.Label({ Text = "", Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 44), Font = Theme.BodyFont, ZIndex = 31, Parent = popup })
	popupTimer = UIKit.Label({ Text = "", Size = UDim2.fromOffset(60, 30), Position = UDim2.new(0, 14, 1, -46), ZIndex = 31, Parent = popup })
	local function respond(accept: boolean)
		if pendingHost then
			Remotes.DuoRespond:FireServer(pendingHost, accept)
		end
		pendingHost = nil
		popupToken += 1
		TweenService:Create(popup, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -170) }):Play()
	end
	UIKit.Button({ Text = "ACCEPT", Color = Theme.Green, Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -290, 1, -56), ZIndex = 31, Parent = popup, Callback = function()
		respond(true)
	end })
	UIKit.Button({ Text = "DECLINE", Color = Theme.Red, Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -150, 1, -56), ZIndex = 31, Parent = popup, Callback = function()
		respond(false)
	end })
	Duo.Respond = respond
end

function Duo:Init(controllers)
	C = controllers
	buildPanel()
	buildPopup()

	Remotes.DuoInvited.OnClientEvent:Connect(function(data)
		pendingHost = data.HostUserId
		popupToken += 1
		local token = popupToken
		popupText.Text = data.HostName .. " wants to build a tower with you!"
		UIKit.PlaySound("Notify", 0.6, 1.2)
		TweenService:Create(popup, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 90) }):Play()
		task.spawn(function()
			for t = data.Timeout or 30, 0, -1 do
				if token ~= popupToken then
					return
				end
				popupTimer.Text = "⏱ " .. t
				task.wait(1)
			end
			if token == popupToken then
				Duo.Respond(false)
			end
		end)
	end)

	for _, attr in { "DuoHost", "DuoPartner" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if C.UI.Current == "Duo" then
				refresh()
			end
		end)
	end
	Players.PlayerAdded:Connect(function()
		if C.UI.Current == "Duo" then
			refresh()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if C.UI.Current == "Duo" then
				refresh()
			end
		end)
	end)
end

return Duo
