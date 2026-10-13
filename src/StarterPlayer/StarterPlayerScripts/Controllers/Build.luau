--[[
	Build (client) - keeps a live copy of your tower's state and draws:
	  • the BUILD menu: every upgrade by floor, with BUY / BUY ALL
	  • the FLOORS menu (elevator): teleport to any built floor
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)
local TycoonItems = require(Shared.TycoonItems)

local player = Players.LocalPlayer
local Theme = UIKit.Theme
local FLOORS = Config.Tycoon.Floors

local Build = {}
Build.State = { Plot = nil, Purchased = {}, Disabled = {}, Secrets = {}, IsOwner = true }
Build.Listeners = {}
local C

local ICONS = {
	Unlock = "🏢", Dropper = "⬇️", Mk2 = "⏫", Upgrader = "✨", Generator = "⚙️", Conveyor = "➡️",
	Boost = "🚀", Decor = "🪴", Wall = "🧱", Special = "⭐", Trophy = "🏆", Roof = "🚁", Secret = "🕵️",
}

local selectedFloor = 1
local listFrame: ScrollingFrame
local headerLabel: TextLabel
local floorButtons = {}
local rows = {}
local gains = {}
local floorsGrid: Frame
local floorsTitle: TextLabel
local floorsPlot: number? = nil

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local function notify()
	for _, fn in Build.Listeners do
		task.spawn(fn)
	end
end

function Build:OnChanged(fn)
	table.insert(self.Listeners, fn)
end

function Build:Refetch()
	local ok, state = pcall(function()
		return Remotes.GetTycoonState:InvokeServer()
	end)
	if ok and type(state) == "table" then
		local disabled = {}
		for id, seconds in state.Disabled or {} do
			disabled[id] = os.clock() + seconds
		end
		self.State = {
			Plot = state.Plot,
			Purchased = state.Purchased or {},
			Disabled = disabled,
			Secrets = state.Secrets or {},
			IsOwner = state.IsOwner ~= false,
			OwnerName = state.OwnerName,
		}
		notify()
	end
end

function Build:WreckedCount(): (number, number)
	local n, soonest = 0, math.huge
	for _, untilTime in self.State.Disabled do
		n += 1
		soonest = math.min(soonest, untilTime - os.clock())
	end
	return n, soonest
end

function Build:BoughtCount(): number
	local n = 0
	for id in self.State.Purchased do
		local item = TycoonItems.ById[id]
		if item and item.Kind ~= "Secret" then
			n += 1
		end
	end
	return n
end

local function incomeNow(): number
	local disabled = {}
	for id in Build.State.Disabled do
		disabled[id] = true
	end
	return (TycoonItems.ComputeIncome(Build.State.Purchased, disabled, Build.State.Secrets, player:GetAttribute("Pass_FastDroppers") == true))
end

-- $/s each currently-available item would add (with your multipliers)
local function computeGains()
	gains = {}
	local base = incomeNow()
	local mult = player:GetAttribute("Multiplier") or 1
	for _, item in TycoonItems.List do
		if TycoonItems.IsAvailable(item, Build.State.Purchased) then
			local copy = table.clone(Build.State.Purchased)
			copy[item.Id] = true
			local after = TycoonItems.ComputeIncome(copy, nil, Build.State.Secrets, player:GetAttribute("Pass_FastDroppers") == true)
			gains[item.Id] = math.max(0, after - base) * mult
		end
	end
end

local function pct(x: number): string
	return tostring(math.floor(x * 100 + 0.5)) .. "%"
end

-- (numbers come from TycoonItems so the text always matches the real math)
local function describe(item): string
	local kind = item.Kind
	if kind == "Dropper" then
		return "A dropper on floor " .. item.Floor
	elseif kind == "Mk2" then
		return "Doubles its dropper"
	elseif kind == "Upgrader" then
		return "x" .. item.Multiplier .. " to all drops on this floor"
	elseif kind == "Generator" then
		return "Passive cash machine"
	elseif kind == "Conveyor" then
		return "+" .. pct(TycoonItems.ConveyorBonus) .. " drop income on this floor"
	elseif kind == "Boost" then
		return "x" .. item.Multiplier .. " everything on this floor"
	elseif kind == "Decor" then
		return "+" .. pct(TycoonItems.DecorBonus) .. " income on this floor"
	elseif kind == "Wall" then
		return "+" .. pct(TycoonItems.WallBonus) .. " income on this floor"
	elseif kind == "Unlock" then
		return item.Floor == 1 and "Your starting base" or "Opens a whole new floor!"
	elseif kind == "Special" then
		local bonus = pct(item.Bonus or TycoonItems.SpecialBonus)
		if item.Effect == "Bunker" then
			return "Nuke-proof bunker + " .. bonus .. " ALL income"
		elseif item.Effect == "Shield" then
			return "Protects your tower from ALL disasters + " .. bonus
		end
		return "+" .. bonus .. " ALL income"
	elseif kind == "Trophy" or kind == "Roof" then
		return "+" .. pct(item.Bonus or 0) .. " ALL income"
	end
	return ""
end

---------------------------------------------------------------------------
-- BUILD menu
---------------------------------------------------------------------------
local function isFloorUnlocked(floor: number): boolean
	if floor == FLOORS + 1 then
		return Build.State.Purchased["Roof_1"] == true
	end
	return Build.State.Purchased[TycoonItems.FloorUnlockId(floor)] == true
end
Build.IsFloorUnlocked = isFloorUnlocked

local function floorLabel(floor: number): string
	if floor == FLOORS + 1 then
		return "🚁 Roof"
	end
	return "F" .. floor .. " " .. TycoonItems.Themes[floor].Name
end

local function updateHeader()
	local mult = player:GetAttribute("Multiplier") or 1
	headerLabel.Text = string.format("Upgrades %d/%d   •   Income %s/s", Build:BoughtCount(), TycoonItems.BuyableCount, Util.Money(incomeNow() * mult))
	for floor, button in floorButtons do
		local items = TycoonItems.ByFloor[floor]
		local owned = 0
		for _, item in items do
			if Build.State.Purchased[item.Id] then
				owned += 1
			end
		end
		local unlocked = isFloorUnlocked(floor)
		local available = false
		for _, item in items do
			if TycoonItems.IsAvailable(item, Build.State.Purchased) then
				available = true
			end
		end
		button.Text = (unlocked and "" or (available and "🆕 " or "🔒 ")) .. floorLabel(floor) .. "  " .. owned .. "/" .. #items
		button.BackgroundColor3 = floor == selectedFloor and Theme.Accent or (unlocked and Theme.PanelLight or Theme.Background)
	end
end

local function updateRows()
	local cash = player:GetAttribute("Cash") or 0
	for id, row in rows do
		local item = TycoonItems.ById[id]
		local owned = Build.State.Purchased[id]
		local wrecked = Build.State.Disabled[id]
		local available = TycoonItems.IsAvailable(item, Build.State.Purchased)
		local button = row.Button
		if wrecked then
			button.Text = "🔧 " .. Util.Clock(math.max(0, wrecked - os.clock()))
			button.BackgroundColor3 = Color3.fromRGB(200, 90, 40)
		elseif owned then
			button.Text = "OWNED ✓"
			button.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
		elseif available then
			button.Text = Util.Money(item.Cost)
			button.BackgroundColor3 = cash >= item.Cost and Theme.Green or Theme.Red
		else
			button.Text = "🔒 " .. Util.Money(item.Cost)
			button.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
		end
		local gain = gains[id]
		row.Desc.Text = describe(item) .. ((gain and gain > 0) and ("  (+" .. Util.Money(gain) .. "/s)") or "")
		row.Frame.BackgroundColor3 = available and Color3.fromRGB(50, 56, 84) or Theme.Panel
	end
end

local function buildRows()
	for _, row in rows do
		row.Frame:Destroy()
	end
	rows = {}
	local items = TycoonItems.ByFloor[selectedFloor] or {}
	for i, item in items do
		local frame = UIKit.new("Frame", { Size = UDim2.new(1, -10, 0, 50), BackgroundColor3 = Theme.Panel, LayoutOrder = i, ZIndex = 7, Parent = listFrame })
		UIKit.Corner(frame, 8)
		UIKit.Label({ Text = ICONS[item.Kind] or "•", Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(6, 7), ZIndex = 8, Parent = frame })
		UIKit.Label({ Text = item.Name, Size = UDim2.new(1, -220, 0, 24), Position = UDim2.fromOffset(48, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = frame })
		local desc = UIKit.Label({ Text = "", Size = UDim2.new(1, -220, 0, 16), Position = UDim2.fromOffset(48, 29), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, TextColor3 = Theme.SubText, Stroke = false, ZIndex = 8, Parent = frame })
		local button = UIKit.Button({
			Text = "",
			Color = Theme.Green,
			Size = UDim2.fromOffset(150, 38),
			Position = UDim2.new(1, -158, 0, 6),
			ZIndex = 8,
			Parent = frame,
			Callback = function()
				if Build.State.Purchased[item.Id] then
					return
				end
				local ok, message = Remotes.BuyItem:InvokeServer(item.Id)
				C.Notifications:Toast(message, ok and "success" or "error", 2.5)
			end,
		})
		rows[item.Id] = { Frame = frame, Button = button, Desc = desc }
	end
	updateRows()
end

local function selectFloor(floor: number)
	selectedFloor = floor
	buildRows()
	updateHeader()
end

local function refreshAll()
	computeGains()
	updateHeader()
	updateRows()
end

local function buildPanel()
	local _, content = C.UI:MakePanel("Build", "🏗️ BUILD", Color3.fromRGB(255, 150, 40), 940, 600, function()
		-- default to the highest floor with something to buy
		local best = 1
		for floor = 1, FLOORS + 1 do
			for _, item in TycoonItems.ByFloor[floor] do
				if TycoonItems.IsAvailable(item, Build.State.Purchased) then
					best = floor
					break
				end
			end
		end
		selectFloor(best)
		refreshAll()
	end)

	headerLabel = UIKit.Label({ Text = "", Size = UDim2.new(1, -420, 0, 30), Position = UDim2.fromOffset(4, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = content })
	UIKit.Button({ Text = "BUY ALL (FLOOR)", Color = Theme.Accent2, Size = UDim2.fromOffset(190, 38), Position = UDim2.new(1, -400, 0, 0), ZIndex = 7, Parent = content, Callback = function()
		Remotes.BuyAll:FireServer(selectedFloor)
	end })
	UIKit.Button({ Text = "⚡ BUY ALL", Color = Theme.Green, Size = UDim2.fromOffset(200, 38), Position = UDim2.new(1, -200, 0, 0), ZIndex = 7, Parent = content, Callback = function()
		Remotes.BuyAll:FireServer(nil)
	end })

	local tabs = UIKit.Scroll({ Size = UDim2.new(0, 230, 1, -50), Position = UDim2.fromOffset(0, 48), Parent = content })
	UIKit.List(tabs, 6)
	for floor = 1, FLOORS + 1 do
		floorButtons[floor] = UIKit.Button({
			Text = floorLabel(floor),
			Color = Theme.PanelLight,
			Size = UDim2.new(1, -12, 0, 40),
			LayoutOrder = floor,
			ZIndex = 7,
			Parent = tabs,
			Callback = function()
				selectFloor(floor)
			end,
		})
		floorButtons[floor].TextXAlignment = Enum.TextXAlignment.Left
	end
	listFrame = UIKit.Scroll({ Size = UDim2.new(1, -240, 1, -50), Position = UDim2.fromOffset(240, 48), Parent = content })
	UIKit.List(listFrame, 6)
	UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6), Parent = listFrame })
