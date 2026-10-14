--[[
	DisasterService - random server-wide disasters:
	  ☢️ Nuke      siren + countdown, hide in a bunker / shield dome or get
	               vaporized; the shockwave wrecks part of unshielded towers
	  ☄️ Meteors   meteors rain down; hits hurt players, wreck tower items and
	               leave cash crystals on the ground
	  🌪️ Tornado   a tornado sweeps across the map flinging players and
	               wrecking whatever it touches
	  🛸 UFO       UFOs abduct players and drop alien cash
	Wrecked items rebuild themselves after a while (or with Instant Repair).
	The Nuke Shield Dome (floor 2 special) protects a tower and everyone in it.

	Visuals are rendered on the clients (Disasters controller); the server only
	decides what happens and when.
]]
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Util = require(Shared.Util)
local Remotes = require(Shared.Remotes)
local BuildKit = require(script.Parent.BuildKit)

local DC = Config.Disasters

local DisasterService = {}
local S

local active: string? = nil
local queue = {}
local stopRequested = false
local folder: Folder
local rng = Random.new()

local KINDS = { "Nuke", "Meteors", "Tornado", "UFO", "Earthquake" }
for _, def in Config.ExtraDisasters do
	table.insert(KINDS, def.Name) -- (see "More disasters" below)
end
local TITLES = {
	Nuke = "☢️ NUKE INCOMING!",
	Meteors = "☄️ METEOR STORM!",
	Tornado = "🌪️ TORNADO WARNING!",
	UFO = "🛸 UFO INVASION!",
	Earthquake = "🌍 EARTHQUAKE!",
}

local function broadcast(state)
	Remotes.Disaster:FireAllClients(state)
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- players on the main map (not in the sky minigame arena)
local function mainMapPlayers(): { { Player: Player, Root: BasePart, Humanoid: Humanoid } }
	local list = {}
	for _, player in Players:GetPlayers() do
		local root, humanoid = getRoot(player), getHumanoid(player)
		if root and humanoid and humanoid.Health > 0 and not player:GetAttribute("InMinigame") and root.Position.Y < DC.MainMapMaxY then
			table.insert(list, { Player = player, Root = root, Humanoid = humanoid })
		end
	end
	return list
end

local function insideBox(position: Vector3, cf: CFrame, size: Vector3): boolean
	local p = cf:PointToObjectSpace(position)
	return math.abs(p.X) <= size.X / 2 and math.abs(p.Y) <= size.Y / 2 + 2 and math.abs(p.Z) <= size.Z / 2
end

function DisasterService:IsSheltered(position: Vector3): boolean
	local public = S.WorldBuilder.Shelter
	if public and insideBox(position, public.CFrame, public.Size) then
		return true
	end
	local boxes, spheres = S.TycoonService:GetShelters()
	for _, box in boxes do
		if insideBox(position, box.CFrame, box.Size) then
			return true
		end
	end
	for _, sphere in spheres do
		if (position - sphere.Center).Magnitude <= sphere.Radius then
			return true
		end
	end
	return false
end

-- sheltered (bunker, dome, roof) or wearing a personal shield
function DisasterService:IsProtected(player: Player, position: Vector3): boolean
	return self:IsSheltered(position) or (S.ShieldService ~= nil and S.ShieldService:IsShielded(player))
end

function DisasterService:GetShelterInfo()
	local boxes, spheres, doors = S.TycoonService:GetShelters()
	local public = S.WorldBuilder.Shelter
	if public then
		table.insert(boxes, 1, { CFrame = public.CFrame, Size = public.Size })
		table.insert(doors, 1, public.Door)
	end
	return { Boxes = boxes, Spheres = spheres, Doors = doors }
end

function DisasterService:IsActive(): boolean
	return active ~= nil
end

local function fling(player: Player, velocity: Vector3)
	Remotes.ClientCommand:FireClient(player, "fling", velocity)
end

local function rewardFor(player: Player, seconds: number, minimum: number): number
	local data = S.DataService:Get(S.DataService:GetWalletOwner(player))
	local rebirths = data and data.Rebirths or 0
	return math.max(minimum * (1 + rebirths), S.TycoonService:GetIncome(player) * seconds)
end

-- a collectible that pays a few seconds of income
local function spawnCollectible(position: Vector3, kind: string, seconds: number, minimum: number, anchored: boolean)
	local color = kind == "Crystal" and Color3.fromRGB(0, 255, 220) or Color3.fromRGB(120, 255, 80)
	local part = BuildKit.Part({
		Name = kind,
		Shape = kind == "Crystal" and Enum.PartType.Block or Enum.PartType.Ball,
		Size = kind == "Crystal" and Vector3.new(1.6, 3, 1.6) or Vector3.one * 2,
		CFrame = CFrame.new(position) * (kind == "Crystal" and CFrame.Angles(0, 0, math.rad(15)) or CFrame.identity),
		Color = color,
		Material = Enum.Material.Neon,
		Anchored = anchored,
		CanCollide = not anchored,
		Tags = anchored and { "Spin", "Bob" } or {},
		Parent = folder,
	})
	BuildKit.Light(part, color, 12, 2)
	BuildKit.Billboard(part, kind == "Crystal" and "💎 CASH CRYSTAL" or "👽 ALIEN CASH", { Size = UDim2.fromOffset(130, 24), Offset = Vector3.new(0, 2.5, 0), Color = color, MaxDistance = 70 })
	if not anchored then
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
	end
	local taken = false
	part.Touched:Connect(function(hit)
		if taken then
			return
		end
		local player = BuildKit.PlayerFromHit(hit)
		if player and BuildKit.IsNear(player, part) then
			taken = true
			local amount = rewardFor(player, seconds, minimum)
			S.DataService:AddCash(player, amount, false)
			Remotes.VFX:FireClient(player, "CoinPop", { Position = part.Position })
			Remotes.Notify:FireClient(player, { Text = (kind == "Crystal" and "💎 Cash crystal" or "👽 Alien cash") .. ": +" .. Util.Money(amount), Type = "success", Duration = 3 })
			part:Destroy()
		end
	end)
	task.delay(30, function()
		if part.Parent then
			part:Destroy()
		end
	end)
	return part
