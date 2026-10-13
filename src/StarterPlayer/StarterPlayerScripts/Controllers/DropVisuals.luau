--[[
	DropVisuals (client) - renders the falling cash drops locally.
	The server calculates income; it tags dropper / upgrader / generator
	models with attributes (Spout, BeltEnd, Interval, Worth, ...). Here we
	spawn cheap anchored parts that fall onto the conveyor, change colour
	when they pass an upgrader and pop "+$" at the collector.
	Only towers near the camera (and your current floor) are animated.
]]
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)

local player = Players.LocalPlayer

local DropVisuals = {}
local C

local MAX_DROPS = 180
local VIEW_RANGE = 150
local FLOOR_RANGE = 11
local FALL_TIME = 0.35

local droppers: { [Model]: { Next: number } } = {}
local generators: { [Model]: { Next: number } } = {}
local fireworks: { [Model]: { Next: number } } = {}
local live = 0
local folder: Folder
local enabled = true
local popTotals: { [string]: { Amount: number, Position: Vector3 } } = {}

function DropVisuals:SetEnabled(on: boolean)
	enabled = on
end

local function focusPosition(): Vector3
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position or workspace.CurrentCamera.CFrame.Position
end

local function upgradersFor(model: Model)
	local plot, floor = model:GetAttribute("Plot"), model:GetAttribute("Floor")
	local list = {}
	for _, up in CollectionService:GetTagged("Upgrader") do
		if up.Parent and up:GetAttribute("Plot") == plot and up:GetAttribute("Floor") == floor then
			local pos = up:GetAttribute("BeltPos")
			if typeof(pos) == "Vector3" then
				table.insert(list, { Pos = pos, Color = up:GetAttribute("Color") })
			end
		end
	end
	return list
end

local function spawnDrop(model: Model)
	local spout = model:GetAttribute("Spout")
	local beltEnd = model:GetAttribute("BeltEnd")
	if typeof(spout) ~= "Vector3" or typeof(beltEnd) ~= "Vector3" then
		return
	end
	local tier = model:GetAttribute("Tier") or 1
	local size = 0.9 + tier * 0.07
	local drop = Instance.new("Part")
	drop.Name = "Drop"
	drop.Anchored = true
	drop.CanCollide = false
	drop.CanQuery = false
	drop.CanTouch = false
	drop.CastShadow = false
	drop.Size = Vector3.one * size
	drop.Color = model:GetAttribute("DropColor") or Color3.fromRGB(200, 200, 200)
	local materialName = model:GetAttribute("DropMaterial")
	local ok, material = pcall(function()
		return (Enum.Material :: any)[materialName]
	end)
	drop.Material = ok and material or Enum.Material.SmoothPlastic
	drop.CFrame = CFrame.new(spout) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
	drop.Parent = folder
	live += 1

	local landing = Vector3.new(spout.X, beltEnd.Y + size / 2, spout.Z)
	local finish = Vector3.new(beltEnd.X, beltEnd.Y + size / 2, beltEnd.Z)
	local speed = model:GetAttribute("BeltSpeed") or 12
	local distance = (finish - landing).Magnitude
	local travel = distance / speed
	TweenService:Create(drop, TweenInfo.new(FALL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = landing }):Play()
	task.delay(FALL_TIME, function()
		if drop.Parent then
			TweenService:Create(drop, TweenInfo.new(travel, Enum.EasingStyle.Linear), { Position = finish }):Play()
		end
	end)
	-- colour change at each upgrader
	local dir = distance > 0 and (finish - landing).Unit or Vector3.xAxis
	for _, up in upgradersFor(model) do
		local along = (up.Pos - landing):Dot(dir)
		if along > 0 and along < distance then
			task.delay(FALL_TIME + along / speed, function()
				if drop.Parent then
					drop.Color = up.Color or drop.Color
					drop.Material = Enum.Material.Neon
					drop.Size *= 1.12
				end
			end)
		end
	end
	local worth = model:GetAttribute("Worth") or 0
	local key = tostring(model:GetAttribute("Plot")) .. "_" .. tostring(model:GetAttribute("Floor"))
	task.delay(FALL_TIME + travel, function()
		live -= 1
		if drop.Parent then
			drop:Destroy()
		end
		local entry = popTotals[key]
		if not entry then
			entry = { Amount = 0, Position = finish + Vector3.new(0, 3, 0) }
			popTotals[key] = entry
		end
		entry.Amount += worth
	end)
end

