--[[ HUD - cash counter, multiplier/boost info and the side menu buttons ]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local HUD = {}
HUD.CashFrame = nil :: Frame?
local C

local displayedCash = 0
local cashLabel: TextLabel
local infoLabel: TextLabel
local vaultLabel: TextLabel
local boostLabel: TextLabel
local menuButtons: { [string]: TextButton } = {}

local animVersion = 0
local function animateCash(target: number)
	animVersion += 1
	local myVersion = animVersion
	local start = displayedCash
	local startTime = os.clock()
	local duration = 0.35
	task.spawn(function()
		while myVersion == animVersion do
			local alpha = math.min((os.clock() - startTime) / duration, 1)
			displayedCash = start + (target - start) * alpha
			cashLabel.Text = "💵 " .. Util.Money(displayedCash)
			if alpha >= 1 then
				break
			end
			task.wait()
		end
	end)
	if target > start then
		local scale = cashLabel:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1.12
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end
end

local function sideButton(parent: Instance, order: number, icon: string, text: string, color: Color3, callback: () -> ())
	local holder = UIKit.new("Frame", { Size = UDim2.fromOffset(70, 78), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	local button = UIKit.Button({
		Text = icon,
		Color = color,
		Size = UDim2.fromOffset(62, 58),
		Position = UDim2.fromOffset(4, 0),
		Radius = 14,
		Parent = holder,
		Callback = callback,
	})
	UIKit.Label({ Text = text, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0, 60), Parent = holder })
	local badge = UIKit.new("TextLabel", {
		Name = "Badge",
		Size = UDim2.fromOffset(22, 22),
		Position = UDim2.new(1, -18, 0, -6),
		BackgroundColor3 = Theme.Red,
		Text = "!",
		TextScaled = true,
		Font = Theme.Font,
		TextColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 3,
		Parent = button,
	})
	UIKit.Corner(badge, 11)
	return button, holder
end

function HUD:SetBadge(name: string, visible: boolean)
	local button = menuButtons[name]
	if button then
		local badge = button:FindFirstChild("Badge") :: TextLabel?
		if badge then
			badge.Visible = visible
		end
	end
end

function HUD:Init(controllers)
	C = controllers
	local gui = C.UI.Gui

	-- cash display (top centre)
	local cashFrame = UIKit.new("Frame", {
		Name = "Cash",
		Size = UDim2.fromOffset(300, 64),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Theme.Panel,
		Parent = gui,
	})
	UIKit.Corner(cashFrame, 16)
	UIKit.Stroke(cashFrame, Color3.new(0, 0, 0), 3, 0.1)
	UIKit.Gradient(cashFrame, Color3.fromRGB(60, 200, 100), Color3.fromRGB(30, 140, 70), 90)
	self.CashFrame = cashFrame
	cashLabel = UIKit.Label({ Text = "💵 $0", Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6), Parent = cashFrame })
	UIKit.new("UIScale", { Parent = cashLabel })

	infoLabel = UIKit.Label({
		Text = "x1 cash • Rebirth 0",
		Size = UDim2.fromOffset(300, 22),
		Position = UDim2.new(0.5, 0, 0, 78),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.BodyFont,
		Parent = gui,
	})
	vaultLabel = UIKit.Label({
		Text = "",
		Size = UDim2.fromOffset(300, 20),
		Position = UDim2.new(0.5, 0, 0, 100),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.BodyFont,
		TextColor3 = Color3.fromRGB(255, 220, 90),
		Parent = gui,
	})
	boostLabel = UIKit.Label({
		Text = "",
		Size = UDim2.fromOffset(300, 20),
		Position = UDim2.new(0.5, 0, 0, 122),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.BodyFont,
		TextColor3 = Color3.fromRGB(255, 140, 60),
		Parent = gui,
	})

	-- side menu (left)
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		Size = UDim2.new(0, 160, 0, 340),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local grid = UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(70, 80),
		CellPadding = UDim2.fromOffset(6, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = menu,
	})
	grid.FillDirectionMaxCells = 2
	local menuScale = UIKit.new("UIScale", { Parent = menu })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		menuScale.Scale = math.clamp(vp.Y / 800, 0.6, 1.1)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	local buttons = {
		{ "Shop", "🛒", "SHOP", Color3.fromRGB(255, 180, 0) },
		{ "Rebirth", "🔄", "REBIRTH", Color3.fromRGB(200, 90, 255) },
		{ "Daily", "🎁", "DAILY", Color3.fromRGB(255, 90, 120) },
		{ "Codes", "🎟️", "CODES", Color3.fromRGB(0, 190, 255) },
		{ "Settings", "⚙️", "SETTINGS", Color3.fromRGB(130, 140, 160) },
		{ "Home", "🏠", "HOME", Color3.fromRGB(70, 200, 100) },
		{ "Admin", "🛡️", "ADMIN", Color3.fromRGB(235, 70, 70) },
	}
	for i, def in buttons do
		local name = def[1]
		local button, holder = sideButton(menu, i, def[2], def[3], def[4], function()
			if name == "Home" then
				Remotes.GoHome:FireServer()
			else
				C.UI:Toggle(name)
			end
		end)
		menuButtons[name] = button
		if name == "Admin" then
			holder.Visible = (player:GetAttribute("AdminRank") or 0) > 0
			player:GetAttributeChangedSignal("AdminRank"):Connect(function()
				holder.Visible = (player:GetAttribute("AdminRank") or 0) > 0
			end)
		end
	end

	-- keyboard shortcuts
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			C.UI:Toggle("Shop")
		elseif input.KeyCode == Enum.KeyCode.R then
			C.UI:Toggle("Rebirth")
		end
	end)