end

local function notifyPlot(plot, text: string, kind: string?)
	for _, member in { plot.Owner, plot.Partner } do
		if member then
			Remotes.Notify:FireClient(member, { Text = text, Type = kind or "error", Duration = 7 })
		end
	end
end

---------------------------------------------------------------------------
-- ☢️ Nuke
---------------------------------------------------------------------------
local handlers = {}

function handlers.Nuke(by: string?)
	local cfg = DC.Nuke
	local target = Vector3.new(rng:NextNumber(-140, 140), 0, rng:NextNumber(-140, 140))
	Remotes.Announce:FireAllClients({
		Title = TITLES.Nuke,
		Text = (by and (by .. " launched a nuke! ") or "") .. "Get inside a bunker in " .. cfg.Warning .. " seconds!",
		Color = Color3.fromRGB(255, 60, 40),
	})
	for t = cfg.Warning, 1, -1 do
		if stopRequested then
			return
		end
		broadcast({ Phase = "Warning", Kind = "Nuke", TimeLeft = t, Target = target, Shelters = DisasterService:GetShelterInfo(), By = by })
		task.wait(1)
	end
	broadcast({ Phase = "Impact", Kind = "Nuke", Target = target, ShockSpeed = cfg.ShockSpeed })

	local start = os.clock()
	local hitPlayers, hitPlots = {}, {}
	local maxRadius = 1500
	while not stopRequested do
		local radius = (os.clock() - start) * cfg.ShockSpeed
		for _, info in mainMapPlayers() do
			local player = info.Player
			if not hitPlayers[player] and (info.Root.Position - target).Magnitude <= radius then
				hitPlayers[player] = true
				if DisasterService:IsProtected(info.Player, info.Root.Position) then
					Remotes.Notify:FireClient(player, { Text = DisasterService:IsSheltered(info.Root.Position) and "🛡️ You survived the nuke! Smart move." or "🛡️ Your shield absorbed the nuke!", Type = "success" })
				else
					local away = info.Root.Position - target
					local dir = away.Magnitude > 1 and away.Unit or Vector3.new(0, 0, 1)
					fling(player, dir * 120 + Vector3.new(0, 80, 0))
					Remotes.ClientCommand:FireClient(player, "vaporized")
					info.Humanoid:TakeDamage(1e9)
				end
			end
		end
		for _, plot in S.TycoonService:GetPlots() do
			if plot.Owner and not hitPlots[plot] then
				local d = (plot.TowerCF.Position - target) * Vector3.new(1, 0, 1)
				if d.Magnitude <= radius then
					hitPlots[plot] = true
					if S.TycoonService:IsShielded(plot) then
						Remotes.VFX:FireAllClients("ShieldHit", { Center = plot.ShieldCenter, Radius = plot.ShieldRadius })
						notifyPlot(plot, "🛡️ Your Nuke Shield Dome protected your tower!", "success")
					else
						local wrecked = S.TycoonService:KnockOutFraction(plot, cfg.KnockoutFraction, cfg.KnockoutSeconds)
						if wrecked > 0 then
							notifyPlot(plot, "☢️ The nuke wrecked " .. wrecked .. " upgrades! They rebuild in " .. Util.FormatTime(cfg.KnockoutSeconds) .. " (or buy Instant Repair). Get the Nuke Shield on floor 2!")
						end
					end
				end
			end
		end
		if radius > maxRadius then
			break
		end
		task.wait(0.1)
	end
	broadcast({ Phase = "Aftermath", Kind = "Nuke", Duration = 25 })
	task.wait(4)
end

