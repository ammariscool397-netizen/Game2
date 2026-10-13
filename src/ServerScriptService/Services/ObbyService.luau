--[[
	ObbyService - generates an obstacle course west of the lobby with
	checkpoints, kill bricks, spinners, trusses and a finish reward.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local BuildKit = require(script.Parent.BuildKit)

local Part = BuildKit.Part

local ObbyService = {}
local S

local checkpoints: { [number]: CFrame } = {}
local spinners = {}
local startTimes: { [Player]: number } = {}
local finishDebounce: { [Player]: boolean } = {}

local START_X = -215
local KILL_COLOR = Color3.fromRGB(255, 40, 40)

local folder: Model
local rng = Random.new(2024)

local function platform(size: Vector3, pos: Vector3, color: Color3?)
	return Part({
		Name = "Platform",
		Size = size,
		Position = pos,
		Color = color or Color3.fromHSV(rng:NextNumber(), 0.55, 0.95),
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
end

local function killPart(props)
	props.Color = KILL_COLOR
	props.Material = Enum.Material.Neon
	props.Parent = props.Parent or folder
	local part = Part(props)
	part:SetAttribute("Kill", true)
	part.Touched:Connect(function(hit)
		local _, humanoid = BuildKit.PlayerFromHit(hit)
		if humanoid then
			humanoid.Health = 0
		end
	end)
	return part
end

-- every segment starts at the edge `x` (previous platform ends there) at height `y`
local segments = {}

function segments.Jumps(x: number, y: number)
	for _ = 1, 5 do
		local gap = rng:NextNumber(3.5, 5.5)
		local size = rng:NextNumber(5, 7)
		y += rng:NextNumber(0, 1.5)
		local cx = x - gap - size / 2
		platform(Vector3.new(size, 1, size), Vector3.new(cx, y, rng:NextNumber(-4, 4)))
		x = cx - size / 2
	end
	return x, y
end

function segments.KillBricks(x: number, y: number)
	local length = 40
	platform(Vector3.new(length, 1, 10), Vector3.new(x - length / 2, y, 0), Color3.fromRGB(60, 60, 75))
	for i = 1, 4 do
		killPart({ Name = "KillBrick", Size = Vector3.new(1.6, 1.4, 10), Position = Vector3.new(x - i * 8, y + 1.2, 0) })
	end
	return x - length, y
end

function segments.Beam(x: number, y: number)
	local length = 28
	platform(Vector3.new(length, 1, 1.4), Vector3.new(x - length / 2, y, 0), Color3.fromRGB(255, 200, 40))
	platform(Vector3.new(8, 1, 8), Vector3.new(x - length - 4, y, 0))
	return x - length - 8, y
end

function segments.Truss(x: number, y: number)
	local height = 18
	local truss = Instance.new("TrussPart")
	truss.Anchored = true
	truss.Size = Vector3.new(2, height, 2)
	truss.Position = Vector3.new(x - 1, y + height / 2 - 0.5, 0)
	truss.Color = Color3.fromRGB(90, 90, 100)
	truss.Parent = folder
	y += height
	platform(Vector3.new(10, 1, 10), Vector3.new(x - 2 - 5, y, 0))
	return x - 12, y
end

function segments.Spinner(x: number, y: number)
	local size = 26
	local center = Vector3.new(x - size / 2, y, 0)
	platform(Vector3.new(size, 1, size), center, Color3.fromRGB(70, 70, 90))
	local bar = killPart({ Name = "Spinner", Size = Vector3.new(24, 1.2, 1.2), Position = center + Vector3.new(0, 1.6, 0) })
	Part({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(40, 40, 50), Material = Enum.Material.Metal, Parent = folder })
	table.insert(spinners, { Part = bar, Center = center + Vector3.new(0, 1.6, 0), Speed = rng:NextNumber(1.6, 2.4) * (rng:NextNumber() > 0.5 and 1 or -1), Angle = 0 })
	return x - size, y
end

function segments.Stairs(x: number, y: number)
	for _ = 1, 6 do
		y += 2
		platform(Vector3.new(4, 1, 8), Vector3.new(x - 2 - 2, y, 0))
		x -= 6
	end
	return x, y
end

function segments.Zigzag(x: number, y: number)
	local side = 1
	for _ = 1, 6 do
		local cx = x - 6
		platform(Vector3.new(4, 1, 4), Vector3.new(cx, y, side * 4))
		side = -side
		x = cx - 2
	end
	return x, y
end

local LAYOUT = {
	"Jumps", "KillBricks", "Checkpoint",
	"Beam", "Jumps", "Checkpoint",
	"Truss", "Spinner", "Checkpoint",
	"Zigzag", "Stairs", "Checkpoint",
	"KillBricks", "Beam", "Checkpoint",
	"Spinner", "Jumps", "Checkpoint",
	"Truss", "Zigzag", "Spinner", "Finish",
}

function ObbyService:Init(services)
	S = services
	folder = BuildKit.Model("Obby", workspace)

	-- start area
	local start = platform(Vector3.new(20, 1, 22), Vector3.new(START_X, 0.5, 0), Color3.fromRGB(0, 200, 255))
	start.Material = Enum.Material.Neon
	for _, z in { -10, 10 } do
		Part({ Name = "Arch", Size = Vector3.new(2, 16, 2), Position = Vector3.new(START_X - 9, 8, z), Color = Color3.fromRGB(40, 40, 55), Material = Enum.Material.Metal, Parent = folder })
	end
	local arch = Part({ Name = "ArchTop", Size = Vector3.new(2, 4, 22), Position = Vector3.new(START_X - 9, 17, 0), Color = Color3.fromRGB(255, 80, 160), Material = Enum.Material.Neon, Parent = folder })
	BuildKit.SurfaceText(arch, Enum.NormalId.Right, "🏃 OBBY - " .. Util.Money(Config.Obby.Reward) .. "+ REWARD", { PixelsPerStud = 18 })
	local startLine = Part({ Name = "StartLine", Size = Vector3.new(1, 14, 18), Position = Vector3.new(START_X - 9, 7, 0), Transparency = 1, CanCollide = false, Parent = folder })
	startLine.Touched:Connect(function(hit)
		local player = BuildKit.PlayerFromHit(hit)
		if player and (player:GetAttribute("ObbyStage") or 0) == 0 then
			startTimes[player] = os.clock()
			player:SetAttribute("ObbyStage", 0)
		end
	end)

	local x, y = START_X - 10, 4
	platform(Vector3.new(8, 1, 8), Vector3.new(x - 6, y, 0))
	x -= 10
	local stage = 0
	for _, name in LAYOUT do
		if name == "Checkpoint" or name == "Finish" then
			local isFinish = name == "Finish"
			x -= 4
			local pad = platform(Vector3.new(12, 1, 12), Vector3.new(x - 6, y, 0), isFinish and Color3.fromRGB(255, 200, 40) or Color3.fromRGB(60, 220, 100))
			pad.Material = Enum.Material.Neon
			if isFinish then
				self:_buildFinish(pad)
			else
				stage += 1
				local thisStage = stage
				checkpoints[thisStage] = CFrame.lookAt(pad.Position + Vector3.new(0, 4, 0), pad.Position + Vector3.new(-10, 4, 0))
				local flag = Part({ Name = "Flag", Size = Vector3.new(0.4, 8, 0.4), Position = pad.Position + Vector3.new(4, 4.5, 4), Color = Color3.fromRGB(230, 230, 230), Parent = folder })
				local cloth = Part({ Name = "Cloth", Size = Vector3.new(0.2, 2.4, 3.6), Position = flag.Position + Vector3.new(0, 2.6, -1.9), Color = Color3.fromRGB(60, 220, 100), Material = Enum.Material.Fabric, Parent = folder })
				BuildKit.Billboard(pad, "CHECKPOINT " .. thisStage, { Size = UDim2.fromOffset(180, 36), Offset = Vector3.new(0, 5, 0), Color = Color3.fromRGB(150, 255, 170), MaxDistance = 90 })
				pad.Touched:Connect(function(hit)
					local player = BuildKit.PlayerFromHit(hit)
					if player and (player:GetAttribute("ObbyStage") or 0) < thisStage then
						player:SetAttribute("ObbyStage", thisStage)
						cloth.Color = Color3.fromRGB(255, 220, 40)
						Remotes.Notify:FireClient(player, { Text = "Checkpoint " .. thisStage .. " reached!", Type = "success" })
						Remotes.VFX:FireClient(player, "Confetti", { Position = pad.Position + Vector3.new(0, 3, 0), Small = true })
					end
				end)
			end
			x -= 12
		else
			x, y = segments[name](x, y)
		end
	end

	-- lava floor under the whole course
	local length = START_X - 12 - x + 40
	killPart({
		Name = "Lava",
		Size = Vector3.new(length, 1, 70),
		Position = Vector3.new(START_X - 12 - length / 2, 0.4, 0),
	}).Color = Color3.fromRGB(255, 90, 0)

	Players.PlayerRemoving:Connect(function(player)
		startTimes[player] = nil
		finishDebounce[player] = nil
	end)
end

function ObbyService:_buildFinish(pad: BasePart)
	local trophy = Part({
		Name = "Trophy",
		Size = Vector3.new(3, 4, 3),
		Position = pad.Position + Vector3.new(0, 4, 0),
		Color = Color3.fromRGB(255, 210, 40),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Tags = { "Spin", "Bob" },
		Parent = folder,
	})
	BuildKit.Light(trophy, Color3.fromRGB(255, 210, 40), 30, 3)
	BuildKit.Particles(trophy, { Color = ColorSequence.new(Color3.fromRGB(255, 230, 80)), Size = BuildKit.Size(1), Rate = 25, SpreadAngle = Vector2.new(180, 180) })
	BuildKit.Billboard(pad, "🏆 FINISH! 🏆", { Size = UDim2.fromOffset(220, 50), Offset = Vector3.new(0, 9, 0), Color = Color3.fromRGB(255, 220, 60), MaxDistance = 150 })

	pad.Touched:Connect(function(hit)
		local player = BuildKit.PlayerFromHit(hit)
		if not player or finishDebounce[player] then
			return
		end
		if (player:GetAttribute("ObbyStage") or 0) <= 0 then
			return -- must have actually run the course
		end
		finishDebounce[player] = true
		self:_finish(player)
		task.delay(3, function()
			finishDebounce[player] = nil
			if player.Parent then
				player:SetAttribute("ObbyStage", 0)
				S.TycoonService:TeleportHome(player)
			end
		end)
	end)
end

function ObbyService:_finish(player: Player)
	local data = S.DataService:Get(player)
	if not data then
		return
	end
	local elapsed = startTimes[player] and (os.clock() - startTimes[player]) or nil
	startTimes[player] = nil
	data.ObbyCompletions += 1
	Remotes.VFX:FireClient(player, "Confetti", {})
	Remotes.VFX:FireClient(player, "WinSound", {})
	local now = os.time()
	if now - data.LastObbyReward >= Config.Obby.Cooldown then
		data.LastObbyReward = now
		local reward = Config.Obby.Reward * (1 + data.Rebirths)
		S.DataService:AddCash(player, reward, false)
		Remotes.Notify:FireClient(player, { Text = "Obby complete! +" .. Util.Money(reward), Type = "success", Duration = 6 })
		Remotes.VFX:FireClient(player, "CashBurst", { Amount = reward })
	else
		Remotes.Notify:FireClient(player, {
			Text = "Obby complete! Next reward in " .. Util.FormatTime(Config.Obby.Cooldown - (now - data.LastObbyReward)),
			Type = "info",
			Duration = 6,
		})
	end
	Remotes.Announce:FireAllClients({
		Title = "🏃 " .. player.DisplayName .. " beat the obby!",
		Text = elapsed and ("Time: " .. string.format("%.1f", elapsed) .. "s") or "",
		Color = Color3.fromRGB(255, 80, 160),
	})
end

function ObbyService:GetCheckpointCFrame(stage: number): CFrame?
	return checkpoints[stage]
end

function ObbyService:Start()
	RunService.Heartbeat:Connect(function(dt)
		for _, spinner in spinners do
			spinner.Angle += dt * spinner.Speed
			spinner.Part.CFrame = CFrame.new(spinner.Center) * CFrame.Angles(0, spinner.Angle, 0)
		end
	end)
end

return ObbyService
