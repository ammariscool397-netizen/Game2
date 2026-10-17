--[[ HUD - cash counter, income, multiplier/boost info, floor indicator,
	repair alert and the side menu buttons ]]
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
local incomeLabel: TextLabel
local infoLabel: TextLabel
local vaultLabel: TextLabel
local boostLabel: TextLabel
local floorLabel: TextLabel
local repairFrame: Frame
local repairLabel: TextLabel
local menuButtons: { [string]: TextButton } = {}
local moreNames: { [string]: boolean } = {}
local badgeOn: { [string]: boolean } = {}

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
	if target > start * 1.02 then
		local scale = cashLabel:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1.08
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

local function showBadge(name: string, visible: boolean, text: string?)
	local button = menuButtons[name]
	local badge = button and button:FindFirstChild("Badge") :: TextLabel?
	if badge then
		badge.Visible = visible
		badge.Text = text or "!"
	end
end

function HUD:SetBadge(name: string, visible: boolean, text: string?)
	showBadge(name, visible, text)
	if moreNames[name] and name ~= "Secrets" then
		-- a hidden button needs attention: show it on MORE
		badgeOn[name] = visible
		local any = false
		for _, on in badgeOn do
			any = any or on
		end
		showBadge("More", any)
	end
end

function HUD:Init(controllers)
	C = controllers
	local gui = C.UI.Gui

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

	local function line(y: number, color: Color3?)
		return UIKit.Label({
			Text = "",
			Size = UDim2.fromOffset(340, 20),
			Position = UDim2.new(0.5, 0, 0, y),
			AnchorPoint = Vector2.new(0.5, 0),
			Font = Theme.BodyFont,
			TextColor3 = color or Theme.Text,
			Parent = gui,
		})
	end
	incomeLabel = line(76, Color3.fromRGB(140, 255, 160))
	infoLabel = line(97)
	vaultLabel = line(118, Color3.fromRGB(255, 220, 90))
	boostLabel = line(139, Color3.fromRGB(255, 140, 60))

	floorLabel = UIKit.Label({
		Text = "",
		Size = UDim2.fromOffset(220, 26),
		Position = UDim2.new(1, -12, 0, 42),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = gui,
	})

	-- wrecked-items alert (bottom centre)
	repairFrame = UIKit.new("Frame", {
		Size = UDim2.fromOffset(420, 46),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(70, 30, 20),
		Visible = false,
		Parent = gui,
	})
	UIKit.Corner(repairFrame, 12)
	UIKit.Stroke(repairFrame, Color3.fromRGB(255, 120, 60), 2)
	repairLabel = UIKit.Label({ Text = "", Size = UDim2.new(1, -150, 1, -10), Position = UDim2.fromOffset(10, 5), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, Parent = repairFrame })
	UIKit.Button({ Text = "🔧 FIX NOW", Color = Color3.fromRGB(255, 130, 40), Size = UDim2.fromOffset(130, 36), Position = UDim2.new(1, -136, 0, 5), Parent = repairFrame, Callback = function()
		Remotes.BuyProduct:FireServer("InstantRepair")
	end })

	-- side menu (left): the main buttons, and a MORE button that opens the rest
	local menu = UIKit.new("Frame", {
		Name = "Menu",
		Size = UDim2.new(0, 80, 0, 480),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local list = UIKit.new("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = menu,
	})
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	local menuScale = UIKit.new("UIScale", { Parent = menu })

	local morePanel = UIKit.new("Frame", {
		Name = "MorePanel",
		Size = UDim2.fromOffset(170, 440),
		Position = UDim2.new(0, 96, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	UIKit.Corner(morePanel, 16)
	UIKit.Stroke(morePanel, Color3.new(0, 0, 0), 3, 0.1)
	local moreGrid = UIKit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(70, 80),
		CellPadding = UDim2.fromOffset(6, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = morePanel,
	})
	moreGrid.FillDirectionMaxCells = 2
	moreGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	moreGrid.VerticalAlignment = Enum.VerticalAlignment.Center
	local moreScale = UIKit.new("UIScale", { Parent = morePanel })
	local function rescale()
		local vp = workspace.CurrentCamera.ViewportSize
		local scale = math.clamp(vp.Y / 860, 0.55, 1.1)
		menuScale.Scale, moreScale.Scale = scale, scale
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	local main = {
		{ "Shop", "🛒", "SHOP", Color3.fromRGB(255, 180, 0) },
		{ "Build", "🏗️", "BUILD", Color3.fromRGB(255, 140, 40) },
		{ "Rebirth", "🔄", "REBIRTH", Color3.fromRGB(200, 90, 255) },
		{ "Pets", "🐾", "PETS", Color3.fromRGB(255, 150, 200) },
		{ "Daily", "🎁", "DAILY", Color3.fromRGB(255, 90, 120) },
	}
	local more = {
		{ "Duo", "👥", "DUO", Color3.fromRGB(0, 190, 255) },
		{ "Floors", "🛗", "FLOORS", Color3.fromRGB(0, 160, 220) },
		{ "Wheel", "🎰", "WHEEL", Color3.fromRGB(255, 120, 60) },
		{ "Secrets", "🕵️", "SECRETS", Color3.fromRGB(120, 200, 120) },
		{ "Travel", "🧭", "TRAVEL", Color3.fromRGB(60, 200, 190) },
		{ "Shield", "🛡️", "SHIELD", Color3.fromRGB(70, 170, 255) },
		{ "Codes", "🎟️", "CODES", Color3.fromRGB(0, 200, 160) },
		{ "Home", "🏠", "HOME", Color3.fromRGB(70, 200, 100) },
		{ "Settings", "⚙️", "SETTINGS", Color3.fromRGB(130, 140, 160) },
		{ "Admin", "🛡️", "ADMIN", Color3.fromRGB(235, 70, 70) },
	}
	local function setMore(open: boolean)
		morePanel.Visible = open
	end
	local function addButton(parent: Instance, index: number, def, inMore: boolean)
		local name = def[1]
		local button, holder = sideButton(parent, index, def[2], def[3], def[4], function()
			if inMore then
				setMore(false)
			end
			if name == "Home" then
				Remotes.GoHome:FireServer()
			elseif name == "Floors" then
				if C.UI.Current == "Floors" then
					C.UI:Close()
				else
					C.Build:OpenFloors(nil)
				end
			else
				C.UI:Toggle(name)
			end
		end)
		menuButtons[name] = button
		if inMore then
			moreNames[name] = true
		end
		return button, holder
	end
	for i, def in main do
		addButton(menu, i, def, false)
	end
	local moreButton = sideButton(menu, #main + 1, "➕", "MORE", Color3.fromRGB(90, 100, 130), function()
		setMore(not morePanel.Visible)
	end)
	menuButtons.More = moreButton
	for i, def in more do
		local _, holder = addButton(morePanel, i, def, true)
		if def[1] == "Admin" then
			local function show()
				holder.Visible = (player:GetAttribute("AdminRank") or 0) > 0 or (player:GetAttribute("AdminPerms") or "") ~= ""
			end
			show()
			player:GetAttributeChangedSignal("AdminRank"):Connect(show)
			player:GetAttributeChangedSignal("AdminPerms"):Connect(show)
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.G then
			C.UI:Toggle("Shop")
		elseif input.KeyCode == Enum.KeyCode.B then
			C.UI:Toggle("Build")
		elseif input.KeyCode == Enum.KeyCode.R then
			C.UI:Toggle("Rebirth")
		end
	end)
end

local function currentFloor(): string
	local center = player:GetAttribute("PlotCenter")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if typeof(center) ~= "Vector3" or not root then
		return ""
	end
	local d = root.Position - center
	if Vector3.new(d.X, 0, d.Z).Magnitude > 70 then
		return ""
	end
	local floor = math.floor(d.Y / Config.Tycoon.FloorHeight) + 1
	if floor > Config.Tycoon.Floors then
		return "🚁 Roof"
	end
	return "🏢 Floor " .. math.max(floor, 1)
end

function HUD:Refresh()
	local mult = player:GetAttribute("Multiplier") or 1
	local rebirths = player:GetAttribute("WalletRebirths") or player:GetAttribute("Rebirths") or 0
	local rounded = math.floor(mult * 100 + 0.5) / 100
	incomeLabel.Text = "+" .. Util.Money(player:GetAttribute("Income") or 0) .. "/s"
	local friends = math.min(tonumber(player:GetAttribute("FriendsHere")) or 0, Config.Bonuses.MaxFriends)
	local extras = (player:GetAttribute("DuoHost") and "  •  👥 Duo" or "")
		.. ((player:GetAttribute("Pass_AutoBuild") and player:GetAttribute("AutoBuild") ~= false) and "  •  🤖 Auto" or "")
		.. (player.MembershipType == Enum.MembershipType.Premium and ("  •  ⭐+" .. Config.Bonuses.PremiumPercent .. "%") or "")
		.. (friends > 0 and ("  •  👫+" .. friends * Config.Bonuses.FriendPercent .. "%") or "")
	infoLabel.Text = string.format("x%s cash  •  Rebirth %d%s", rounded >= 1000 and Util.Abbreviate(rounded) or tostring(rounded), rebirths, extras)
	local hasAuto = player:GetAttribute("Pass_AutoCollect")
	local vault = player:GetAttribute("Vault") or 0
	vaultLabel.Text = (not hasAuto and vault > 0) and ("🏦 Vault: " .. Util.Money(vault) .. " (step on a vault pad!)") or ""

	local parts = {}
	local now = Util.ServerNow()
	local boostEnd = player:GetAttribute("BoostEnd") or 0
	if boostEnd > now then
		table.insert(parts, "🚀 2x Boost " .. Util.Clock(boostEnd - now))
	end
	local eventMult = workspace:GetAttribute("EventMultiplier") or 1
	local eventEnds = workspace:GetAttribute("EventEnds") or 0
	if eventMult ~= 1 and eventEnds > now then
		table.insert(parts, "🔥 " .. eventMult .. "x Event " .. Util.Clock(eventEnds - now))
	end
	boostLabel.Text = table.concat(parts, "   ")
	floorLabel.Text = currentFloor()

	-- wrecked items
	if C.Build then
		local wrecked, soonest = C.Build:WreckedCount()
		repairFrame.Visible = wrecked > 0
		if wrecked > 0 then
			repairLabel.Text = string.format("🔧 %d upgrades wrecked - rebuilding in %s", wrecked, Util.Clock(math.max(0, soonest)))
		end
	end

	-- badges
	local lastDaily = player:GetAttribute("LastDaily") or 0
	self:SetBadge("Daily", now - lastDaily >= Config.Daily.Cooldown or (player:GetAttribute("WeeklyReady") or 0) > 0)
	local cost = player:GetAttribute("RebirthCost") or math.huge
	self:SetBadge("Rebirth", (player:GetAttribute("Cash") or 0) >= cost and not player:GetAttribute("DuoHost"))
	local found = player:GetAttribute("SecretsFound") or ""
	local count = found == "" and 0 or #string.split(found, ",")
	self:SetBadge("Secrets", count > 0, tostring(count))
end

function HUD:Start()
	if not player:GetAttribute("DataLoaded") then
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	displayedCash = player:GetAttribute("Cash") or 0
	cashLabel.Text = "💵 " .. Util.Money(displayedCash)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		animateCash(player:GetAttribute("Cash") or 0)
	end)
	for _, attr in { "Multiplier", "Rebirths", "Vault", "BoostEnd", "LastDaily", "Pass_AutoCollect", "Income", "SecretsFound" } do
		player:GetAttributeChangedSignal(attr):Connect(function()
			self:Refresh()
		end)
	end
	Util.Try("HUD", self.Refresh, self)
	while true do
		task.wait(0.5)
		Util.Try("HUD", self.Refresh, self)
	end
end

return HUD