---------------------------------------------------------------------------
-- ☄️ Meteors
---------------------------------------------------------------------------
local function meteorImpact(target: Vector3, cfg)
	local plot = S.TycoonService:PlotAt(target)
	local shielded = plot ~= nil and S.TycoonService:IsShielded(plot)
	local impact = target
	if plot and shielded then
		local c, r = plot.ShieldCenter, plot.ShieldRadius
		local dx, dz = target.X - c.X, target.Z - c.Z
		impact = Vector3.new(target.X, c.Y + math.sqrt(math.max(r * r - dx * dx - dz * dz, 0)), target.Z)
	elseif plot then
		-- hits the top of the tower
		local floors = 0
		for f = 1, Config.Tycoon.Floors do
			if S.TycoonService:IsFloorUnlocked(plot, f) then
				floors = f
			end
		end
		impact = Vector3.new(target.X, plot.TowerCF.Position.Y + floors * Config.Tycoon.FloorHeight, target.Z)
	else
		-- find the ground (terrain, trees, buildings)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = { folder }
		for _, p in Players:GetPlayers() do
			if p.Character then
				table.insert(exclude, p.Character)
			end
		end
		params.FilterDescendantsInstances = exclude
		local result = workspace:Raycast(Vector3.new(target.X, 450, target.Z), Vector3.new(0, -900, 0), params)
		if result then
			impact = result.Position
		end
	end
	broadcast({ Phase = "Meteor", Kind = "Meteors", Target = impact, Delay = 1.4, Radius = cfg.Radius, Shield = shielded })
	task.delay(1.4, function()
		if stopRequested then
			return
		end
		for _, info in mainMapPlayers() do
			local d = (info.Root.Position - impact).Magnitude
			if d <= cfg.Radius and not DisasterService:IsProtected(info.Player, info.Root.Position) then
				info.Humanoid:TakeDamage(cfg.Damage)
				local away = info.Root.Position - impact
				fling(info.Player, (away.Magnitude > 0.1 and away.Unit or Vector3.yAxis) * 60 + Vector3.new(0, 50, 0))
			end
		end
		if plot and not shielded then
			local wrecked = S.TycoonService:KnockOutNear(plot, impact, 20, 2, cfg.KnockoutSeconds)
			if wrecked > 0 then
				notifyPlot(plot, "☄️ A meteor wrecked " .. wrecked .. " of your upgrades!")
			end
		elseif not plot and rng:NextNumber() < cfg.CrystalChance and impact.Y < 50 then
			spawnCollectible(impact + Vector3.new(0, 2, 0), "Crystal", cfg.CrystalIncomeSeconds, 1000, true)
		end
	end)
end

function handlers.Meteors(by: string?)
	local cfg = DC.Meteors
	Remotes.Announce:FireAllClients({
		Title = TITLES.Meteors,
		Text = (by and (by .. " called a meteor storm! ") or "") .. "Dodge the red circles and grab the cash crystals!",
		Color = Color3.fromRGB(255, 120, 30),
	})
	local endTime = os.clock() + cfg.Duration
	local lastTick = 0
	while os.clock() < endTime and not stopRequested do
		local now = os.clock()
		if now - lastTick >= 1 then
			lastTick = now
			broadcast({ Phase = "Active", Kind = "Meteors", TimeLeft = math.ceil(endTime - now) })
		end
		local players = mainMapPlayers()
		local target
		if #players > 0 and rng:NextNumber() < 0.45 then
			local pick = players[rng:NextInteger(1, #players)]
			target = pick.Root.Position + Vector3.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-12, 12))
			target = Vector3.new(target.X, 0, target.Z)
		else
			local a = rng:NextNumber(0, math.pi * 2)
			local r = math.sqrt(rng:NextNumber()) * 650
			target = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		end
		meteorImpact(target, cfg)
		task.wait(cfg.Interval * rng:NextNumber(0.7, 1.3))
	end
	task.wait(2)
end

---------------------------------------------------------------------------
-- 🌪️ Tornado
---------------------------------------------------------------------------
local function persistentCore(name: string, tag: string, position: Vector3)
	local model = Instance.new("Model")
	model.Name = name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local core = BuildKit.Part({ Name = "Core", Size = Vector3.one * 2, Position = position, Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, Parent = model })
	model.PrimaryPart = core
	core:AddTag(tag)
	model.Parent = folder
	return model, core
end

function handlers.Tornado(by: string?)
	local cfg = DC.Tornado
	Remotes.Announce:FireAllClients({
		Title = TITLES.Tornado,
		Text = (by and (by .. " summoned a tornado! ") or "") .. "Stay away from it - or hide under your Nuke Shield!",
		Color = Color3.fromRGB(160, 170, 190),
	})
	local a = rng:NextNumber(0, math.pi * 2)
	local startPos = Vector3.new(math.cos(a) * 700, 0, math.sin(a) * 700)
	local mid = Vector3.new(rng:NextNumber(-150, 150), 0, rng:NextNumber(-150, 150))
	local b = a + math.pi + rng:NextNumber(-0.6, 0.6)
	local endPos = Vector3.new(math.cos(b) * 700, 0, math.sin(b) * 700)
	local total = (mid - startPos).Magnitude + (endPos - mid).Magnitude

	local model, core = persistentCore("Tornado", "Tornado", startPos)
	core:SetAttribute("Radius", cfg.Radius)
	local startTime = os.clock()
	local lastEffect, lastWreck, lastTick = 0, 0, 0
	local wreckedPlots = {}
	while not stopRequested do
		local elapsed = os.clock() - startTime
		if elapsed >= cfg.Duration then
			break
		end
		local dist = elapsed / cfg.Duration * total
		local pos
		local first = (mid - startPos).Magnitude
		if dist <= first then
			pos = startPos:Lerp(mid, dist / first)
		else
			pos = mid:Lerp(endPos, (dist - first) / (total - first))
		end
		pos += Vector3.new(math.sin(elapsed * 1.7) * 6, 0, math.cos(elapsed * 1.3) * 6)
		core.CFrame = CFrame.new(pos)
		local now = os.clock()
		if now - lastTick >= 1 then
			lastTick = now
			broadcast({ Phase = "Active", Kind = "Tornado", TimeLeft = math.ceil(cfg.Duration - elapsed) })
		end
		if now - lastEffect >= 0.25 then
			lastEffect = now
			for _, info in mainMapPlayers() do
				local flat = (info.Root.Position - pos) * Vector3.new(1, 0, 1)
				if flat.Magnitude <= cfg.Radius and info.Root.Position.Y < 220 and not DisasterService:IsProtected(info.Player, info.Root.Position) then
					Remotes.ClientCommand:FireClient(info.Player, "tornado", pos)
					info.Humanoid:TakeDamage(3)
				end
			end
		end
		if now - lastWreck >= 0.5 then
			lastWreck = now
			for _, plot in S.TycoonService:GetPlots() do
				if plot.Owner and not S.TycoonService:IsShielded(plot) then
					local flat = (plot.TowerCF.Position - pos) * Vector3.new(1, 0, 1)
					if flat.Magnitude < 90 then
						local wrecked = S.TycoonService:KnockOutNear(plot, pos, cfg.Radius, 3, cfg.KnockoutSeconds, true)
						if wrecked > 0 and not wreckedPlots[plot] then
							wreckedPlots[plot] = true
							notifyPlot(plot, "🌪️ The tornado is tearing through your tower!")
						end
					end
				end
			end
		end
		task.wait(0.1)
	end
	model:Destroy()
