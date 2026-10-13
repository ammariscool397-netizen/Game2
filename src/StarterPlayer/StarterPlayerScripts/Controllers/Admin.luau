--[[
	Admin (client) - Admin Panel UI + client-side admin effects
	(fly, noclip, spectate). Opens with the 🛡️ button or F2.
	Chat commands (";speed me 50") are routed through here too.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local Remotes = require(Shared.Remotes)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Admin = {}
local C

local commandBox: TextBox
local resultLabel: TextLabel
local pages = {}
local tabButtons = {}
local currentTab = "Commands"

---------------------------------------------------------------------------
-- Fly / noclip / view
---------------------------------------------------------------------------
local flying = false
local flyParts = {}
local flyConn: RBXScriptConnection?
local noclipConn: RBXScriptConnection?

local function stopFly()
	flying = false
	if flyConn then
		flyConn:Disconnect()
		flyConn = nil
	end
	for _, inst in flyParts do
		inst:Destroy()
	end
	flyParts = {}
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function startFly()
	stopFly()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	flying = true
	local attachment = Instance.new("Attachment")
	attachment.Name = "FlyAttachment"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.MaxForce = math.huge
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.MaxTorque = math.huge
	align.Responsiveness = 40
	align.Parent = root
	flyParts = { attachment, velocity, align }
	humanoid.PlatformStand = true

	flyConn = RunService.RenderStepped:Connect(function()
		if not root.Parent then
			stopFly()
			return
		end
		local cam = workspace.CurrentCamera
		local move = humanoid.MoveDirection
		local vertical = 0
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
			vertical += 1
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
			vertical -= 1
		end
		-- fly where the camera looks when moving forward
		local look = cam.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude > 0 and move.Magnitude > 0 then
			local forwardAmount = move:Dot(flatLook.Unit)
			move += Vector3.new(0, look.Y * forwardAmount, 0)
		end
		local speed = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 160 or 70
		velocity.VectorVelocity = (move + Vector3.new(0, vertical, 0)) * speed
		align.CFrame = cam.CFrame.Rotation
	end)
end

local function setNoclip(enabled: boolean)
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	if enabled then
		noclipConn = RunService.Stepped:Connect(function()
			local character = player.Character
			if character then
				for _, part in character:GetDescendants() do
					if part:IsA("BasePart") then
						part.CanCollide = false
					end
				end
			end
		end)
	end
end

local function view(target: Player?)
	local cam = workspace.CurrentCamera
	local character = (target or player).Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		cam.CameraSubject = humanoid
	end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function run(text: string)
	if text == "" then
		return
	end
	local ok, message = Remotes.AdminCommand:InvokeServer(text)
	if resultLabel then
		resultLabel.Text = tostring(message)
		resultLabel.TextColor3 = ok and Theme.Green or Theme.Red
	end
	C.Notifications:Toast(tostring(message), ok and "success" or "error", 3)
	return ok
end

local function clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function rowFrame(parent: Instance, order: number, height: number?)
	local frame = UIKit.new("Frame", {
		Size = UDim2.new(1, -10, 0, height or 46),
		BackgroundColor3 = order % 2 == 0 and Theme.PanelLight or Theme.Panel,
		LayoutOrder = order,
		ZIndex = 7,
		Parent = parent,
	})
	UIKit.Corner(frame, 8)
	return frame
end

local function smallButton(parent: Instance, text: string, color: Color3, x: number, width: number, callback: () -> ())
	return UIKit.Button({
		Text = text,
		Color = color,
		Size = UDim2.fromOffset(width, 32),
		Position = UDim2.new(1, x, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 8,
		Parent = parent,
		Callback = callback,
	})
end

local function fillCommands()
	local page = pages.Commands
	clear(page)
	local list = Remotes.AdminData:InvokeServer("commands")
	if not list then
		return
	end
	table.sort(list, function(a, b)
		if a.Rank ~= b.Rank then
			return a.Rank < b.Rank
		end
		return a.Name < b.Name
	end)
	for i, cmd in list do
		local frame = rowFrame(page, i, 50)
		local rankColor = ({ Theme.Accent2, Theme.Green, Theme.Accent, Theme.Red })[cmd.Rank] or Theme.SubText
		local badge = UIKit.Label({ Text = Config.RankNames[cmd.Rank] or "?", Size = UDim2.fromOffset(84, 20), Position = UDim2.fromOffset(8, 15), TextColor3 = rankColor, Font = Theme.BodyFont, ZIndex = 8, Parent = frame })
		badge.TextXAlignment = Enum.TextXAlignment.Left
		UIKit.Label({
			Text = Config.Admin.Prefix .. cmd.Name .. " " .. (cmd.Args or ""),
			Size = UDim2.new(0.42, -90, 0, 22),
			Position = UDim2.fromOffset(96, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = cmd.Allowed and Theme.Text or Theme.SubText,
			ZIndex = 8,
			Parent = frame,
		})
		local aliases = (#cmd.Aliases > 0) and ("aliases: " .. table.concat(cmd.Aliases, ", ")) or ""
		UIKit.Label({
			Text = aliases,
			Size = UDim2.new(0.42, -90, 0, 16),
			Position = UDim2.fromOffset(96, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.SubText,
			Font = Theme.BodyFont,
			Stroke = false,
			ZIndex = 8,
			Parent = frame,
		})
		UIKit.Label({
			Text = cmd.Desc,
			Size = UDim2.new(0.58, -90, 0, 30),
			Position = UDim2.new(0.42, 6, 0, 10),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.BodyFont,
			TextColor3 = Theme.SubText,
			Stroke = false,
			ZIndex = 8,
			Parent = frame,
		})
		if cmd.Allowed then
			smallButton(frame, "USE", Theme.Accent, -76, 66, function()
				commandBox.Text = cmd.Name .. " "
				commandBox:CaptureFocus()
				commandBox.CursorPosition = #commandBox.Text + 1
			end)
		end
	end
end

local function fillPlayers()
	local page = pages.Players
	clear(page)
	local list = Remotes.AdminData:InvokeServer("players")
	if not list then
		return
	end
	for i, info in list do
		local frame = rowFrame(page, i, 56)
		UIKit.Label({
			Text = info.DisplayName .. "  (@" .. info.Name .. ")",
			Size = UDim2.new(0.4, 0, 0, 24),
			Position = UDim2.fromOffset(10, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 8,
			Parent = frame,
		})
		UIKit.Label({
			Text = (Config.RankNames[info.Rank] or "Player") .. " • " .. Util.Money(info.Cash) .. " • R" .. info.Rebirths,
			Size = UDim2.new(0.4, 0, 0, 18),
			Position = UDim2.fromOffset(10, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.BodyFont,
			TextColor3 = Theme.SubText,
			Stroke = false,
			ZIndex = 8,
			Parent = frame,
		})
		local name = info.Name
		local actions = {
			{ "TO", Theme.Accent2, "to " .. name },
			{ "BRING", Theme.Accent2, "bring " .. name },
			{ "VIEW", Theme.Purple, "view " .. name },
			{ "+1M", Theme.Green, "givecash " .. name .. " 1m" },
			{ "FREEZE", Color3.fromRGB(120, 200, 255), "freeze " .. name },
			{ "KILL", Theme.Red, "kill " .. name },
			{ "KICK", Color3.fromRGB(150, 30, 30), "kick " .. name },
		}
		local x = -8
		for j = #actions, 1, -1 do
			local action = actions[j]
			x -= 62
			smallButton(frame, action[1], action[2], x, 58, function()
				run(action[3])
				if action[1] == "KICK" then
					task.wait(0.5)
					fillPlayers()
				end
			end)
		end
	end
end

local function fillLogs()
	local page = pages.Logs
	clear(page)
	local logs = Remotes.AdminData:InvokeServer("logs") or {}
	if #logs == 0 then
		UIKit.Label({ Text = "No commands run yet.", Size = UDim2.new(1, 0, 0, 30), Font = Theme.BodyFont, ZIndex = 8, Parent = page })
	end
	for i, entry in logs do
		local frame = rowFrame(page, i, 34)
		UIKit.Label({
			Text = os.date("%H:%M:%S", entry.Time) .. "  " .. entry.By .. ":  " .. entry.Text,
			Size = UDim2.new(1, -20, 1, -10),
			Position = UDim2.fromOffset(10, 5),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.BodyFont,
			Stroke = false,
			ZIndex = 8,
			Parent = frame,
		})
	end
end

local function buildServerPage()
	local page = pages.Server
	local order = 0
	local function section(title: string)
		order += 1
		UIKit.Label({ Text = title, Size = UDim2.new(1, -10, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Accent, LayoutOrder = order, ZIndex = 8, Parent = page })
	end
	local function buttonRow(buttons)
		order += 1
		local frame = UIKit.new("Frame", { Size = UDim2.new(1, -10, 0, 44), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 7, Parent = page })
		UIKit.List(frame, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
		for _, def in buttons do
			UIKit.Button({ Text = def[1], Color = def[2], Size = UDim2.fromOffset(def[4] or 150, 40), ZIndex = 8, Parent = frame, Callback = function()
				run(def[3])
			end })
		end
	end
	local function inputRow(placeholder: string, buttonText: string, color: Color3, build: (string) -> string)
		order += 1
		local frame = UIKit.new("Frame", { Size = UDim2.new(1, -10, 0, 44), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = 7, Parent = page })
		local box = UIKit.TextBox({ Placeholder = placeholder, Size = UDim2.new(1, -170, 0, 40), ZIndex = 8, Parent = frame })
		UIKit.Button({ Text = buttonText, Color = color, Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -155, 0, 0), ZIndex = 8, Parent = frame, Callback = function()
			if box.Text ~= "" then
				run(build(box.Text))
				box.Text = ""
			end
		end })
	end

	section("💰 Economy")
	buttonRow({
		{ "🌧️ Cash Rain", Theme.Green, "cashrain" },
		{ "🔥 2x Event 10m", Color3.fromRGB(255, 110, 40), "doublecash 10 2" },
		{ "⚡ 5x Event 5m", Theme.Red, "doublecash 5 5" },
		{ "Me +$1B", Theme.Accent, "givecash me 1b", 120 },
	})
	buttonRow({
		{ "🏗️ Unlock All (me)", Theme.Accent2, "unlockall me", 190 },
		{ "🔄 Free Rebirth (me)", Theme.Purple, "rebirth me", 200 },
		{ "👑 VIP (me)", Theme.Accent, "givepass me VIP", 140 },
	})
	section("🎮 Minigames")
	buttonRow({
		{ "🪙 Coin Rush", Theme.Accent, "minigame CoinRush" },
		{ "🟥 Falling Tiles", Theme.Red, "minigame FallingTiles" },
		{ "☄️ Meteors", Color3.fromRGB(255, 120, 0), "minigame MeteorShower" },
	})
	section("🌍 World")
	buttonRow({
		{ "☀️ Day", Theme.Accent, "time 14", 110 },
		{ "🌙 Night", Theme.Purple, "time 0", 110 },
		{ "🌅 Sunset", Color3.fromRGB(255, 120, 80), "time 18", 120 },
		{ "🎉 Confetti All", Theme.Green, "confetti all", 160 },
	})
	buttonRow({
		{ "🕊️ Fly", Theme.Accent2, "fly me", 110 },
		{ "🚫 Unfly", Theme.SubText, "unfly me", 110 },
		{ "👻 Noclip", Theme.Purple, "noclip me", 120 },
		{ "🧱 Clip", Theme.SubText, "clip me", 110 },
		{ "💪 God", Theme.Green, "god me", 100 },
	})
	section("📢 Messages & Music")
	inputRow("Announcement text...", "📢 ANNOUNCE", Theme.Accent, function(text)
		return "m " .. text
	end)
	inputRow("Sound id (numbers only)...", "🎵 PLAY", Theme.Purple, function(text)
		return "music " .. text
	end)
	buttonRow({ { "⏹ Reset Music", Theme.SubText, "stopmusic", 170 } })
end

local function selectTab(name: string)
	currentTab = name
	for tabName, page in pages do
		page.Visible = tabName == name
		tabButtons[tabName].BackgroundColor3 = tabName == name and Theme.Red or Theme.PanelLight
	end
	if name == "Commands" then
		task.spawn(fillCommands)
	elseif name == "Players" then
		task.spawn(fillPlayers)
	elseif name == "Logs" then
		task.spawn(fillLogs)
	end
end

local function buildPanel()
	local _, content = C.UI:MakePanel("Admin", "🛡️ ADMIN PANEL", Theme.Red, 900, 600, function()
		selectTab(currentTab)
	end)

	-- command bar
	local bar = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 6, Parent = content })
	commandBox = UIKit.TextBox({ Placeholder = "Command (e.g. speed me 50) - press Enter", Size = UDim2.new(1, -130, 0, 42), ZIndex = 7, Parent = bar })
	UIKit.Button({ Text = "RUN ▶", Color = Theme.Green, Size = UDim2.fromOffset(120, 42), Position = UDim2.new(1, -120, 0, 0), ZIndex = 7, Parent = bar, Callback = function()
		run(commandBox.Text)
	end })
	commandBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			run(commandBox.Text)
		end
	end)
	resultLabel = UIKit.Label({ Text = "Rank: " .. (Config.RankNames[player:GetAttribute("AdminRank") or 0] or "?"), Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 48), Font = Theme.BodyFont, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = content })

	-- tabs
	local tabs = UIKit.new("Frame", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 74), BackgroundTransparency = 1, ZIndex = 6, Parent = content })
	UIKit.List(tabs, 8, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Left)
	for i, name in { "Commands", "Players", "Server", "Logs" } do
		tabButtons[name] = UIKit.Button({ Text = name:upper(), Color = Theme.PanelLight, Size = UDim2.fromOffset(140, 38), LayoutOrder = i, ZIndex = 7, Parent = tabs, Callback = function()
			selectTab(name)
		end })
		local page = UIKit.Scroll({ Size = UDim2.new(1, 0, 1, -124), Position = UDim2.fromOffset(0, 122), Parent = content })
		page.Visible = false
		UIKit.List(page, 6)
		UIKit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = page })
		pages[name] = page
	end
	buildServerPage()
end

---------------------------------------------------------------------------
function Admin:Init(controllers)
	C = controllers
	buildPanel()

	Remotes.ClientCommand.OnClientEvent:Connect(function(command, value)
		if command == "fly" then
			if value then
				startFly()
				C.Notifications:Toast("Fly ON: WASD + Space/E up, Ctrl/Q down, Shift = fast", "info", 6)
			else
				stopFly()
			end
		elseif command == "noclip" then
			setNoclip(value == true)
		elseif command == "view" then
			view(value)
		elseif command == "openadmin" then
			currentTab = value or "Commands"
			C.UI:Open("Admin")
		end
	end)

	player.CharacterAdded:Connect(function()
		flying = false
		flyParts = {}
		if flyConn then
			flyConn:Disconnect()
			flyConn = nil
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F2 and (player:GetAttribute("AdminRank") or 0) > 0 then
			C.UI:Toggle("Admin")
		end
	end)

	-- chat commands (TextChatService): ";cmd args"
	pcall(function()
		TextChatService.SendingMessage:Connect(function(message: TextChatMessage)
			local text = message.Text
			local prefix = Config.Admin.Prefix
			if text:sub(1, #prefix) == prefix and (player:GetAttribute("AdminRank") or 0) > 0 then
				task.spawn(run, text)
			end
		end)
	end)
end

function Admin:IsFlying()
	return flying
end

return Admin
