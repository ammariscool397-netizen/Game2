--[[
	Pets (client) - the Pets panel (eggs + your pets) and the pets that float
	behind every player. Which pets a player wears comes from their "Pets"
	attribute, so everyone sees them; the visuals are made locally.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local Theme = UIKit.Theme
local PC = Config.Pets

local Pets = {}
Pets.State = nil :: any
local C

---------------------------------------------------------------------------
-- Floating pets
---------------------------------------------------------------------------
local followers: { [Player]: { Key: string, Parts: { BasePart } } } = {}

local function clearFollowers(target: Player)
	local entry = followers[target]
	if entry then
		for _, part in entry.Parts do
			part:Destroy()
		end
		followers[target] = nil
	end
end

local function makePart(petId: string): BasePart
	local pet = Config.PetById[petId]
	local part = Instance.new("Part")
	part.Name = "Pet_" .. petId
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.one
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(54, 54)
	gui.MaxDistance = 90
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = pet and pet.Icon or "?"
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = pet and PC.Rarities[pet.Rarity].Color or Color3.new(1, 1, 1)
	label.Parent = gui
	part.Parent = workspace
	return part
end

-- make the floating pets match a player's "Pets" attribute
local function refreshFollowers(target: Player)
	local key = tostring(target:GetAttribute("Pets") or "")
	local entry = followers[target]
	if entry and entry.Key == key then
		return
	end
	clearFollowers(target)
	if key == "" then
		return
	end
	local parts = {}
	for id in string.gmatch(key, "[^,]+") do
		table.insert(parts, makePart(id))
	end
	followers[target] = { Key = key, Parts = parts }
end

local function follow(dt: number)
	local now = os.clock()
	for target, entry in followers do
		local character = target.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local count = #entry.Parts
			for i, part in entry.Parts do
				local angle = (i - (count + 1) / 2) * 0.75
				local offset = Vector3.new(math.sin(angle) * 3.4, 1.3 + math.sin(now * 2 + i) * 0.3, 3 + math.cos(angle) * 0.6)
				local goal = root.CFrame * CFrame.new(offset)
				part.CFrame = part.CFrame:Lerp(goal, math.min(1, dt * 7))
			end
		end
	end
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local infoLabel: TextLabel
local eggButtons: { [string]: { Button: TextButton, Cost: TextLabel } } = {}
local grid: ScrollingFrame

local function act(action: string, arg: any?)
	local ok, message = Remotes.PetAction:InvokeServer(action, arg)
	if message and message ~= "" then
		C.Notifications:Toast(tostring(message), ok and "success" or "error")
	end
	return ok
end

local function render()
	local state = Pets.State
	if not state then
		return
	end
	infoLabel.Text = string.format("🐾 %d/%d equipped  •  +%sx income  •  %d pets", #state.Equipped, state.Slots, tostring(state.Bonus), #state.Owned)
	for _, egg in state.Eggs do
		local entry = eggButtons[egg.Id]
		if entry then
			entry.Cost.Text = Util.Money(egg.Cost)
		end
	end
	for _, child in grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local equipped = {}
	for _, uid in state.Equipped do
		equipped[uid] = true
	end
	-- best pets first
	local sorted = table.clone(state.Owned)
	table.sort(sorted, function(a, b)
		local ba, bb = Config.PetBonus(a.Id), Config.PetBonus(b.Id)
		if ba ~= bb then
			return ba > bb
		end
		return a.Uid < b.Uid
	end)
	for order, owned in sorted do
		local pet = Config.PetById[owned.Id]
		local rarity = PC.Rarities[pet.Rarity]
		local card = UIKit.new("Frame", { Name = "Pet" .. owned.Uid, BackgroundColor3 = equipped[owned.Uid] and Color3.fromRGB(40, 70, 45) or Theme.Panel, LayoutOrder = order, ZIndex = 7, Parent = grid })
		UIKit.Corner(card, 10)
		UIKit.Stroke(card, rarity.Color, 2, 0.1)
		UIKit.Label({ Text = pet.Icon, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 4), ZIndex = 8, Parent = card })
		UIKit.Label({ Text = pet.Name, Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 46), Font = Theme.BodyFont, ZIndex = 8, Parent = card })
		UIKit.Label({ Text = pet.Rarity .. " +" .. tostring(rarity.Bonus) .. "x", Size = UDim2.new(1, -8, 0, 14), Position = UDim2.fromOffset(4, 62), Font = Theme.BodyFont, TextColor3 = rarity.Color, Stroke = false, ZIndex = 8, Parent = card })
		UIKit.Button({
			Name = "Equip",
			Text = equipped[owned.Uid] and "UNEQUIP" or "EQUIP",
			Color = equipped[owned.Uid] and Theme.PanelLight or Theme.Green,
			Size = UDim2.new(0.58, -6, 0, 26),
			Position = UDim2.new(0, 4, 1, -30),
			ZIndex = 8,
			Parent = card,
			Callback = function()
				act(equipped[owned.Uid] and "Unequip" or "Equip", owned.Uid)
			end,
		})
		UIKit.Button({
			Name = "Sell",
			Text = "SELL",
			Color = Theme.Red,
			Size = UDim2.new(0.42, -6, 0, 26),
			Position = UDim2.new(0.58, 2, 1, -30),
			ZIndex = 8,
			Parent = card,
			Callback = function()
				act("Sell", owned.Uid)
			end,
		})
	end
end

function Pets:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Pets", "🐾 PETS", Color3.fromRGB(255, 150, 200), 760, 560, function()
		act("Refresh")
	end)
	infoLabel = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 30), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = content })
	-- eggs
	local eggRow = UIKit.new("Frame", { Name = "Eggs", Size = UDim2.new(1, 0, 0, 110), Position = UDim2.fromOffset(0, 34), BackgroundTransparency = 1, ZIndex = 6, Parent = content })
	UIKit.List(eggRow, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	for i, egg in PC.Eggs do
		local frame = UIKit.new("Frame", { Name = "Egg" .. egg.Id, Size = UDim2.new(1 / #PC.Eggs, -6, 1, 0), BackgroundColor3 = Theme.Panel, LayoutOrder = i, ZIndex = 7, Parent = eggRow })
		UIKit.Corner(frame, 10)
		UIKit.Stroke(frame, Theme.Accent, 2, 0.3)
		UIKit.Label({ Text = egg.Icon .. " " .. egg.Name, Size = UDim2.new(1, -8, 0, 26), Position = UDim2.fromOffset(4, 4), ZIndex = 8, Parent = frame })
		local cost = UIKit.Label({ Text = "...", Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 32), Font = Theme.BodyFont, TextColor3 = Color3.fromRGB(150, 255, 160), ZIndex = 8, Parent = frame })
		local odds = {}
		for _, name in PC.RarityOrder do
			if egg.Weights[name] then
				table.insert(odds, name:sub(1, 1) .. egg.Weights[name] .. "%")
			end
		end
		UIKit.Label({ Text = table.concat(odds, " "), Size = UDim2.new(1, -8, 0, 14), Position = UDim2.fromOffset(4, 52), Font = Theme.BodyFont, TextColor3 = Theme.SubText, Stroke = false, ZIndex = 8, Parent = frame })
		local button = UIKit.Button({
			Name = "Hatch" .. egg.Id,
			Text = "HATCH",
			Color = Theme.Accent,
			Size = UDim2.new(1, -16, 0, 30),
			Position = UDim2.new(0, 8, 1, -36),
			ZIndex = 8,
			Parent = frame,
			Callback = function()
				act("Hatch", egg.Id)
			end,
		})
		eggButtons[egg.Id] = { Button = button, Cost = cost }
	end
	UIKit.Button({
		Name = "EquipBest",
		Text = "⭐ EQUIP BEST",
		Color = Theme.Green,
		Size = UDim2.fromOffset(170, 34),
		Position = UDim2.new(1, -170, 0, -2),
		ZIndex = 8,
		Parent = content,
		Callback = function()
			act("EquipBest")
		end,
	})
	grid = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -154), Position = UDim2.fromOffset(0, 152), Parent = content })
	local layout = UIKit.new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 124), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	Remotes.PetUpdate.OnClientEvent:Connect(function(state)
		if type(state) == "table" then
			Pets.State = state
			render()
		end
	end)

	-- floating pets for every player
	local function watch(target: Player)
		target:GetAttributeChangedSignal("Pets"):Connect(function()
			refreshFollowers(target)
		end)
		target.CharacterAdded:Connect(function()
			refreshFollowers(target)
		end)
		refreshFollowers(target)
	end
	for _, target in Players:GetPlayers() do
		watch(target)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(clearFollowers)
	RunService.Heartbeat:Connect(function(dt)
		Util.Try("Pets", follow, dt)
	end)
end

return Pets