end

---------------------------------------------------------------------------
-- 🛸 UFO
---------------------------------------------------------------------------
function handlers.UFO(by: string?)
	local cfg = DC.UFO
	Remotes.Announce:FireAllClients({
		Title = TITLES.UFO,
		Text = (by and (by .. " called the aliens! ") or "") .. "Watch out for tractor beams - and grab the alien cash!",
		Color = Color3.fromRGB(120, 255, 80),
	})
	local ufos = {}
	for i = 1, cfg.Count do
		local a = i / cfg.Count * math.pi * 2
		local start = Vector3.new(math.cos(a) * 600, 120, math.sin(a) * 600)
		local model, core = persistentCore("UFO" .. i, "UFO", start)
		core:SetAttribute("BeamOn", false)
		table.insert(ufos, { Model = model, Core = core, Pos = start, Target = Vector3.new(rng:NextNumber(-400, 400), 120, rng:NextNumber(-400, 400)), NextAbduct = os.clock() + rng:NextNumber(2, cfg.AbductEvery), Busy = false })
	end
	local endTime = os.clock() + cfg.Duration
	local lastCash, lastTick = 0, 0
	local last = os.clock()
	while os.clock() < endTime and not stopRequested do
		local now = os.clock()
		local dt = now - last
		last = now
		if now - lastTick >= 1 then
			lastTick = now
			broadcast({ Phase = "Active", Kind = "UFO", TimeLeft = math.ceil(endTime - now) })
		end
		local players = mainMapPlayers()
		for _, ufo in ufos do
			if not ufo.Busy then
				local delta = ufo.Target - ufo.Pos
				if delta.Magnitude < 5 then
					ufo.Target = Vector3.new(rng:NextNumber(-500, 500), 120, rng:NextNumber(-500, 500))
				else
					ufo.Pos += delta.Unit * math.min(delta.Magnitude, 45 * dt)
				end
				-- abduct the nearest exposed player
				if now >= ufo.NextAbduct then
					ufo.NextAbduct = now + cfg.AbductEvery
					local best, bestD = nil, 180
					for _, info in players do
						local flat = (info.Root.Position - ufo.Pos) * Vector3.new(1, 0, 1)
						if flat.Magnitude < bestD and not DisasterService:IsProtected(info.Player, info.Root.Position) then
							best, bestD = info, flat.Magnitude
						end
					end
					if best then
						ufo.Busy = true
						local victim = best
						task.spawn(function()
							-- fly over the victim, beam them up, drop them
							local hover = victim.Root.Position + Vector3.new(0, 60, 0)
							local t0 = os.clock()
							local from = ufo.Pos
							while os.clock() - t0 < 1.2 do
								ufo.Pos = from:Lerp(hover, (os.clock() - t0) / 1.2)
								ufo.Core.CFrame = CFrame.new(ufo.Pos)
								task.wait()
							end
							ufo.Pos = hover
							ufo.Core.CFrame = CFrame.new(hover)
							ufo.Core:SetAttribute("BeamOn", true)
							if victim.Player.Parent then
								Remotes.ClientCommand:FireClient(victim.Player, "abduct", hover - Vector3.new(0, 6, 0), 2.5)
							end
							task.wait(2.8)
							ufo.Core:SetAttribute("BeamOn", false)
							spawnCollectible(hover - Vector3.new(0, 8, 0), "AlienCash", cfg.CashIncomeSeconds, 500, false)
							ufo.Busy = false
						end)
					end
				end
				ufo.Core.CFrame = CFrame.new(ufo.Pos)
			end
		end
		if now - lastCash >= cfg.CashEvery then
			lastCash = now
			local ufo = ufos[rng:NextInteger(1, #ufos)]
			if not ufo.Busy then
				spawnCollectible(ufo.Pos - Vector3.new(0, 8, 0), "AlienCash", cfg.CashIncomeSeconds, 500, false)
			end
		end
		task.wait(0.05)
	end
	for _, ufo in ufos do
		ufo.Model:Destroy()
	end
end

---------------------------------------------------------------------------
-- 🌍 Earthquake
---------------------------------------------------------------------------
local function crack(position: Vector3, length: number, angle: number)
	local cf = CFrame.new(position) * CFrame.Angles(0, angle, 0)
	local model = Instance.new("Model")
	model.Name = "Crack"
	BuildKit.Part({ Name = "Rim", Size = Vector3.new(2.2, 0.4, length), CFrame = cf, Color = Color3.fromRGB(45, 35, 28), Material = Enum.Material.Slate, CanCollide = false, CanTouch = false, CanQuery = false, Parent = model })
	BuildKit.Part({ Name = "Glow", Size = Vector3.new(0.8, 0.5, length - 1), CFrame = cf, Color = Color3.fromRGB(255, 110, 20), Material = Enum.Material.Neon, CanCollide = false, CanTouch = false, CanQuery = false, Parent = model })
	model.Parent = folder
	return model
end

function handlers.Earthquake(by: string?)
	local cfg = DC.Earthquake
	Remotes.Announce:FireAllClients({
		Title = TITLES.Earthquake,
		Text = (by and (by .. " shook the ground! ") or "") .. "Hold on tight - and grab the cash geodes it digs up!",
		Color = Color3.fromRGB(210, 150, 90),
	})
	for _ = 1, cfg.GeodeCount do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(40, 220)
		spawnCollectible(Vector3.new(math.cos(a) * r, 2.5, math.sin(a) * r), "Crystal", cfg.GeodeIncomeSeconds, 750, true)
	end
	local cracks = {}
	local notified = {}
	local endTime = os.clock() + cfg.Duration
	local nextShock = os.clock() + 1
	local lastTick = 0
	while os.clock() < endTime and not stopRequested do
		local now = os.clock()
		if now - lastTick >= 1 then
			lastTick = now
			broadcast({ Phase = "Active", Kind = "Earthquake", TimeLeft = math.ceil(endTime - now) })
		end
		if now >= nextShock then
			nextShock = now + cfg.WaveEvery
			broadcast({ Phase = "Shock", Kind = "Earthquake", Intensity = rng:NextNumber(0.6, 1) })
			for _, info in mainMapPlayers() do
				if not DisasterService:IsProtected(info.Player, info.Root.Position) then
					info.Humanoid:TakeDamage(cfg.Damage)
					fling(info.Player, Vector3.new(rng:NextNumber(-12, 12), 28, rng:NextNumber(-12, 12)))
				end
			end
			for _, plot in S.TycoonService:GetPlots() do
				if plot.Owner and not S.TycoonService:IsShielded(plot) then
					local wrecked = S.TycoonService:KnockOutFraction(plot, cfg.KnockoutFraction, cfg.KnockoutSeconds)
					if wrecked > 0 and not notified[plot] then
						notified[plot] = true
						notifyPlot(plot, "🌍 The earthquake is shaking your tower apart! Wrecked upgrades rebuild by themselves.")
					end
				end
			end
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(20, 200)
			table.insert(cracks, crack(Vector3.new(math.cos(a) * r, 0.6, math.sin(a) * r), rng:NextNumber(18, 45), rng:NextNumber(0, math.pi)))
		end
		task.wait(0.1)
	end
	task.wait(1)
	for _, model in cracks do
		model:Destroy()
	end
end

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- More disasters (Config.ExtraDisasters): Rain, Wave, Zone and Status kinds
---------------------------------------------------------------------------
local spawnedFx: { Instance } = {}
local slowedPlayers: { [Player]: boolean } = {}

local function track<T>(instance: T & Instance): T & Instance
	table.insert(spawnedFx, instance)
	return instance
end

local function cleanupFx()
	for _, instance in spawnedFx do
		instance:Destroy()
	end
	table.clear(spawnedFx)
end

-- slows a player (factor) or gives their normal speed back (nil)
local function setSlow(player: Player, factor: number?)
	local humanoid = getHumanoid(player)
	if not humanoid then
		slowedPlayers[player] = nil
		return
	end
	if factor then
		humanoid.WalkSpeed = S.MonetizationService:GetBaseSpeed(player) * factor
		slowedPlayers[player] = true
	elseif slowedPlayers[player] then
		humanoid.WalkSpeed = S.MonetizationService:GetBaseSpeed(player)
		slowedPlayers[player] = nil
	end
end

-- a flat glowing circle on the ground
local function marker(position: Vector3, radius: number, color: Color3, seconds: number): BasePart
	local disc = BuildKit.Part({
		Name = "XD_Marker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		CFrame = CFrame.new(position.X, 0.5, position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Parent = folder,
	})
	Debris:AddItem(disc, seconds)
	return track(disc)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function hurt(info, damage: number, awayFrom: Vector3?, knock: number?)
	info.Humanoid:TakeDamage(damage)
	if knock and awayFrom then
		local away = info.Root.Position - awayFrom
		local direction = away.Magnitude > 0.1 and away.Unit or Vector3.yAxis
		fling(info.Player, direction * knock + Vector3.new(0, knock * 0.7, 0))
	end
end

-- knocks out part of the towers near `position` (unless their dome protects them)
local function wreckNear(def, position: Vector3, notified)
	for _, plot in S.TycoonService:GetPlots() do
		if plot.Owner and flatDistance(plot.TowerCF.Position, position) <= def.WreckRadius then
			if S.TycoonService:IsShielded(plot) then
				if not notified[plot] then
					notified[plot] = true
					Remotes.VFX:FireAllClients("ShieldHit", { Center = plot.ShieldCenter, Radius = plot.ShieldRadius })
					notifyPlot(plot, "🛡️ Your Nuke Shield Dome protected your tower from the " .. def.Name .. "!", "success")
				end
			else
				local wrecked = S.TycoonService:KnockOutFraction(plot, def.Wreck, def.KnockoutSeconds)
				if wrecked > 0 and not notified[plot] then
					notified[plot] = true
					notifyPlot(plot, def.Icon .. " The " .. def.Name .. " is wrecking your tower! Wrecked upgrades rebuild by themselves.")
				end
			end
		end
	end
end

-- Rain: a burning puddle that keeps hurting for a few seconds
local function spawnPatch(def, position: Vector3)
	local patch = def.Patch
	local disc = marker(position, patch.Radius, def.Color, patch.Seconds)
	disc.Transparency = 0.3
	task.spawn(function()
		local untilTime = os.clock() + patch.Seconds
		while os.clock() < untilTime and not stopRequested and disc.Parent do
			for _, info in mainMapPlayers() do
				if info.Root.Position.Y < 8 and flatDistance(info.Root.Position, position) <= patch.Radius and not DisasterService:IsProtected(info.Player, info.Root.Position) then
					info.Humanoid:TakeDamage(patch.Damage * 0.5)
				end
			end
			task.wait(0.5)
		end
	end)
end

local function rainImpact(def, position: Vector3, notified)
	Remotes.VFX:FireAllClients("Shockwave", { Position = position + Vector3.new(0, 2, 0), Color = def.Color, Size = def.Radius * 2.5 })
	if def.Shake then
		broadcast({ Phase = "Shock", Kind = def.Name, Intensity = def.Shake })
	end
	for _, info in mainMapPlayers() do
		if (info.Root.Position - position).Magnitude <= def.Radius and not DisasterService:IsProtected(info.Player, info.Root.Position) then
			hurt(info, def.Damage, position, def.Knock)
		end
	end
	if def.Wreck then
		wreckNear(def, position, notified)
	end
	if def.Patch then
		spawnPatch(def, position)
	end
end

local function rainDrop(def, target: Vector3, notified)
	marker(target, def.Radius, def.Color, def.FallTime + 0.3)
	if def.Bolt then
		task.wait(def.FallTime)
		if stopRequested then
			return
		end
		local bolt = track(BuildKit.Part({ Name = "XD_Bolt", Size = Vector3.new(1.4, 130, 1.4), Position = target + Vector3.new(0, 65, 0), Color = Color3.fromRGB(255, 255, 220), Material = Enum.Material.Neon, CanCollide = false, CanTouch = false, CanQuery = false, Parent = folder }))
		Debris:AddItem(bolt, 0.3)
	else
		local size = def.DropSize or 3
		local drop = track(BuildKit.Part({ Name = "XD_Drop", Shape = Enum.PartType.Ball, Size = Vector3.one * size, Position = target + Vector3.new(0, 130, 0), Color = def.Color, Material = Enum.Material.Neon, CanCollide = false, CanTouch = false, CanQuery = false, Parent = folder }))
		TweenService:Create(drop, TweenInfo.new(def.FallTime, Enum.EasingStyle.Linear), { Position = target + Vector3.new(0, size / 2, 0) }):Play()
		Debris:AddItem(drop, def.FallTime + 0.1)
		task.wait(def.FallTime)
		if stopRequested then
			return
		end
	end
	rainImpact(def, target, notified)
end

local function runRain(def, notified)
	local endTime = os.clock() + def.Duration
	local nextWave = os.clock() + 1
	local lastTick = 0
	while os.clock() < endTime and not stopRequested do
		local now = os.clock()
		if now - lastTick >= 1 then
			lastTick = now
			broadcast({ Phase = "Active", Kind = def.Name, TimeLeft = math.ceil(endTime - now), Tint = def.Tint })
		end
		if now >= nextWave then
			nextWave = now + def.Interval
			local players = mainMapPlayers()
			if #players > 0 then
				for _ = 1, def.PerWave do
					local root = players[rng:NextInteger(1, #players)].Root.Position
					local angle, distance = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, def.Spread)
					task.spawn(rainDrop, def, Vector3.new(root.X + math.cos(angle) * distance, 0.5, root.Z + math.sin(angle) * distance), notified)
				end
			end
		end
		task.wait(0.1)
	end
	task.wait(def.FallTime + 0.3) -- the last drops land
end

-- Wave: a wall sweeps across the whole map
local function runWave(def, notified)
	local reach = 1100
	for wave = 1, def.Waves do
		if stopRequested then
			return
		end
		local alongX = rng:NextInteger(1, 2) == 1
		local sign = rng:NextInteger(0, 1) == 0 and -1 or 1
		local y = def.Height / 2
		local from = alongX and Vector3.new(-sign * reach, y, 0) or Vector3.new(0, y, -sign * reach)
		local to = alongX and Vector3.new(sign * reach, y, 0) or Vector3.new(0, y, sign * reach)
		local size = alongX and Vector3.new(def.Thickness, def.Height, def.Width) or Vector3.new(def.Width, def.Height, def.Thickness)
		local wall = track(BuildKit.Part({ Name = "XD_Wall", Size = size, Position = from, Color = def.Color, Material = Enum.Material[def.Material], Transparency = def.WallTransparency, CanCollide = false, CanTouch = false, CanQuery = false, Parent = folder }))
		local side = alongX and (sign < 0 and "west" or "east") or (sign < 0 and "north" or "south")
		Remotes.Announce:FireAllClients({ Title = def.Icon .. " WAVE " .. wave .. "/" .. def.Waves, Text = "It comes from the " .. side .. " - get above " .. def.SafeY .. " studs or into cover!", Color = def.Color })
		for t = def.Warning, 1, -1 do
			if stopRequested then
				return
			end
			broadcast({ Phase = "Active", Kind = def.Name, TimeLeft = t, Tint = def.Tint })
			task.wait(1)
		end
		local travel = 2 * reach / def.Speed
		TweenService:Create(wall, TweenInfo.new(travel, Enum.EasingStyle.Linear), { Position = to }):Play()
		local hitPlayers, hitPlots = {}, {}
		local started = os.clock()
		while os.clock() - started < travel and not stopRequested do
			local cf = wall.CFrame
			for _, info in mainMapPlayers() do
				if not hitPlayers[info.Player] and info.Root.Position.Y < def.SafeY and insideBox(info.Root.Position, cf, wall.Size) then
					hitPlayers[info.Player] = true
					if not DisasterService:IsProtected(info.Player, info.Root.Position) then
						hurt(info, def.Damage, cf.Position, def.Knock)
					end
				end
			end
			for _, plot in S.TycoonService:GetPlots() do
				local delta = plot.TowerCF.Position - cf.Position
				local along = alongX and math.abs(delta.X) or math.abs(delta.Z)
				if plot.Owner and not hitPlots[plot] and along <= def.Thickness / 2 + 25 then
					hitPlots[plot] = true
					wreckNear({ Name = def.Name, Icon = def.Icon, Wreck = def.Wreck, WreckRadius = 1e9, KnockoutSeconds = def.KnockoutSeconds }, plot.TowerCF.Position, notified)
				end
			end
			task.wait(0.1)
		end
		wall:Destroy()
		if wave < def.Waves and not stopRequested then
			task.wait(def.Gap)
		end
	end
end

-- Zone: danger circles that hurt / slow / pull whoever stands in them
local function runZones(def)
	local zones = {}
	local endTime = os.clock() + def.Duration
	local nextSpawn = os.clock() + 1
	local lastTick, lastCheck = 0, os.clock()
	while (os.clock() < endTime or #zones > 0) and not stopRequested do
		local now = os.clock()
		if now - lastTick >= 1 then
			lastTick = now
			broadcast({ Phase = "Active", Kind = def.Name, TimeLeft = math.max(0, math.ceil(endTime - now)), Tint = def.Tint })
		end
		if now < endTime and now >= nextSpawn then
			nextSpawn = now + def.Interval
			local players = mainMapPlayers()
			if #players > 0 then
				for _ = 1, def.Count do
					local root = players[rng:NextInteger(1, #players)].Root.Position
					local angle, distance = rng:NextNumber(0, math.pi * 2), rng:NextNumber(0, 30)
					local position = Vector3.new(root.X + math.cos(angle) * distance, 0, root.Z + math.sin(angle) * distance)
					table.insert(zones, { Position = position, Part = marker(position, def.Radius, Color3.fromRGB(255, 255, 255), def.Warning + def.Lifetime + 1), Born = now, Active = false })
				end
			end
		end
		-- warning -> active -> gone
		for i = #zones, 1, -1 do
			local zone = zones[i]
			if not zone.Active and now - zone.Born >= def.Warning then
				zone.Active = true
				zone.Part.Color = def.Color
				zone.Part.Transparency = 0.2
			elseif now - zone.Born >= def.Warning + def.Lifetime then
				zone.Part:Destroy()
				table.remove(zones, i)
			end
		end
		-- the effects, twice a second
		if now - lastCheck >= 0.5 then
			local dt = now - lastCheck
			lastCheck = now
			for _, info in mainMapPlayers() do
				local inside
				for _, zone in zones do
					if zone.Active and info.Root.Position.Y < 12 and flatDistance(info.Root.Position, zone.Position) <= def.Radius then
						inside = zone
					end
				end
				if inside and not DisasterService:IsProtected(info.Player, info.Root.Position) then
					if def.Damage > 0 then
						info.Humanoid:TakeDamage(def.Damage * dt)
					end
					if def.Slow then
						setSlow(info.Player, def.Slow)
					end
					if def.Pull then
						local toCenter = Vector3.new(inside.Position.X - info.Root.Position.X, 0, inside.Position.Z - info.Root.Position.Z)
						if toCenter.Magnitude > 1 then
							fling(info.Player, toCenter.Unit * def.Pull)
						end
					end
				else
					setSlow(info.Player, nil)
				end
			end
		end
		task.wait(0.1)
	end
end

-- Status: everyone outside cover suffers
local function runStatus(def)
	local endTime = os.clock() + def.Duration
	local lastTick = 0
	local nextGravity, gravityIndex = os.clock(), 0
	while os.clock() < endTime and not stopRequested do
		local now = os.clock()
		if def.Gravities and now >= nextGravity then
			gravityIndex = gravityIndex % #def.Gravities + 1
			workspace.Gravity = def.Gravities[gravityIndex]
			nextGravity = now + def.GravityEvery
		end
		if now - lastTick >= 1 then
			lastTick = now
			broadcast({ Phase = "Active", Kind = def.Name, TimeLeft = math.ceil(endTime - now), Tint = def.Tint })
			for _, info in mainMapPlayers() do
				if DisasterService:IsProtected(info.Player, info.Root.Position) then
					setSlow(info.Player, nil)
				else
					if def.Damage then
						info.Humanoid:TakeDamage(def.Damage)
					end
					if def.Slow then
						setSlow(info.Player, def.Slow)
					end
					if def.Push then
						fling(info.Player, Vector3.new(rng:NextNumber(-1, 1), 0.1, rng:NextNumber(-1, 1)).Unit * def.Push)
					end
				end
			end
		end
		task.wait(0.1)
	end
end

for _, def in Config.ExtraDisasters do
	handlers[def.Name] = function(by: string?)
		local originalGravity = workspace.Gravity
		Remotes.Announce:FireAllClients({ Title = def.Title, Text = (by and (by .. " triggered it! ") or "") .. def.Intro, Color = def.Color })
		local notified = {}
		local ok, err = pcall(function()
			if def.Type == "Rain" then
				runRain(def, notified)
			elseif def.Type == "Wave" then
				runWave(def, notified)
			elseif def.Type == "Zone" then
				runZones(def)
			else
				runStatus(def)
			end
		end)
		-- always put everything back
		workspace.Gravity = originalGravity
		for player in slowedPlayers do
			setSlow(player, nil)
		end
		task.wait(1)
		cleanupFx()
		if not ok then
			error(err, 0)
		end
	end
end

---------------------------------------------------------------------------
function DisasterService:Init(services)
	S = services
	folder = Instance.new("Folder")
	folder.Name = "Disasters"
	folder.Parent = workspace
end

function DisasterService:_run(kind: string, by: string?)
	active = kind
	stopRequested = false
	workspace:SetAttribute("Disaster", kind)
	-- who's out there (survivors = same character, still alive at the end)
	local present = {}
	for _, info in mainMapPlayers() do
		present[info.Player] = info.Player.Character
	end
	local ok, err = pcall(handlers[kind], by)
	if not ok then
		warn("[Disasters] " .. kind .. " failed: " .. tostring(err))
	end
	for player, character in present do
		local humanoid = getHumanoid(player)
		if player.Parent and player.Character == character and humanoid and humanoid.Health > 0 and S.QuestService then
			S.QuestService:Progress(player, "Survive", 1)
		end
	end
	broadcast({ Phase = "End", Kind = kind })
	workspace:SetAttribute("Disaster", nil)
	active = nil
	stopRequested = false
end

function DisasterService:Start()
	if not DC.Enabled then
		-- still allow forced (bought / admin) disasters
		while true do
			if #queue > 0 then
				local job = table.remove(queue, 1)
				self:_run(job.Kind, job.By)
			end
			task.wait(1)
		end
	end
	local nextTime = os.clock() + DC.FirstDelay
	while true do
		if #queue > 0 then
			local job = table.remove(queue, 1)
			self:_run(job.Kind, job.By)
			nextTime = math.max(nextTime, os.clock() + 60)
		elseif os.clock() >= nextTime then
			local total = 0
			for _, kind in KINDS do
				total += DC[kind].Weight
			end
			local roll = rng:NextNumber(0, total)
			local pick = KINDS[1]
			for _, kind in KINDS do
				roll -= DC[kind].Weight
				if roll <= 0 then
					pick = kind
					break
				end
			end
			self:_run(pick, nil)
			nextTime = os.clock() + rng:NextNumber(DC.MinInterval, DC.MaxInterval)
		end
		task.wait(1)
	end
end

-- start (or queue) a disaster. by = name shown in the announcement
function DisasterService:Trigger(kind: string, by: string?): string
	local key
	for _, k in KINDS do
		if k:lower() == tostring(kind):lower() then
			key = k
		end
	end
	if not key then
		return "Unknown disaster. Options: " .. table.concat(KINDS, ", ")
	end
	table.insert(queue, { Kind = key, By = by })
	if active then
		return key .. " queued (a " .. active .. " is happening right now)"
	end
	return key .. " incoming!"
end

function DisasterService:ListKinds(): string
	return table.concat(KINDS, ", ")
end

function DisasterService:Stop(): string
	if not active then
		return "No disaster is active"
	end
	stopRequested = true
	queue = {}
	return "Stopping " .. tostring(active)
end

return DisasterService
