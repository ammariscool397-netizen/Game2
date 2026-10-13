--[[
	Guide (client) - a glowing beam from you to your next goal in your tower:
	the cheapest button you can afford (on your floor first), or a vault pad
	when collecting would let you buy something. Only near your own tower;
	hidden during nukes and minigames. Turn it off in Settings.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local UIKit = require(Shared.UIKit)
local TycoonItems = require(Shared.TycoonItems)

local player = Players.LocalPlayer
local Theme = UIKit.Theme

local Guide = {}
Guide.Target = nil :: { Kind: string, Id: string?, Position: Vector3 }?

local RANGE = 150 -- studs from your tower's centre
local fromAttachment: Attachment?
local anchor: BasePart
local beam: Beam
local labelGui: BillboardGui
local label: TextLabel

local function root(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function plotModel(): Instance?
	local index = player:GetAttribute("Plot")
	local tycoons = workspace:FindFirstChild("Tycoons")
	return index and tycoons and tycoons:FindFirstChild("Plot" .. tostring(index))
end

-- where should the player go next?
local function findTarget(from: BasePart)
	local plot = plotModel()
	local center = player:GetAttribute("PlotCenter")
	if not plot or typeof(center) ~= "Vector3" then
		return nil
	end
	local offset = from.Position - center
	if Vector3.new(offset.X, 0, offset.Z).Magnitude > RANGE then
		return nil
	end
	local cash = player:GetAttribute("Cash") or 0
	local buttons = plot:FindFirstChild("Buttons")
	local best, bestScore, cheapest = nil, math.huge, nil
	for _, model in buttons and buttons:GetChildren() or {} do
		local item = TycoonItems.ById[model.Name]
		local pad = model:FindFirstChild("Pad") :: BasePart?
		if item and pad then
			if not cheapest or item.Cost < cheapest.Cost then
				cheapest = item
			end
			if item.Cost <= cash then
				-- strongly prefer buttons on the floor you're standing on
				local sameFloor = math.abs(pad.Position.Y - from.Position.Y) < Config.Tycoon.FloorHeight / 2
				local score = item.Cost * (sameFloor and 1 or 1000)
				if score < bestScore then
					best, bestScore = { Kind = "Buy", Id = item.Id, Position = pad.Position, Text = "⬇ BUY: " .. item.Name }, score
				end
			end
		end
	end
	if best then
		return best
	end
	-- nothing affordable: the vault would make it affordable?
	local vault = player:GetAttribute("Vault") or 0
	if cheapest and vault > 0 and cash + vault >= cheapest.Cost and not player:GetAttribute("Pass_AutoCollect") then
		local items = plot:FindFirstChild("Items")
		local nearest, nearestD = nil, math.huge
		for floor = 1, Config.Tycoon.Floors do
			local unlock = items and items:FindFirstChild(TycoonItems.FloorUnlockId(floor))
			local pad = unlock and unlock:FindFirstChild("VaultPad", true) :: BasePart?
			if pad then
				local d = (pad.Position - from.Position).Magnitude
				if d < nearestD then
					nearest, nearestD = pad, d
				end
			end
		end
		if nearest then
			return { Kind = "Vault", Position = nearest.Position, Text = "💰 COLLECT " .. Util.Money(vault) }
		end
	end
	return nil
end

local function hide()
	Guide.Target = nil
	beam.Enabled = false
	labelGui.Enabled = false
end

local function update()
	local r = root()
	local enabled = player:GetAttribute("Guide") ~= false
	if not r or not enabled or player:GetAttribute("InMinigame") or workspace:GetAttribute("Disaster") == "Nuke" then
		hide()
		return
	end
	local target = findTarget(r)
	if not target then
		hide()
		return
	end
	if not fromAttachment or fromAttachment.Parent ~= r then
		local attachment = Instance.new("Attachment")
		attachment.Name = "GuideFrom"
		attachment.Parent = r
		beam.Attachment0 = attachment
		fromAttachment = attachment
	end
	Guide.Target = target
	anchor.CFrame = CFrame.new(target.Position + Vector3.new(0, 1, 0))
	local color = target.Kind == "Vault" and Theme.Accent or Theme.Green
	beam.Color = ColorSequence.new(color)
	beam.Enabled = true
	label.Text = target.Text
	label.TextColor3 = color
	labelGui.Enabled = true
end

function Guide:Init()
	anchor = Instance.new("Part")
	anchor.Name = "GuideTarget"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = workspace
	local toAttachment = Instance.new("Attachment")
	toAttachment.Parent = anchor
	beam = Instance.new("Beam")
	beam.Attachment1 = toAttachment
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Segments = 16
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 3
	beam.TextureSpeed = 2
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.2, 0.15), NumberSequenceKeypoint.new(1, 0.1) })
	beam.Enabled = false
	beam.Parent = anchor
	labelGui = Instance.new("BillboardGui")
	labelGui.Name = "GuideLabel"
	labelGui.Size = UDim2.fromOffset(240, 40)
	labelGui.StudsOffset = Vector3.new(0, 4.5, 0)
	labelGui.AlwaysOnTop = true
	labelGui.MaxDistance = 120
	labelGui.Enabled = false
	labelGui.Parent = anchor
	label = UIKit.Label({ Text = "", Size = UDim2.fromScale(1, 1), Parent = labelGui })
end

function Guide:Start()
	while true do
		task.wait(0.25)
		Util.Try("Guide", update)
	end
end

return Guide
