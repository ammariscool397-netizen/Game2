--[[
	MinigameService - round based minigames in a sky arena.
	Flow: Intermission -> Join window (players press JOIN) -> Countdown ->
	Playing -> Results -> everyone is sent home.

	Games: CoinRush, FallingTiles, MeteorShower (configure in Config.Minigames)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local BuildKit = require(script.Parent.BuildKit)

local Part = BuildKit.Part
local MG = Config.Minigames

local MinigameService = {}
local S

local running = false
local forced: string? = nil
local joined: { [Player]: boolean } = {}
local acceptingJoins = false

local function broadcast(state)
	Remotes.MinigameState:FireAllClients(state)
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function rebirthScale(player: Player): number
	return 1 + (tonumber(player:GetAttribute("Rebirths")) or 0)
end

-- the bigger of a fixed minimum (scaled by rebirths) or N seconds of the player's income
local function incomeReward(player: Player, seconds: number, minimum: number): number
	return math.max(minimum * rebirthScale(player), S.TycoonService:GetIncome(player) * seconds)
end

local function barrier(folder: Instance, center: Vector3, size: number, height: number)
	for _, data in {
		{ Vector3.new(size, height, 2), Vector3.new(0, height / 2, size / 2 + 1) },
		{ Vector3.new(size, height, 2), Vector3.new(0, height / 2, -size / 2 - 1) },
		{ Vector3.new(2, height, size), Vector3.new(size / 2 + 1, height / 2, 0) },
		{ Vector3.new(2, height, size), Vector3.new(-size / 2 - 1, height / 2, 0) },
	} do
		Part({ Name = "Barrier", Size = data[1], Position = center + data[2], Transparency = 0.85, Color = Color3.fromRGB(120, 200, 255), Material = Enum.Material.ForceField, Parent = folder })
	end
end

---------------------------------------------------------------------------
-- Games. Each has Setup(ctx) and Run(ctx); Run returns when the round ends.
---------------------------------------------------------------------------
local Games = {}

Games.CoinRush = {
	Setup = function(ctx)
		local c = ctx.Center
		Part({ Name = "Floor", Size = Vector3.new(110, 2, 110), Position = c, Color = Color3.fromRGB(70, 60, 110), Material = Enum.Material.Slate, Parent = ctx.Folder })
		Part({ Name = "Edge", Size = Vector3.new(114, 1.8, 114), Position = c - Vector3.new(0, 0.2, 0), Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Neon, Parent = ctx.Folder })
		barrier(ctx.Folder, c, 110, 30)
		local rng = Random.new()
		for _ = 1, 14 do
			local size = Vector3.new(rng:NextNumber(4, 10), rng:NextNumber(3, 9), rng:NextNumber(4, 10))
			Part({
				Name = "Obstacle",
				Size = size,
				Position = c + Vector3.new(rng:NextNumber(-45, 45), 1 + size.Y / 2, rng:NextNumber(-45, 45)),
				Color = Color3.fromHSV(rng:NextNumber(), 0.6, 0.9),
				Parent = ctx.Folder,
			})
		end
		ctx.SpawnRadius = 40
	end,
	Run = function(ctx)
		local rng = Random.new()
		local coins = 0
		local info = MG.Games.CoinRush
		local function spawnCoin()
			coins += 1
			local coin = Part({
				Name = "Coin",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.5, 3, 3),
				CFrame = CFrame.new(ctx.Center + Vector3.new(rng:NextNumber(-50, 50), 4, rng:NextNumber(-50, 50))) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
				Color = Color3.fromRGB(255, 205, 40),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Tags = { "Spin" },
				Parent = ctx.Folder,
			})
			BuildKit.Light(coin, Color3.fromRGB(255, 205, 40), 8, 1)
			local taken = false
			coin.Touched:Connect(function(hit)
				if taken then
					return
				end
				local player = BuildKit.PlayerFromHit(hit)
				if player and ctx.Alive[player] and BuildKit.IsNear(player, coin) then
					taken = true
					coins -= 1
					ctx.Scores[player] = (ctx.Scores[player] or 0) + 1
					player:SetAttribute("MinigameScore", ctx.Scores[player])
					Remotes.VFX:FireClient(player, "CoinPop", { Position = coin.Position })
					coin:Destroy()
				end
			end)
		end
		for _ = 1, 20 do
			spawnCoin()
		end
		ctx:Loop(info.Duration, function()
			if coins < 40 then
				spawnCoin()
			end
			return false
		end, function(player)
			-- fell off: put them back
			ctx:Place(player)
			return true
		end)
	end,
	Rewards = function(ctx)
		local info = MG.Games.CoinRush
		local best, bestScore = nil, 0
		local results = {}
		for player in ctx.Participants do
			local score = ctx.Scores[player] or 0
			if score > bestScore then
				best, bestScore = player, score
			end
		end
		for player in ctx.Participants do
			local score = ctx.Scores[player] or 0
			local reward = score * incomeReward(player, info.CoinIncomeSeconds, info.CoinMin)
			if player == best then
				reward += incomeReward(player, info.WinnerIncomeSeconds, info.WinnerMin)
			end
			table.insert(results, { Player = player, Score = score .. " coins", Reward = reward, Winner = player == best })
		end
		return results
	end,
}

Games.FallingTiles = {
	Setup = function(ctx)
		local c = ctx.Center
		local tiles = 13
		local size = 7
		local offset = (tiles - 1) * size / 2
		for layer = 0, 1 do
			for x = 0, tiles - 1 do
				for z = 0, tiles - 1 do
					local hue = ((x + z) % 6) / 6
					local tile = Part({
						Name = "Tile",
						Size = Vector3.new(size - 0.2, 1, size - 0.2),
						Position = c + Vector3.new(x * size - offset, -layer * 22, z * size - offset),
						Color = Color3.fromHSV(hue, 0.55, 1),
						Material = Enum.Material.SmoothPlastic,
						Parent = ctx.Folder,
					})
					local triggered = false
					tile.Touched:Connect(function(hit)
						if triggered then
							return
						end
						local player = BuildKit.PlayerFromHit(hit)
						if not player or not ctx.Alive[player] or not ctx.Started or not BuildKit.IsNear(player, tile) then
							return
						end
						triggered = true
						tile.Color = Color3.fromRGB(255, 60, 60)
						tile.Material = Enum.Material.Neon
						task.delay(0.5, function()
							tile.CanCollide = false
							TweenService:Create(tile, TweenInfo.new(0.4), { Transparency = 1, Position = tile.Position - Vector3.new(0, 6, 0) }):Play()
							task.delay(0.5, function()
								tile:Destroy()
							end)
						end)
					end)
				end
			end
		end
		ctx.SpawnRadius = 35
		ctx.FallDepth = 45
	end,
	Run = function(ctx)
		ctx:Loop(MG.Games.FallingTiles.Duration, function()
			local alive = ctx:AliveCount()
			if ctx.StartCount > 1 then
				return alive <= 1
			end
			return alive == 0
		end)
	end,
	Rewards = function(ctx)
		return ctx:SurvivalRewards(MG.Games.FallingTiles)
	end,
}

Games.MeteorShower = {
	Setup = function(ctx)
		local c = ctx.Center
		Part({ Name = "Floor", Size = Vector3.new(110, 3, 110), Position = c, Color = Color3.fromRGB(90, 80, 80), Material = Enum.Material.Basalt, Parent = ctx.Folder })
		Part({ Name = "Glow", Size = Vector3.new(112, 2.6, 112), Position = c - Vector3.new(0, 0.4, 0), Color = Color3.fromRGB(255, 100, 0), Material = Enum.Material.Neon, Parent = ctx.Folder })
		ctx.SpawnRadius = 40
		ctx.FallDepth = 30
	end,
	Run = function(ctx)
		local rng = Random.new()
		local elapsed = 0
		local duration = MG.Games.MeteorShower.Duration
		local function meteor()
			local target
			local alive = {}
			for p in ctx.Alive do
				table.insert(alive, p)
			end
			if #alive > 0 and rng:NextNumber() < 0.55 then
				local root = getRoot(alive[rng:NextInteger(1, #alive)])
				if root then
					target = Vector3.new(root.Position.X + rng:NextNumber(-6, 6), ctx.Center.Y + 1.6, root.Position.Z + rng:NextNumber(-6, 6))
				end
			end
			target = target or ctx.Center + Vector3.new(rng:NextNumber(-52, 52), 1.6, rng:NextNumber(-52, 52))
			local radius = 10
			local warning = Part({
				Name = "Warning",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, radius * 2, radius * 2),
				CFrame = CFrame.new(target) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(255, 40, 40),
				Material = Enum.Material.Neon,
				Transparency = 0.5,
				CanCollide = false,
				CanTouch = false,
				Parent = ctx.Folder,
			})
			task.delay(1.3, function()
				if not ctx.Folder.Parent then
					return
				end
				local rock = Part({
					Name = "Meteor",
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 7,
					Position = target + Vector3.new(rng:NextNumber(-20, 20), 120, rng:NextNumber(-20, 20)),
					Color = Color3.fromRGB(120, 50, 20),
					Material = Enum.Material.CrackedLava,
					CanCollide = false,
					CanTouch = false,
					Parent = ctx.Folder,
				})
				local fire = Instance.new("Fire")
				fire.Size = 12
				fire.Heat = 20
				fire.Parent = rock
				BuildKit.Light(rock, Color3.fromRGB(255, 120, 0), 30, 4)
				local tween = TweenService:Create(rock, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = target })
				tween:Play()
				tween.Completed:Wait()
				warning:Destroy()
				rock:Destroy()
				if not ctx.Folder.Parent then
					return
				end
				local explosion = Instance.new("Explosion")
				explosion.Position = target
				explosion.BlastRadius = radius
				explosion.BlastPressure = 0
				explosion.DestroyJointRadiusPercent = 0
				explosion.Parent = workspace
				Remotes.VFX:FireAllClients("Shockwave", { Position = target, Color = Color3.fromRGB(255, 120, 0), Size = radius * 3 })
				for p in ctx.Alive do
					local root = getRoot(p)
					local humanoid = getHumanoid(p)
					if root and humanoid and (root.Position - target).Magnitude <= radius then
						humanoid:TakeDamage(55)
						local away = root.Position - target
						Remotes.ClientCommand:FireClient(p, "fling", ((away.Magnitude > 0.1 and away.Unit or Vector3.yAxis) + Vector3.new(0, 1.5, 0)) * 50)
					end
				end
			end)
		end
		local accumulator = 0
		ctx:Loop(duration, function(dt)
			elapsed += dt
			accumulator += dt
			local interval = math.max(0.15, 0.7 - elapsed / duration * 0.55)
			while accumulator >= interval do
				accumulator -= interval
				meteor()
			end
			return ctx:AliveCount() == 0
		end)
	end,
	Rewards = function(ctx)
		return ctx:SurvivalRewards(MG.Games.MeteorShower)
	end,
}

Games.LavaRise = {
	Setup = function(ctx)
		local c = ctx.Center
		Part({ Name = "Floor", Size = Vector3.new(70, 2, 70), Position = c, Color = Color3.fromRGB(70, 70, 80), Material = Enum.Material.Slate, Parent = ctx.Folder })
		barrier(ctx.Folder, c, 70, 110)
		-- a spiral of platforms around a central pillar
		Part({ Name = "Pillar", Size = Vector3.new(8, 100, 8), Position = c + Vector3.new(0, 50, 0), Color = Color3.fromRGB(50, 50, 60), Material = Enum.Material.Basalt, Parent = ctx.Folder })
		for i = 1, 28 do
			local angle = i * math.rad(32)
			local height = 3 + i * 3.2
			Part({
				Name = "Step",
				Size = Vector3.new(9, 1.2, 9),
				Position = c + Vector3.new(math.cos(angle) * 16, height, math.sin(angle) * 16),
				Color = Color3.fromHSV((i / 28) % 1, 0.6, 1),
				Parent = ctx.Folder,
			})
		end
		Part({ Name = "Summit", Size = Vector3.new(14, 1.2, 14), Position = c + Vector3.new(0, 3 + 29 * 3.2, 0), Color = Color3.fromRGB(255, 210, 40), Material = Enum.Material.Neon, Parent = ctx.Folder })
		ctx.Lava = Part({
			Name = "Lava",
			Size = Vector3.new(76, 4, 76),
			Position = c - Vector3.new(0, 6, 0),
			Color = Color3.fromRGB(255, 80, 0),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = ctx.Folder,
		})
		BuildKit.Light(ctx.Lava, Color3.fromRGB(255, 110, 20), 60, 3)
		ctx.SpawnRadius = 25
		ctx.FallDepth = 1000 -- the lava decides
	end,
	Run = function(ctx)
		local info = MG.Games.LavaRise
		local lava = ctx.Lava :: BasePart
		local startY = lava.Position.Y
		local elapsed = 0
		ctx:Loop(info.Duration, function(dt)
			elapsed += dt
			local top = startY + elapsed * info.RiseSpeed
			lava.Position = Vector3.new(ctx.Center.X, top, ctx.Center.Z)
			for player in ctx.Alive do
				local root = getRoot(player)
				if root and root.Position.Y < top + lava.Size.Y / 2 + 1 then
					ctx:Eliminate(player, "🌋 The lava got you!")
				end
			end
			if ctx.StartCount > 1 then
				return ctx:AliveCount() <= 1
			end
			return ctx:AliveCount() == 0
		end)
	end,
	Rewards = function(ctx)
		return ctx:SurvivalRewards(MG.Games.LavaRise)
	end,
}

---------------------------------------------------------------------------
-- Round context
---------------------------------------------------------------------------
local Context = {}
Context.__index = Context

function Context:AliveCount()
	local n = 0
	for _ in self.Alive do
		n += 1
	end
	return n
end

function Context:Place(player: Player)
	local character = player.Character
	if not character then
		return
	end

	local r = self.SpawnRadius or 30
	local offset = Vector3.new(math.random(-r, r), 6, math.random(-r, r))
	character:PivotTo(CFrame.new(self.Center + offset))
	local root = getRoot(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

function Context:Eliminate(player: Player, reason: string?)
	if not self.Alive[player] then
		return
	end
	self.Alive[player] = nil
	self.EliminatedAt[player] = os.clock() - self.StartTime
	player:SetAttribute("InMinigame", nil)
	if player.Parent then
		Remotes.Notify:FireClient(player, { Text = reason or "You were eliminated!", Type = "error" })
		local humanoid = getHumanoid(player)
		if humanoid and humanoid.Health > 0 then
			S.TycoonService:TeleportHome(player)
		end
	end
end

-- Runs the round loop for `duration` seconds. `tick(dt)` returns true to end early.
-- `onFall(player)` returns true if the fall was handled (otherwise: eliminated)
function Context:Loop(duration: number, tick: (number) -> boolean, onFall: ((Player) -> boolean)?)
	local endTime = os.clock() + duration
	local lastBroadcast = 0
	local last = os.clock()
	while os.clock() < endTime do
		local now = os.clock()
		local dt = now - last
		last = now
		for player in self.Alive do
			local root = getRoot(player)
			local humanoid = getHumanoid(player)
			if not player.Parent then
				self.Alive[player] = nil
			elseif not root or not humanoid or humanoid.Health <= 0 then
				self:Eliminate(player, "You died!")
			elseif root.Position.Y < self.Center.Y - (self.FallDepth or 25) then
				if not (onFall and onFall(player)) then
					self:Eliminate(player, "You fell!")
				end
			end
		end
		if tick(dt) then
			break
		end
		if self:AliveCount() == 0 then
			break
		end
		if now - lastBroadcast >= 1 then
			lastBroadcast = now
			broadcast({ Phase = "Playing", Name = self.DisplayName, TimeLeft = math.ceil(endTime - now), Alive = self:AliveCount() })
		end
		task.wait(0.1)
	end
end

function Context:SurvivalRewards(info)
	local results = {}
	local survivors = {}
	for player in self.Alive do
		table.insert(survivors, player)
	end
	local duration = os.clock() - self.StartTime
	for player in self.Participants do
		local survived = self.Alive[player] ~= nil
		local time = survived and duration or (self.EliminatedAt[player] or 0)
		local fraction = math.clamp(time / math.max(duration, 1), 0, 1)
		local reward = math.floor(incomeReward(player, info.SurviveIncomeSeconds, info.SurviveMin) * (survived and 1 or fraction * 0.5))
		local winner = survived and #survivors <= 3
		if winner then
			reward += incomeReward(player, info.WinnerIncomeSeconds, info.WinnerMin)
		end
		table.insert(results, { Player = player, Score = string.format("%.0fs", time), Reward = reward, Winner = winner })
	end
	return results
end

---------------------------------------------------------------------------
function MinigameService:Init(services)
	S = services
	Remotes.MinigameJoin.OnServerEvent:Connect(function(player)
		if not acceptingJoins or joined[player] then
			return
		end
		if not S.DataService:IsLoaded(player) then
			return
		end
		joined[player] = true
		player:SetAttribute("MinigameJoined", true)
		Remotes.Notify:FireClient(player, { Text = "You joined the minigame! Get ready...", Type = "success" })
	end)
	Players.PlayerRemoving:Connect(function(player)
		joined[player] = nil
	end)
end

function MinigameService:ForceStart(name: string?): string
	if running then
		return "A minigame is already running"
	end
	local key
	if name then
		for k in Games do
			if k:lower() == name:lower() then
				key = k
			end
		end
		if not key then
			local names = {}
			for k in Games do
				table.insert(names, k)
			end
			table.sort(names)
			return "Unknown minigame. Options: " .. table.concat(names, ", ")
		end
	else
		local keys = {}
		for k in Games do
			table.insert(keys, k)
		end
		key = keys[math.random(1, #keys)]
	end
	forced = key
	return "Starting " .. MG.Games[key].DisplayName .. "!"
end

function MinigameService:Start()
	if not MG.Enabled then
		return
	end
	local keys = {}
	for k in Games do
		if MG.Games[k] then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	local lastKey
	while true do
		local t = MG.Intermission
		while t > 0 and not forced do
			broadcast({ Phase = "Intermission", TimeLeft = t })
			task.wait(1)
			t -= 1
		end
		local key = forced
		forced = nil
		if not key then
			repeat
				key = keys[math.random(1, #keys)]
			until key ~= lastKey or #keys == 1
		end
		lastKey = key
		local ok, err = pcall(self.RunGame, self, key)
		if not ok then
			warn("[Minigames] " .. tostring(err))
		end
		running = false
		acceptingJoins = false
		joined = {}
		for _, p in Players:GetPlayers() do
			p:SetAttribute("MinigameJoined", nil)
			p:SetAttribute("MinigameScore", nil)
		end
	end
end

function MinigameService:RunGame(key: string)
	running = true
	local info = MG.Games[key]
	local def = Games[key]

	-- join window
	joined = {}
	acceptingJoins = true
	for t = MG.JoinTime, 1, -1 do
		broadcast({ Phase = "Join", Game = key, Name = info.DisplayName, Description = info.Description, TimeLeft = t })
		task.wait(1)
	end
	acceptingJoins = false

	local participants = {}
	local count = 0
	for player in joined do
		local humanoid = getHumanoid(player)
		if player.Parent and humanoid and humanoid.Health > 0 then
			participants[player] = true
			count += 1
		end
	end
	if count < MG.MinPlayers then
		broadcast({ Phase = "Cancelled", Name = info.DisplayName, Text = "Not enough players joined." })
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "Minigame_" .. key
	folder.Parent = workspace

	local ctx = setmetatable({
		Key = key,
		DisplayName = info.DisplayName,
		Center = MG.ArenaCenter,
		Folder = folder,
		Participants = participants,
		Alive = table.clone(participants),
		Scores = {},
		EliminatedAt = {},
		StartCount = count,
		Started = false,
		StartTime = os.clock(),
	}, Context)

	local okSetup, setupErr = pcall(def.Setup, ctx)
	if not okSetup then
		warn("[Minigames] setup failed: " .. tostring(setupErr))
		folder:Destroy()
		return
	end

	-- stream the arena in for everyone (in parallel) before teleporting
	local pending = 0
	for player in participants do
		pending += 1
		task.spawn(function()
			pcall(player.RequestStreamAroundAsync, player, ctx.Center, 3)
			pending -= 1
		end)
	end
	local waitStart = os.clock()
	while pending > 0 and os.clock() - waitStart < 3.5 do
		task.wait(0.1)
	end

	-- send players in
	local deathConns = {}
	for player in participants do
		player:SetAttribute("InMinigame", true)
		player:SetAttribute("MinigameScore", 0)
		player:SetAttribute("ObbyStage", 0)
		ctx:Place(player)
		local humanoid = getHumanoid(player)
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			humanoid.UseJumpPower = true
			table.insert(deathConns, humanoid.Died:Connect(function()
				ctx:Eliminate(player, "You died!")
			end))
		end
	end
	Remotes.VFX:FireAllClients("Flash", {})

	for n = 3, 1, -1 do
		broadcast({ Phase = "Countdown", Name = info.DisplayName, Count = n })
		task.wait(1)
	end
	broadcast({ Phase = "Countdown", Name = info.DisplayName, Count = 0 })
	for player in ctx.Alive do
		local humanoid = getHumanoid(player)
		if humanoid then
			humanoid.WalkSpeed = S.MonetizationService:GetBaseSpeed(player)
			humanoid.JumpPower = 50
		end
	end
	ctx.Started = true
	ctx.StartTime = os.clock()

	local okRun, runErr = pcall(def.Run, ctx)
	if not okRun then
		warn("[Minigames] run failed: " .. tostring(runErr))
	end

	-- results
	local results = {}
	local okRewards, rewardResult = pcall(def.Rewards, ctx)
	if okRewards then
		results = rewardResult
	end
	table.sort(results, function(a, b)
		return a.Reward > b.Reward
	end)
	local summary = {}
	for _, r in results do
		local player = r.Player
		if player.Parent then
			if S.QuestService then
				S.QuestService:Progress(player, "Minigame", 1)
			end
			local data = S.DataService:Get(player)
			if data and r.Reward > 0 then
				S.DataService:AddCash(player, r.Reward, false)
				if r.Winner then
					data.MinigameWins += 1
				end
				Remotes.VFX:FireClient(player, r.Winner and "Confetti" or "CashBurst", { Amount = r.Reward })
			end
		end
		table.insert(summary, { Name = player.DisplayName, Score = r.Score, Reward = r.Reward, Winner = r.Winner })
	end
	broadcast({ Phase = "Results", Name = info.DisplayName, Results = summary })

	for _, conn in deathConns do
		conn:Disconnect()
	end
	for player in participants do
		if player.Parent then
			local wasAlive = player:GetAttribute("InMinigame")
			player:SetAttribute("InMinigame", nil)
			if wasAlive then
				S.TycoonService:TeleportHome(player)
			end
		end
	end
	task.delay(1, function()
		folder:Destroy()
	end)
	local winners = {}
	for _, r in summary do
		if r.Winner then
			table.insert(winners, r.Name)
		end
	end
	if #winners > 0 then
		Remotes.Announce:FireAllClients({
			Title = "🏆 " .. info.DisplayName .. " Winner" .. (#winners > 1 and "s" or ""),
			Text = table.concat(winners, ", ") .. " won " .. Util.Money(summary[1].Reward) .. "!",
			Color = Color3.fromRGB(170, 80, 255),
		})
	end
	task.wait(6)
end

return MinigameService
