--[[ Shop - Robux panel with Game Passes and Developer Products ]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme
local ROBUX = utf8.char(0xE002)

local Shop = {}
local C
local openGiftPicker: (string, string, string) -> ()


local function sorted(map)
	local list = {}
	for key, value in map do
		table.insert(list, { Key = key, Data = value })
	end
	table.sort(list, function(a, b)
		return (a.Data.Order or 0) < (b.Data.Order or 0)
	end)
	return list
end

local function card(parent: Instance, order: number, data, isPass: boolean, key: string)
	local accent: Color3 = data.Color or (isPass and Theme.Accent or Theme.Green)
	local frame = UIKit.new("Frame", {
		Name = key,
		BackgroundColor3 = Theme.PanelLight,
		LayoutOrder = order,
		ZIndex = 6,
		Parent = parent,
	})
	UIKit.Corner(frame, 14)
	UIKit.Stroke(frame, accent, 3)
	UIKit.Gradient(frame, Theme.PanelLight, Theme.Panel, 90)

	local icon = UIKit.Label({ Text = data.Icon or "⭐", Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 8), ZIndex = 7, Parent = frame })
	icon:AddTag("UISpin")
	UIKit.Label({ Text = data.Name, Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 70), TextColor3 = accent, ZIndex = 7, Parent = frame })
	UIKit.new("TextLabel", {
		Text = data.Description or "",
		Size = UDim2.new(1, -16, 0, 50),
		Position = UDim2.fromOffset(8, 100),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 14,
		Font = Theme.BodyFont,
		TextColor3 = Theme.SubText,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 7,
		Parent = frame,
	})
	local button = UIKit.Button({
		Text = ROBUX .. " " .. tostring(data.PriceHint or "?"),
		Color = Theme.Green,
		Size = Config.CanGift(isPass and "Pass" or "Product", key) and UDim2.new(1, -84, 0, 42) or UDim2.new(1, -24, 0, 42),
		Position = UDim2.new(0, 12, 1, -52),
		ZIndex = 7,
		Parent = frame,
		Callback = function()
			if isPass then
				if player:GetAttribute("Pass_" .. key) then
					return
				end
				Remotes.BuyPass:FireServer(key)
			else
				Remotes.BuyProduct:FireServer(key)
			end
		end,
	})

	if Config.CanGift(isPass and "Pass" or "Product", key) then
		UIKit.Button({
			Text = "🎁",
			Color = Theme.Purple,
			Size = UDim2.fromOffset(52, 42),
			Position = UDim2.new(1, -64, 1, -52),
			ZIndex = 7,
			Parent = frame,
			Callback = function()
				openGiftPicker(isPass and "Pass" or "Product", key, data.Name)
			end,
		})
	end

	-- real price from Roblox if configured
	if data.Id and data.Id ~= 0 then
		task.spawn(function()
			local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, data.Id, isPass and Enum.InfoType.GamePass or Enum.InfoType.Product)
			if ok and info and info.PriceInRobux then
				button.Text = ROBUX .. " " .. tostring(info.PriceInRobux)
			end
		end)
	end

	if isPass then
		local function refresh()
			if player:GetAttribute("Pass_" .. key) then
				button.Text = "OWNED ✓"
				button.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
			end
		end
		player:GetAttributeChangedSignal("Pass_" .. key):Connect(refresh)
		refresh()
	end
	return frame
end

function Shop:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Shop", "🛒 SHOP", Theme.Accent, 820, 560)

	-- gift picker: choose who gets it (the server checks everything again)
	local picker = UIKit.new("Frame", {
		Name = "GiftPicker",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 30,
		Parent = content,
	})
	UIKit.Corner(picker, 14)
	local pickerTitle = UIKit.Label({ Text = "", Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 8), ZIndex = 31, Parent = picker })
	local pickerList = UIKit.Scroll({ Size = UDim2.new(1, -20, 1, -110), Position = UDim2.fromOffset(10, 50), Parent = picker })
	pickerList.ZIndex = 31
	UIKit.List(pickerList, 6)
	UIKit.Button({ Text = "CANCEL", Color = Theme.Red, Size = UDim2.fromOffset(160, 40), Position = UDim2.new(0.5, 0, 1, -50), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 31, Parent = picker, Callback = function()
		picker.Visible = false
	end })
	openGiftPicker = function(kind: string, key: string, itemName: string)
		pickerTitle.Text = "🎁 Gift " .. itemName .. " to..."
		for _, child in pickerList:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local others = 0
		for _, other in Players:GetPlayers() do
			if other ~= player then
				others += 1
				UIKit.Button({
					Text = other.DisplayName .. "  (@" .. other.Name .. ")",
					Color = Theme.PanelLight,
					Size = UDim2.new(1, -10, 0, 40),
					LayoutOrder = others,
					ZIndex = 32,
					Parent = pickerList,
					Callback = function()
						picker.Visible = false
						Remotes.GiftItem:FireServer(kind, key, other.UserId)
					end,
				})
			end
		end
		if others == 0 then
			UIKit.Label({ Text = "Nobody else is in your server right now.", Size = UDim2.new(1, -10, 0, 40), Font = Theme.BodyFont, TextColor3 = Theme.SubText, ZIndex = 32, Parent = pickerList })
		end
		picker.Visible = true
	end

	local tabs = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 6, Parent = content })
	UIKit.List(tabs, 10, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center)

	local pages = {}
	local function makePage(name)
		local scroll = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -54), Position = UDim2.fromOffset(0, 54), Parent = content })
		scroll.Name = name
		scroll.Visible = false
		UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 6), Parent = scroll })
		local grid = UIKit.new("UIGridLayout", {
			CellSize = UDim2.new(0.315, 0, 0, 220),
			CellPadding = UDim2.new(0.02, 0, 0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroll,
		})
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		pages[name] = scroll
		return scroll
	end
	local passPage = makePage("Passes")
	local productPage = makePage("Products")

	local tabButtons = {}
	local function select(name)
		for pageName, page in pages do
			page.Visible = pageName == name
			tabButtons[pageName].BackgroundColor3 = pageName == name and Theme.Accent or Theme.PanelLight
		end
	end
	tabButtons.Passes = UIKit.Button({ Text = "👑 GAME PASSES", Color = Theme.Accent, Size = UDim2.fromOffset(200, 40), ZIndex = 7, Parent = tabs, Callback = function()
		select("Passes")
	end })
	tabButtons.Products = UIKit.Button({ Text = "💰 CASH & BOOSTS", Color = Theme.PanelLight, Size = UDim2.fromOffset(200, 40), ZIndex = 7, Parent = tabs, Callback = function()
		select("Products")
	end })

	-- in Studio everything shows (purchases are simulated); in a live game only
	-- the items whose ids are set up on the Creator Dashboard
	local showAll = RunService:IsStudio() and Config.Monetization.SimulateUnconfiguredInStudio
	local function fill(page, map, isPass: boolean)
		local shown = 0
		for _, entry in sorted(map) do
			if showAll or (entry.Data.Id or 0) ~= 0 then
				shown += 1
				card(page, shown, entry.Data, isPass, entry.Key)
			end
		end
		if shown == 0 then
			UIKit.Label({ Text = "Coming soon! 🛠️", Size = UDim2.new(1, 0, 0, 40), Font = Theme.BodyFont, TextColor3 = Theme.SubText, ZIndex = 7, Parent = page })
		end
	end
	fill(passPage, Config.GamePasses, true)
	fill(productPage, Config.Products, false)
	select("Passes")
end

return Shop
