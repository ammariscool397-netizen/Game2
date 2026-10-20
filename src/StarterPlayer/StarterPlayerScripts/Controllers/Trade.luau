--[[ Trade (client) - trade pets with another player: player list, the two offers, your pets, Accept ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme
local RARITIES = Config.Pets.Rarities

local Trade = {}
Trade.State = nil :: any
local C

local listView: ScrollingFrame
local tradeView: Frame
local mineGrid: ScrollingFrame
local theirsGrid: ScrollingFrame
local petsGrid: ScrollingFrame
local statusLabel: TextLabel
local acceptButton: TextButton
local mineTitle: TextLabel
local theirsTitle: TextLabel
local popup: Frame
local popupText: TextLabel
local popupTimer: TextLabel
local popupToken = 0

local function act(action: string, arg: any?)
	local ok, message = Remotes.TradeAction:InvokeServer(action, arg)
	if message and message ~= "" and not ok then
		C.Notifications:Toast(tostring(message), "error", 3)
	end
	return ok
end

local function petCard(parent: Instance, order: number, pet, onClick: (() -> ())?)
	local def = Config.PetById[pet.Id]
	local rarity = RARITIES[def.Rarity]
	local button = UIKit.new("TextButton", { Text = "", BackgroundColor3 = Theme.Panel, AutoButtonColor = false, LayoutOrder = order, ZIndex = 8, Parent = parent })
	UIKit.Corner(button, 10)
	UIKit.Stroke(button, rarity.Color, 2)
	UIKit.Label({ Text = def.Icon, Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 2), ZIndex = 9, Parent = button })
	UIKit.Label({ Text = def.Name, Size = UDim2.new(1, -4, 0, 16), Position = UDim2.fromOffset(2, 38), Font = Theme.BodyFont, TextColor3 = rarity.Color, ZIndex = 9, Parent = button })
	UIKit.Label({ Text = "+" .. tostring(rarity.Bonus) .. "x", Size = UDim2.new(1, -4, 0, 14), Position = UDim2.fromOffset(2, 54), Font = Theme.BodyFont, TextColor3 = Theme.SubText, Stroke = false, ZIndex = 9, Parent = button })
	if onClick then
		button.Activated:Connect(function()
			UIKit.PlaySound("Click", 0.4)
			onClick()
		end)
	end
	return button
end

local function fillPlayers()
	UIKit.Clear(listView)
	local order = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			order += 1
			local row = UIKit.Row(listView, order, 52)
			UIKit.Label({ Text = other.DisplayName, Size = UDim2.new(1, -200, 0, 28), Position = UDim2.fromOffset(12, 12), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = row })
			UIKit.Button({ Text = "🤝 TRADE", Color = Theme.Accent2, Size = UDim2.fromOffset(150, 38), Position = UDim2.new(1, -160, 0, 7), ZIndex = 8, Parent = row, Callback = function()
				local ok = act("Invite", other.UserId)
				if ok then
					C.Notifications:Toast("Trade request sent to " .. other.DisplayName .. ".", "info", 3)
				end
			end })
		end
	end
	if order == 0 then
		UIKit.Label({ Text = "Nobody else is in your server right now.", Size = UDim2.new(1, -10, 0, 40), Font = Theme.BodyFont, TextColor3 = Theme.SubText, ZIndex = 8, Parent = listView })
	end
end

local function renderTrade()
	local state = Trade.State
	listView.Visible = state == nil
	tradeView.Visible = state ~= nil
	if not state then
		fillPlayers()
		return
	end
	mineTitle.Text = "YOUR OFFER" .. (state.MyAccepted and "  ✔" or "")
	theirsTitle.Text = state.Partner.Name:upper() .. "'S OFFER" .. (state.TheirAccepted and "  ✔" or "")
	UIKit.Clear(mineGrid)
	UIKit.Clear(theirsGrid)
	UIKit.Clear(petsGrid)
	local offered = {}
	for i, pet in state.Mine do
		offered[pet.Uid] = true
		petCard(mineGrid, i, pet, function()
			act("Remove", pet.Uid)
		end)
	end
	for i, pet in state.Theirs do
		petCard(theirsGrid, i, pet, nil)
	end
	local pets = C.Pets.State and C.Pets.State.Owned or {}
	local order = 0
	for _, pet in pets do
		if not offered[pet.Uid] then
			order += 1
			petCard(petsGrid, order, pet, function()
				act("Add", pet.Uid)
			end)
		end
	end
end

local function updateAccept()
	local state = Trade.State
	if not state then
		return
	end
	local wait = state.ReadyAt - Util.ServerNow()
	if state.MyAccepted then
		acceptButton.Text = "WAITING..."
		acceptButton.BackgroundColor3 = Color3.fromRGB(80, 82, 110)
		statusLabel.Text = state.TheirAccepted and "" or "Waiting for " .. state.Partner.Name .. " to accept..."
	elseif wait > 0 then
		acceptButton.Text = "ACCEPT (" .. math.ceil(wait) .. ")"
		acceptButton.BackgroundColor3 = Color3.fromRGB(80, 82, 110)
		statusLabel.Text = "Check the offers carefully!"
	else
		acceptButton.Text = "✅ ACCEPT"
		acceptButton.BackgroundColor3 = Theme.Green
		statusLabel.Text = state.TheirAccepted and (state.Partner.Name .. " accepted - your turn!") or "Add pets, then press Accept."
	end
end

function Trade:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Trade", "🤝 TRADE", Theme.Accent2, 860, 600, function()
		renderTrade()
	end)

	listView = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, 0), Parent = content })
	UIKit.List(listView, 6)
	UIKit.new("UIPadding", { PaddingRight = UDim.new(0, 8), Parent = listView })

	tradeView = UIKit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 6, Parent = content })
	local function box(x: number, title: string)
		local label = UIKit.Label({ Text = title, Size = UDim2.new(0.5, -6, 0, 26), Position = UDim2.new(x, 0, 0, 0), ZIndex = 7, Parent = tradeView })
		local scroll = UIKit.Scroll({ Size = UDim2.new(0.5, -6, 0, 150), Position = UDim2.new(x, 0, 0, 28), Parent = tradeView })
		local frameBg = UIKit.new("Frame", { Size = UDim2.new(0.5, -6, 0, 150), Position = UDim2.new(x, 0, 0, 28), BackgroundColor3 = Theme.Background, ZIndex = 6, Parent = tradeView })
		UIKit.Corner(frameBg, 10)
		scroll.ZIndex = 7
		local layout = UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(84, 74), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		return label, scroll
	end
	mineTitle, mineGrid = box(0, "YOUR OFFER")
	theirsTitle, theirsGrid = box(0.5, "THEIR OFFER")
	UIKit.Label({ Text = "YOUR PETS (tap to offer)", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 188), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, ZIndex = 7, Parent = tradeView })
	petsGrid = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -300), Position = UDim2.fromOffset(0, 214), Parent = tradeView })
	local layout = UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(84, 74), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = petsGrid })
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	statusLabel = UIKit.Label({ Text = "", Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.new(0, 0, 1, -76), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, ZIndex = 7, Parent = tradeView })
	acceptButton = UIKit.Button({ Text = "✅ ACCEPT", Color = Theme.Green, Size = UDim2.new(0.34, 0, 0, 44), Position = UDim2.new(0.3, 0, 1, -48), ZIndex = 8, Parent = tradeView, Callback = function()
		act("Accept")
	end })
	UIKit.Button({ Text = "❌ CANCEL", Color = Theme.Red, Size = UDim2.new(0.3, 0, 0, 44), Position = UDim2.new(0.68, 0, 1, -48), ZIndex = 8, Parent = tradeView, Callback = function()
		act("Cancel")
	end })

	-- the trade request popup
	popup = UIKit.new("Frame", { Name = "TradePopup", Size = UDim2.fromOffset(380, 100), Position = UDim2.new(0.5, 0, 0, -140), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = Theme.Panel, ZIndex = 30, Parent = C.UI.Gui })
	UIKit.Corner(popup, 14)
	UIKit.Stroke(popup, Theme.Accent2, 3)
	popupText = UIKit.Label({ Text = "", Size = UDim2.new(1, -90, 0, 40), Position = UDim2.fromOffset(12, 6), ZIndex = 31, Parent = popup })
	popupTimer = UIKit.Label({ Text = "", Size = UDim2.fromOffset(60, 40), Position = UDim2.new(1, -70, 0, 6), TextColor3 = Theme.Accent, ZIndex = 31, Parent = popup })
	local function respond(accept: boolean)
		popupToken += 1
		TweenService:Create(popup, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -140) }):Play()
		act("Respond", accept)
	end
	UIKit.Button({ Text = "✅ YES", Color = Theme.Green, Size = UDim2.fromOffset(170, 38), Position = UDim2.fromOffset(12, 52), ZIndex = 31, Parent = popup, Callback = function()
		respond(true)
	end })
	UIKit.Button({ Text = "✖ NO", Color = Theme.Red, Size = UDim2.fromOffset(170, 38), Position = UDim2.fromOffset(198, 52), ZIndex = 31, Parent = popup, Callback = function()
		respond(false)
	end })

	Remotes.TradeInvited.OnClientEvent:Connect(function(data)
		popupToken += 1
		local token = popupToken
		popupText.Text = data.FromName .. " wants to trade pets!"
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
				respond(false)
			end
		end)
	end)

	Remotes.TradeUpdate.OnClientEvent:Connect(function(state)
		local wasTrading = Trade.State ~= nil
		Trade.State = state
		if state and not wasTrading then
			-- the popup is gone, the trade begins: pets first
			popupToken += 1
			popup.Position = UDim2.new(0.5, 0, 0, -140)
			Remotes.PetAction:InvokeServer("Refresh")
			C.UI:Open("Trade")
		end
		if C.UI.Current == "Trade" then
			renderTrade()
			updateAccept()
		end
	end)
	-- pets changed (a trade finished, or a pet was sold)
	Remotes.PetUpdate.OnClientEvent:Connect(function()
		if Trade.State and C.UI.Current == "Trade" then
			task.defer(renderTrade)
		end
	end)
	Players.PlayerAdded:Connect(function()
		if not Trade.State and C.UI.Current == "Trade" then
			fillPlayers()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if not Trade.State and C.UI.Current == "Trade" then
				fillPlayers()
			end
		end)
	end)
end

function Trade:Start()
	while true do
		task.wait(0.25)
		if Trade.State and C.UI.Current == "Trade" then
			updateAccept()
		end
	end
end

return Trade
