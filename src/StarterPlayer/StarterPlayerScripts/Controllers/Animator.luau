--[[
	Animator - smooth client-side animation for tagged parts:
	  Spin  - rotates around world Y
	  Bob   - floats up and down
	  Pulse - neon glow pulsing
	  RainbowSign - rainbow text on owner signs
	Only animates things near the camera to keep FPS high.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Animator = {}

local spinning: { [BasePart]: { Base: CFrame, Speed: number, Phase: number, Spin: boolean, Bob: boolean } } = {}
local pulsing: { [BasePart]: { Color: Color3, Phase: number } } = {}
local rainbow: { [TextLabel]: boolean } = {}
local uiSpin: { [GuiObject]: boolean } = {}
local lowGraphics = false
local RANGE = 260

local function track(instance: Instance)
	if not instance:IsA("BasePart") or spinning[instance :: BasePart] then
		return
	end
	local part = instance :: BasePart
	spinning[part] = {
		Base = part.CFrame,
		Speed = 1.2 + math.random() * 0.8,
		Phase = math.random() * math.pi * 2,
		Spin = CollectionService:HasTag(part, "Spin"),
		Bob = CollectionService:HasTag(part, "Bob"),
	}
end

local function untrack(part: Instance)
	if part:IsA("BasePart") and not CollectionService:HasTag(part, "Spin") and not CollectionService:HasTag(part, "Bob") then
		spinning[part] = nil
	end
end

function Animator:IsLowGraphics(): boolean
	return lowGraphics
end

-- low graphics: no animations and no particles (also ones created later).
-- Only emitters we switched off are switched back on.
local quieted = setmetatable({}, { __mode = "k" })
local descendantConn: RBXScriptConnection?
local function quiet(d: Instance)
	if lowGraphics and d:IsA("ParticleEmitter") and d.Enabled then
		d.Enabled = false
		quieted[d] = true
	end
end

function Animator:SetLowGraphics(enabled: boolean)
	if enabled == lowGraphics then
		return
	end
	lowGraphics = enabled
	if enabled then
		for _, d in workspace:GetDescendants() do
			quiet(d)
		end
		descendantConn = workspace.DescendantAdded:Connect(function(d)
			if d:IsA("ParticleEmitter") then
				task.defer(quiet, d)
			end
		end)
	else
		if descendantConn then
			descendantConn:Disconnect()
			descendantConn = nil
		end
		for d in quieted do
			if d.Parent then
				(d :: ParticleEmitter).Enabled = true
			end
		end
		table.clear(quieted)
	end
end

function Animator:Init()
	for _, tag in { "Spin", "Bob" } do
		for _, part in CollectionService:GetTagged(tag) do
			track(part)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(part)
			-- refresh tag info (a part can have both tags)
			spinning[part] = nil
			track(part)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(untrack)
	end
	for _, part in CollectionService:GetTagged("Pulse") do
		if part:IsA("BasePart") then
			pulsing[part] = { Color = part.Color, Phase = math.random() * 6 }
		end
	end
	CollectionService:GetInstanceAddedSignal("Pulse"):Connect(function(part)
		if part:IsA("BasePart") then
			pulsing[part] = { Color = part.Color, Phase = math.random() * 6 }
		end
	end)
	CollectionService:GetInstanceRemovedSignal("Pulse"):Connect(function(part)
		pulsing[part] = nil
	end)

	local function trackSign(sign: Instance)
		for _, d in sign:GetDescendants() do
			if d:IsA("TextLabel") then
				rainbow[d] = true
			end
		end
	end
	for _, sign in CollectionService:GetTagged("RainbowSign") do
		trackSign(sign)
	end
	CollectionService:GetInstanceAddedSignal("RainbowSign"):Connect(function(sign)
		task.wait()
		trackSign(sign)
	end)

	for _, ui in CollectionService:GetTagged("UISpin") do
		uiSpin[ui] = true
	end
	CollectionService:GetInstanceAddedSignal("UISpin"):Connect(function(ui)
		uiSpin[ui] = true
	end)
end

function Animator:Start()
	-- the saved setting
	self:SetLowGraphics(player:GetAttribute("LowGraphics") == true)
	player:GetAttributeChangedSignal("LowGraphics"):Connect(function()
		self:SetLowGraphics(player:GetAttribute("LowGraphics") == true)
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local cam = workspace.CurrentCamera
		local camPos = cam.CFrame.Position

		for ui in uiSpin do
			if ui.Parent then
				ui.Rotation = math.sin(t * 2) * 15
			else
				uiSpin[ui] = nil
			end
		end

		if lowGraphics then
			return
		end

		for part, info in spinning do
			if not part.Parent then
				spinning[part] = nil
				continue
			end
			local base = info.Base
			if (base.Position - camPos).Magnitude > RANGE then
				continue
			end
			local pos = base.Position
			if info.Bob then
				pos += Vector3.new(0, math.sin(t * 2 + info.Phase) * 0.8, 0)
			end
			local rotation = base.Rotation
			if info.Spin then
				rotation = CFrame.Angles(0, t * info.Speed + info.Phase, 0) * rotation
			end
			part.CFrame = CFrame.new(pos) * rotation
		end

		for part, info in pulsing do
			if not part.Parent then
				pulsing[part] = nil
				continue
			end
			if (part.Position - camPos).Magnitude > RANGE then
				continue
			end
			local alpha = (math.sin(t * 3 + info.Phase) + 1) / 2
			part.Color = info.Color:Lerp(Color3.new(1, 1, 1), alpha * 0.3)
		end

		for label in rainbow do
			if not label.Parent then
				rainbow[label] = nil
				continue
			end
			label.TextColor3 = Color3.fromHSV((t * 0.15) % 1, 0.75, 1)
		end
	end)
end

return Animator