local function launchFirework(model: Model)
	local pos = model:GetAttribute("LaunchPos")
	if typeof(pos) ~= "Vector3" then
		return
	end
	local color = Color3.fromHSV(math.random(), 0.8, 1)
	local rocket = Instance.new("Part")
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CanQuery = false
	rocket.CanTouch = false
	rocket.Size = Vector3.new(0.6, 1.6, 0.6)
	rocket.Color = color
	rocket.Material = Enum.Material.Neon
	rocket.Position = pos
	rocket.Parent = folder
	local trail = Instance.new("Fire")
	trail.Size = 2
	trail.Heat = 6
	trail.Parent = rocket
	local top = pos + Vector3.new(math.random(-8, 8), math.random(50, 70), math.random(-8, 8))
	local tween = TweenService:Create(rocket, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = top })
	tween:Play()
	tween.Completed:Connect(function()
		rocket.Transparency = 1
		trail.Enabled = false
		local burst = Instance.new("ParticleEmitter")
		burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		burst.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
		burst.LightEmission = 1
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
		burst.Speed = NumberRange.new(25, 40)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Lifetime = NumberRange.new(1, 1.6)
		burst.Drag = 3
		burst.Acceleration = Vector3.new(0, -12, 0)
		burst.Rate = 0
		burst.Parent = rocket
		burst:Emit(80)
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 60
		light.Brightness = 4
		light.Parent = rocket
		TweenService:Create(light, TweenInfo.new(1.2), { Brightness = 0 }):Play()
		Debris:AddItem(rocket, 2.2)
	end)
end

local function track(map, model)
	if model:IsA("Model") then
		map[model] = { Next = os.clock() + math.random() * 2 }
	end
end

function DropVisuals:Init(controllers)
	C = controllers
	folder = Instance.new("Folder")
	folder.Name = "LocalDrops"
	folder.Parent = workspace
	for tag, map in { Dropper = droppers, Generator = generators, Fireworks = fireworks } do
		for _, model in CollectionService:GetTagged(tag) do
			track(map, model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
			track(map, model)
		end)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(model)
			map[model] = nil
		end)
	end
end

function DropVisuals:Start()
	local lastPop = 0
	while true do
		task.wait(0.1)
		local now = os.clock()
		local focus = focusPosition()
		local lowGraphics = C.Animator and C.Animator.IsLowGraphics and C.Animator:IsLowGraphics()
		if enabled and not lowGraphics then
			for model, info in droppers do
				if not model.Parent then
					droppers[model] = nil
				elseif now >= info.Next then
					local interval = model:GetAttribute("Interval") or 2
					info.Next = now + interval
					local spout = model:GetAttribute("Spout")
					if typeof(spout) == "Vector3" and live < MAX_DROPS then
						local d = spout - focus
						if Vector3.new(d.X, 0, d.Z).Magnitude < VIEW_RANGE and math.abs(d.Y - 3.5) < FLOOR_RANGE then
							spawnDrop(model)
						end
					end
				end
			end
		end
		-- "+$" pops at collectors (batched)
		if now - lastPop >= 0.8 then
			lastPop = now
			for key, entry in popTotals do
				if entry.Amount > 0 and C.VFX then
					C.VFX:FloatText(entry.Position, "+" .. Util.Money(entry.Amount), Color3.fromRGB(120, 255, 140), 0.8)
				end
				popTotals[key] = nil
			end
			-- generators
			local shown = 0
			for model, info in generators do
				if not model.Parent then
					generators[model] = nil
				elseif now >= info.Next then
					info.Next = now + (model:GetAttribute("Cycle") or 5)
					local pos = model:GetAttribute("PopPos")
					if typeof(pos) == "Vector3" and shown < 6 and C.VFX then
						local d = pos - focus
						if Vector3.new(d.X, 0, d.Z).Magnitude < 70 and math.abs(d.Y - 9) < FLOOR_RANGE then
							shown += 1
							C.VFX:FloatText(pos, "+" .. Util.Money(model:GetAttribute("Worth") or 0), Color3.fromRGB(255, 220, 90), 0.7)
						end
					end
				end
			end
		end
		for model, info in fireworks do
			if not model.Parent then
				fireworks[model] = nil
			elseif now >= info.Next then
				info.Next = now + math.random(4, 8)
				local pos = model:GetAttribute("LaunchPos")
				if typeof(pos) == "Vector3" and (pos - workspace.CurrentCamera.CFrame.Position).Magnitude < 500 then
					launchFirework(model)
				end
			end
		end
	end
end

return DropVisuals
