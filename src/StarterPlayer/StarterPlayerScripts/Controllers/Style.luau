--[[ Style (client) - cosmetics: trails, auras and hats. Buy, wear and take off. ]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local ROBUX = utf8.char(0xE002)
local Theme = UIKit.Theme
local CC = Config.Cosmetics

local Style = {}
local C

local grid: ScrollingFrame
local info: TextLabel
local tabButtons: { [string]: TextButton } = {}
local currentKind = CC.Kinds[1].Id
local state

local render

local function act(action: string, arg: string)
	local ok, message = Remotes.CosmeticsAction:InvokeServer(action, arg)
	if message and message ~= "" then
		C.Notifications:Toast(tostring(message), ok and "success" or "error", 3)
	end
	state = Remotes.CosmeticsGet:InvokeServer()
	render()
end

render = function()
	if not state then
		return
	end
	info.Text = string.format("✨ %d / %d collected", state.Count, #CC.List)
	for kind, button in tabButtons do
		button.BackgroundColor3 = kind == currentKind and Theme.Accent or Theme.PanelLight
	end
	UIKit.Clear(grid)
	local order = 0
	for _, cosmetic in CC.List do
		if cosmetic.Kind == currentKind then
			order += 1
			local owned = state.Owned[cosmetic.Id] == true
			local worn = state.Equipped[cosmetic.Kind] == cosmetic.Id
			local card = UIKit.new("Frame", { BackgroundColor3 = Theme.PanelLight, LayoutOrder = order, ZIndex = 7, Parent = grid })
			UIKit.Corner(card, 12)
			UIKit.Stroke(card, worn and Theme.Green or (owned and Theme.Accent2 or Color3.fromRGB(70, 72, 96)), 3)
			UIKit.Label({ Text = cosmetic.Icon, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 6), ZIndex = 8, Parent = card })
			UIKit.Label({ Text = cosmetic.Name, Size = UDim2.new(1, -8, 0, 22), Position = UDim2.fromOffset(4, 64), ZIndex = 8, Parent = card })
			local text, color, callback = "", Theme.Green, nil
			if worn then
				text, color = "WEARING ✓", Theme.Green
				callback = function()
					act("Unequip", cosmetic.Kind)
				end
			elseif owned then
				text, color = "WEAR", Theme.Accent2
				callback = function()
					act("Equip", cosmetic.Id)
				end
			elseif cosmetic.Price then
				text, color = Util.Money(cosmetic.Price), Theme.Green
				callback = function()
					act("Buy", cosmetic.Id)
				end
			elseif cosmetic.Robux then
				text, color = ROBUX .. " " .. cosmetic.Robux, Color3.fromRGB(0, 160, 90)
				callback = function()
					act("Buy", cosmetic.Id)
				end
			else
				text, color = cosmetic.Source == "Season" and "🎫 SEASON" or "🏆 ACHIEVEMENT", Color3.fromRGB(80, 82, 110)
			end
			UIKit.Button({ Text = text, Color = color, Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 1, -42), ZIndex = 9, Parent = card, Callback = function()
				if callback then
					callback()
				end
			end })
		end
	end
end

local function refresh()
	state = Remotes.CosmeticsGet:InvokeServer()
	render()
end

function Style:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Style", "✨ STYLE", Color3.fromRGB(255, 100, 190), 780, 560, refresh)
	local tabs = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 6, Parent = content })
	UIKit.List(tabs, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	for i, kind in CC.Kinds do
		tabButtons[kind.Id] = UIKit.Button({ Text = kind.Icon .. " " .. kind.Name:upper(), Color = Theme.PanelLight, Size = UDim2.new(0.32, 0, 0, 40), LayoutOrder = i, ZIndex = 7, Parent = tabs, Callback = function()
			currentKind = kind.Id
			render()
		end })
	end
	info = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 46), Font = Theme.BodyFont, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = content })
	grid = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -74), Position = UDim2.fromOffset(0, 72), Parent = content })
	local layout = UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(160, 150), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), Parent = grid })
end

return Style