end

function HUD:Refresh()
	local mult = player:GetAttribute("Multiplier") or 1
	local rebirths = player:GetAttribute("Rebirths") or 0
	local rounded = math.floor(mult * 100 + 0.5) / 100
	infoLabel.Text = string.format("x%s cash  •  Rebirth %d", rounded >= 1000 and Util.Abbreviate(rounded) or tostring(rounded), rebirths)
	local hasAuto = player:GetAttribute("Pass_AutoCollect")
	local vault = player:GetAttribute("Vault") or 0
	vaultLabel.Text = (not hasAuto and vault > 0) and ("🏦 Vault: " .. Util.Money(vault) .. " (step on the pad!)") or ""

	local parts = {}
	local boostEnd = player:GetAttribute("BoostEnd") or 0
	if boostEnd > os.time() then
		table.insert(parts, "🚀 2x Boost " .. Util.Clock(boostEnd - os.time()))
	end
	local eventMult = workspace:GetAttribute("EventMultiplier") or 1
	local eventEnds = workspace:GetAttribute("EventEnds") or 0
	if eventMult ~= 1 and eventEnds > os.time() then
		table.insert(parts, "🔥 " .. eventMult .. "x Event " .. Util.Clock(eventEnds - os.time()))
	end
	boostLabel.Text = table.concat(parts, "   ")

	-- badges
	local lastDaily = player:GetAttribute("LastDaily") or 0
	self:SetBadge("Daily", os.time() - lastDaily >= Config.Daily.Cooldown)
	local cost = player:GetAttribute("RebirthCost") or math.huge
	self:SetBadge("Rebirth", (player:GetAttribute("Cash") or 0) >= cost)
end

function HUD:Start()
	if not player:GetAttribute("DataLoaded") then
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	displayedCash = player:GetAttribute("Cash") or 0
	cashLabel.Text = "💵 " .. Util.Money(displayedCash)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		animateCash(player:GetAttribute("Cash") or 0)
		self:Refresh()
	end)
	for _, attr in { "Multiplier", "Rebirths", "Vault", "BoostEnd", "LastDaily", "Pass_AutoCollect" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			self:Refresh()
		end)
	end
	self:Refresh()
	while true do
		task.wait(1)
		self:Refresh()
	end
end

return HUD