end

---------------------------------------------------------------------------
-- FLOORS menu (elevator)
---------------------------------------------------------------------------
local function fillFloors()
	for _, child in floorsGrid:GetChildren() do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	local own = floorsPlot == Build.State.Plot
	floorsTitle.Text = own and "Your tower - pick a floor" or "Visiting tower #" .. tostring(floorsPlot)
	for floor = 1, FLOORS + 1 do
		local unlocked = true
		if own then
			unlocked = isFloorUnlocked(floor)
		end
		local theme = TycoonItems.Themes[math.min(floor, FLOORS)]
		local button = UIKit.Button({
			Text = (unlocked and "" or "🔒 ") .. (floor == FLOORS + 1 and "🚁 ROOF" or ("FLOOR " .. floor .. "\n" .. theme.Name)),
			Color = unlocked and theme.Accent or Color3.fromRGB(70, 70, 85),
			Size = UDim2.fromOffset(150, 70),
			LayoutOrder = floor,
			ZIndex = 7,
			Parent = floorsGrid,
			Callback = function()
				if floorsPlot then
					Remotes.TeleportFloor:FireServer(floorsPlot, floor)
					C.UI:Close()
				end
			end,
		})
		button.Name = "Floor" .. floor
	end
end

local function buildFloors()
	local _, content = C.UI:MakePanel("Floors", "🛗 ELEVATOR", Color3.fromRGB(0, 190, 255), 560, 420, function()
		fillFloors()
	end)
	floorsTitle = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 28), Font = Theme.BodyFont, ZIndex = 7, Parent = content })
	floorsGrid = UIKit.new("Frame", { Size = UDim2.new(1, 0, 1, -36), Position = UDim2.fromOffset(0, 36), BackgroundTransparency = 1, ZIndex = 6, Parent = content })
	local grid = UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 70), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = floorsGrid })
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
end

