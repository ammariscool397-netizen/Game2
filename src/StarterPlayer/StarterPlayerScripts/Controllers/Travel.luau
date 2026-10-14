--[[
	Travel (client) - the Travel panel: go to the far islands (and back to the
	plaza) and see how many treasure chests are ready on each.
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
local IC = Config.Islands

local Travel = {}
local C

local rows: { [string]: { Status: TextLabel, Button: TextButton } } = {}

local function refresh()
	local rebirths = player:GetAttribute("Rebirths") or 0
	for _, island in IC.List do
		local row = rows[island.Id]
		if row then
			local locked = rebirths < island.Rebirths
			local ready = player:GetAttribute("ChestsReady_" .. island.Id) or 0
			local nextAt = player:GetAttribute("ChestNext_" .. island.Id) or 0
			if locked then
				row.Status.Text = "🔒 Unlocks at " .. island.Rebirths .. " rebirths"
				row.Status.TextColor3 = Theme.SubText
			elseif ready > 0 then
				row.Status.Text = "💰 " .. ready .. "/" .. island.Chests .. " chests ready!"
				row.Status.TextColor3 = Color3.fromRGB(150, 255, 160)
			else
				row.Status.Text = "Next chest in " .. Util.Clock(math.max(0, nextAt - Util.ServerNow()))
				row.Status.TextColor3 = Theme.SubText
			end
			row.Button.BackgroundColor3 = locked and Color3.fromRGB(90, 90, 110) or Theme.Green
		end
	end
	if C.HUD and C.HUD.SetBadge then
		C.HUD:SetBadge("Travel", (player:GetAttribute("ChestsReady") or 0) > 0, tostring(player:GetAttribute("ChestsReady") or 0))
	end
end

local function go(destination: string)
	local ok, message = Remotes.Travel:InvokeServer(destination)
	C.Notifications:Toast(tostring(message), ok and "success" or "error")
	if ok then
		C.UI:Close()
	end
end

function Travel:Init(controllers)
	C = controllers
	local _, content = C.UI:MakePanel("Travel", "🧭 TRAVEL", Color3.fromRGB(60, 200, 190), 620, 460)
	UIKit.List(content, 10)
	UIKit.new("TextLabel", {
		Text = "Islands beyond the edge of the world, full of treasure chests. Each chest reopens 30 minutes after you open it - even if you leave the game.",
		Size = UDim2.new(1, -20, 0, 54),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextSize = 16,
		Font = Theme.BodyFont,
		TextColor3 = Theme.SubText,
		LayoutOrder = 0,
		ZIndex = 7,
		Parent = content,
	})
	local function row(order: number, id: string, title: string)
		local frame = UIKit.new("Frame", { Name = "Dest" .. id, Size = UDim2.new(1, -10, 0, 66), BackgroundColor3 = Theme.Panel, LayoutOrder = order, ZIndex = 7, Parent = content })
		UIKit.Corner(frame, 10)
		UIKit.Label({ Text = title, Size = UDim2.new(1, -170, 0, 28), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = frame })
		local status = UIKit.Label({ Text = "", Size = UDim2.new(1, -170, 0, 20), Position = UDim2.fromOffset(12, 38), TextXAlignment = Enum.TextXAlignment.Left, Font = Theme.BodyFont, Stroke = false, ZIndex = 8, Parent = frame })
		local button = UIKit.Button({
			Name = "Go" .. id,
			Text = "GO ▶",
			Color = Theme.Green,
			Size = UDim2.fromOffset(130, 44),
			Position = UDim2.new(1, -142, 0, 11),
			ZIndex = 8,
			Parent = frame,
			Callback = function()
				go(id)
			end,
		})
		rows[id] = { Status = status, Button = button }
	end
	row(1, "Plaza", "🏠 Main Island")
	rows.Plaza.Status.Text = "The spawn plaza"
	for i, island in IC.List do
		row(i + 1, island.Id, island.Icon .. " " .. island.Name)
	end
	player:GetAttributeChangedSignal("ChestsReady"):Connect(refresh)
	player:GetAttributeChangedSignal("Rebirths"):Connect(refresh)
	refresh()
end

function Travel:Start()
	while true do
		task.wait(1)
		Util.Try("Travel", refresh)
	end
end

return Travel