function Build:OpenFloors(plotIndex: number?)
	floorsPlot = plotIndex or self.State.Plot
	if not floorsPlot then
		C.Notifications:Toast("You don't have a tower yet!", "error")
		return
	end
	C.UI:Open("Floors")
end

---------------------------------------------------------------------------
function Build:Init(controllers)
	C = controllers
	buildPanel()
	buildFloors()

	Remotes.TycoonUpdate.OnClientEvent:Connect(function(update)
		local kind = update.Type
		if kind == "Reset" then
			self:Refetch()
			return
		elseif kind == "Bought" then
			self.State.Purchased[update.Id] = true
		elseif kind == "Disabled" then
			self.State.Disabled[update.Id] = os.clock() + (update.Seconds or 0)
		elseif kind == "Repaired" then
			self.State.Disabled[update.Id] = nil
		elseif kind == "Secret" then
			self.State.Secrets[update.Id] = true
		end
		notify()
	end)

	Remotes.ClientCommand.OnClientEvent:Connect(function(command, value)
		if command == "openfloors" then
			self:OpenFloors(value)
		end
	end)

	local pending = false
	local function scheduleRefresh()
		if pending then
			return
		end
		pending = true
		task.delay(0.4, function()
			pending = false
			if C.UI.Current == "Build" then
				refreshAll()
			end
		end)
	end
	self:OnChanged(function()
		if C.UI.Current == "Build" then
			refreshAll()
		elseif C.UI.Current == "Floors" then
			fillFloors()
		end
	end)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if C.UI.Current == "Build" then
			updateRows()
		end
	end)
	player:GetAttributeChangedSignal("Multiplier"):Connect(scheduleRefresh)
end

function Build:Start()
	if not player:GetAttribute("DataLoaded") then
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	task.wait(1)
	self:Refetch()
	-- countdown timers on wrecked items
	local function tick()
		if C.UI.Current == "Build" and next(self.State.Disabled) then
			updateRows()
		end
		-- drop expired entries (server sends "Repaired" too; this is a safety net)
		for id, untilTime in self.State.Disabled do
			if os.clock() > untilTime + 5 then
				self.State.Disabled[id] = nil
			end
		end
	end
	while true do
		task.wait(1)
		Util.Try("Build", tick)
	end
end

return Build
