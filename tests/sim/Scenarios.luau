--[[
	Gameplay scenarios. Each one boots a fresh server (+ optionally a local
	client) from the built place file and plays the game like a person would:
	touching buttons, firing remotes, clicking UI, surviving disasters...
	Any script error, failed check or unexpected warning fails the scenario.
]]
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Scenarios = {}

-- warnings that are expected in a Studio-like run
local STUDIO_WARNINGS = { "DataStores unavailable", "Could not load data" }

local function add(def)
	def.AllowedWarnings = def.AllowedWarnings or STUDIO_WARNINGS
	table.insert(Scenarios, def)
end

local function finite(n): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function count(map): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- cheapest item the player can buy right now
local function cheapestAvailable(T, data)
	local TycoonItems = T.Shared("TycoonItems")
	local best
	for _, item in TycoonItems.List do
		if item.Kind ~= "Secret" and TycoonItems.IsAvailable(item, data.Purchased) then
			if not best or item.Cost < best.Cost then
				best = item
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
add({
	Name = "boot",
	Run = function(T, place)
		local game, player = T.Boot(place)
		T.Wait(8)
		T.Check(player:GetAttribute("DataLoaded"), "player data loaded")
		T.Check(player:GetAttribute("Plot") ~= nil, "player got a plot")
		T.Check(player:GetAttribute("LoadingDone"), "loading screen finished")
		T.Check((player:GetAttribute("Cash") or 0) > 0, "player has starting cash")
		local gui = player.PlayerGui:FindFirstChild("MegaTycoonUI")
		T.Check(gui and gui.Enabled, "HUD visible")
		T.Check(game:GetService("Workspace"):GetAttribute("ServerReady"), "server ready flag")
		local plots = game:GetService("Workspace"):FindFirstChild("Tycoons"):GetChildren()
		T.Check(#plots == 8, "8 tower plots exist (got " .. #plots .. ")")
	end,
})

---------------------------------------------------------------------------
add({
	Name = "economy",
	Run = function(T, place)
		local game, player = T.Boot(place)
		T.Wait(6)
		local TycoonService = T.Service("TycoonService")
		local DataService = T.Service("DataService")
		local TycoonItems = T.Shared("TycoonItems")
		local data = DataService:Get(player)
		local plot = TycoonService:GetPlot(player)
		T.Check(plot ~= nil, "has a plot")

		-- 1) buy the first item from the BUILD menu remote
		local first = cheapestAvailable(T, data)
		T.Check(first and first.Cost <= data.Cash, "first item is affordable with starting cash")
		local cashBefore = data.Cash
		local ok, message = T.Client(function()
			return T.Remote("BuyItem"):InvokeServer(first.Id)
		end)
		T.Check(ok == true, "BuyItem succeeded: " .. tostring(message))
		T.Check(data.Purchased[first.Id], "item recorded as purchased")
		T.Check(math.abs(data.Cash - (cashBefore - first.Cost)) < 1e-6, "cash was spent")
		T.Check(player:GetAttribute("Cash") == data.Cash, "Cash attribute mirrors data")
		T.Check(plot.Built[first.Id] ~= nil, "item model was built")

		-- buying it again fails politely
		local again = T.Client(function()
			return T.Remote("BuyItem"):InvokeServer(first.Id)
		end)
		T.Check(again == false, "can't buy the same item twice")

		-- 2) income flows into the vault, then the vault pad collects it
		T.Wait(4)
		T.Check(plot.Income > 0, "tower has income after the first dropper")
		T.Check((player:GetAttribute("Income") or 0) > 0, "Income attribute set")
		local vault = data.Vault
		T.Check(vault > 0, "vault filled up (" .. tostring(vault) .. ")")
		local pad
		for _, d in plot.Built.F1_1:GetDescendants() do
			if d.Name == "VaultPad" then
				pad = d
			end
		end
		T.Check(pad ~= nil, "floor 1 has a vault pad")
		if pad then
			local before = data.Cash
			T.Engine.Touch(pad, player)
			T.Wait(0.5)
			T.Check(data.Vault == 0 and data.Cash > before, "touching the vault pad collects the vault")
		end

		-- 3) touching a physical button buys it
		DataService:AddCash(player, 1e6, false)
		T.Wait(0.5)
		local buttonId, button
		for id, b in plot.ButtonObjs do
			if not buttonId or TycoonItems.ById[id].Cost < TycoonItems.ById[buttonId].Cost then
				buttonId, button = id, b
			end
		end
		T.Check(button ~= nil, "buttons exist on floor 1")
		if button then
			T.Check(button.Pad.Color == roblox.Color3.fromRGB(60, 220, 100), "affordable button is green")
			T.Engine.Touch(button.Pad, player)
			T.Wait(1)
			T.Check(data.Purchased[buttonId], "touching button " .. buttonId .. " bought it")
			T.Check(button.Model.Parent == nil, "bought button disappeared")
		end

		-- 4) BUY ALL from the client
		local boughtBefore = count(data.Purchased)
		T.Client(function()
			T.Remote("BuyAll"):FireServer()
		end)
		T.Wait(1)
		T.Check(count(data.Purchased) > boughtBefore, "BUY ALL bought several upgrades")
		T.Check(finite(data.Cash) and data.Cash >= 0, "cash stays valid")

		-- 5) the client BUILD menu agrees with the server's income math
		local build = T.Controller("Build")
		T.WaitFor(function()
			return build:BoughtCount() == count(data.Purchased)
		end, 5, "client BUILD menu to see every purchase")
		local serverIncome = plot.Income
		local clientIncome = TycoonItems.ComputeIncome(data.Purchased, {}, data.Secrets, false)
		T.Check(math.abs(serverIncome - clientIncome) < 1e-6, "client & server income agree")

		-- 6) can't buy past the floor unlock
		local f2 = TycoonItems.ById[TycoonItems.FloorUnlockId(2)]
		local f2item
		for _, item in TycoonItems.ByFloor[2] do
			if item.Kind ~= "Unlock" then
				f2item = item
				break
			end
		end
		if not data.Purchased[f2.Id] then
			local okF2 = T.Client(function()
				return T.Remote("BuyItem"):InvokeServer(f2item.Id)
			end)
			T.Check(okF2 == false, "floor 2 items are locked until floor 2 is unlocked")
		end
	end,
})

---------------------------------------------------------------------------
-- A bot plays the whole game (collect + BUY ALL every few seconds) until
-- every upgrade is bought. Checks pacing, every item builder, floor
-- unlocks, the roof and the rebirth at the end.
add({
	Name = "playthrough",
	MaxSeconds = 8 * 3600,
	AllowedWarnings = { "DataStores unavailable", "Could not load data" },
	Run = function(T, place)
		T.SetDt(1)
		local game = T.Boot(place, { Client = false })
		local player = T.AddPlayer("Bot")
		T.WaitFor(function()
			return player:GetAttribute("Plot") ~= nil
		end, 20, "bot plot")
		local TycoonService = T.Service("TycoonService")
		local DataService = T.Service("DataService")
		local TycoonItems = T.Shared("TycoonItems")
		local data = DataService:Get(player)
		local plot = TycoonService:GetPlot(player)
		local start = T.Engine.Now
		local floorTimes = {}
		local lastIncome = 0
		local stalls = 0
		while count(data.Purchased) < TycoonItems.BuyableCount and T.Engine.Now - start < 10 * 3600 do
			T.Wait(5)
			TycoonService:CollectVault(player)
			T.Engine.FireServerAs(player, T.Remote("BuyAll"))
			for floor = 2, 8 do
				if not floorTimes[floor] and data.Purchased[TycoonItems.FloorUnlockId(floor)] then
					floorTimes[floor] = T.Engine.Now - start
				end
			end
			if plot.Income <= lastIncome then
				stalls += 1
			end
			lastIncome = math.max(lastIncome, plot.Income)
			if not finite(data.Cash) or not finite(plot.Income) then
				T.Check(false, "cash/income became invalid")
				break
			end
		end
		local elapsed = T.Engine.Now - start
		local summary = {}
		for floor = 2, 8 do
			table.insert(summary, ("F%d %dm"):format(floor, math.floor((floorTimes[floor] or -60) / 60)))
		end
		print(("    playthrough: %d/%d upgrades in %.1f h (%s)"):format(count(data.Purchased), TycoonItems.BuyableCount, elapsed / 3600, table.concat(summary, ", ")))
		T.Check(count(data.Purchased) == TycoonItems.BuyableCount, "bought every upgrade")
		T.Check(elapsed > 3 * 3600 and elapsed < 8 * 3600, ("full tower takes 3-8 hours of optimal play (took %.2f h)"):format(elapsed / 3600))

		-- every purchased item is standing (or wrecked and waiting for repair)
		T.Wait(200) -- let disaster knockouts repair
		local missing = {}
		for id in data.Purchased do
			if not plot.Built[id] and not plot.Disabled[id] then
				table.insert(missing, id)
			end
		end
		T.Check(#missing == 0, "every purchased item is built (missing: " .. table.concat(missing, ",") .. ")")
		T.Check(TycoonService:IsFloorUnlocked(plot, 9), "roof unlocked")

		-- rebirth
		local cost = TycoonItems.GetRebirthCost(data.Rebirths)
		DataService:AddCash(player, cost, false)
		T.Engine.FireServerAs(player, T.Remote("RequestRebirth"))
		T.Wait(3)
		T.Check(data.Rebirths == 1, "rebirthed")
		T.Check(count(data.Purchased) == 1, "tower reset after rebirth")
		local permanent = DataService:GetMultiplier(player, true)
		T.Check(permanent == 1.5, "rebirth multiplier 1.5x (got " .. tostring(permanent) .. ")")
		local items = 0
		for _ in plot.Built do
			items += 1
		end
		T.Check(items <= 1, "old tower models were cleared (" .. items .. " left)")
	end,
})

---------------------------------------------------------------------------
-- Disasters
---------------------------------------------------------------------------
local function waitBuilt(T, plot)
	T.WaitFor(function()
		return #plot.Queue == 0
	end, 30, "tower build queue")
end

local function builtCount(plot): number
	return count(plot.Built)
end

local function lastCommand(T, player, name: string, since: number?)
	for _, args in T.Sent(player, "ClientCommand", since) do
		if args[1] == name then
			return args
		end
	end
	return nil
end

add({
	Name = "nuke",
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Exposed" })
		local bunkered = T.AddPlayer("Bunkered")
		local shielded = T.AddPlayer("Shielded")
		T.Wait(6)
		local TycoonService = T.Service("TycoonService")
		local DisasterService = T.Service("DisasterService")
		local WorldBuilder = T.Service("WorldBuilder")
		TycoonService:UnlockAll(me, 1)
		TycoonService:UnlockAll(shielded, 2)
		local myPlot, shieldPlot = TycoonService:GetPlot(me), TycoonService:GetPlot(shielded)
		waitBuilt(T, myPlot)
		waitBuilt(T, shieldPlot)
		T.Check(shieldPlot.Shielded, "floor 2 Nuke Shield makes the tower shielded")
		T.Check(myPlot.Shelter ~= nil, "floor 1 Panic Bunker registered as a shelter")
		local myItems, myIncome = builtCount(myPlot), myPlot.Income

		-- positions: public bunker / at home under the dome / out in the open
		local shelter = WorldBuilder.Shelter
		T.MoveTo(bunkered, CFrame.new(shelter.CFrame.Position - Vector3.new(0, shelter.Size.Y / 2 - 3, 0)))
		T.Wait(1) -- shielded spawned at home (inside the dome)
		T.MoveTo(me, CFrame.new(150, 4, 0))
		T.Check(DisasterService:IsSheltered(T.Root(bunkered).Position), "public bunker counts as shelter")
		T.Check(DisasterService:IsSheltered(T.Root(shielded).Position), "home spawn is inside the shield dome")
		T.Check(not DisasterService:IsSheltered(T.Root(me).Position), "open field is not sheltered")

		local since = T.Engine.Now
		local ok, message = T.Admin(me, ";nuke")
		T.Check(ok, "nuke command: " .. tostring(message))
		T.WaitFor(function()
			return game:GetService("Workspace"):GetAttribute("Disaster") == "Nuke"
		end, 5, "nuke to start")
		-- the client shows the warning + the guide beam to a bunker
		local gui = me.PlayerGui
		T.Wait(5)
		T.Check(T.FindText(gui, "BUNKER") ~= nil or T.FindText(gui, "NUKE") ~= nil, "client shows the nuke warning")
		T.WaitFor(function()
			return game:GetService("Workspace"):GetAttribute("Disaster") == nil
		end, 90, "nuke to end")

		T.Check(lastCommand(T, me, "vaporized", since) ~= nil, "exposed player was vaporized")
		T.Check(T.Noticed(bunkered, "survived", since), "bunkered player survived")
		T.Check(T.Noticed(shielded, "survived", since), "shielded player survived")
		T.Check(T.Humanoid(bunkered).Health > 0 and T.Humanoid(shielded).Health > 0, "sheltered players are alive")
		local wrecked = TycoonService:WreckedCount(myPlot)
		T.Check(wrecked > 0, "unshielded tower lost upgrades (" .. wrecked .. ")")
		T.Check(TycoonService:WreckedCount(shieldPlot) == 0, "shielded tower took no damage")
		T.Check(myPlot.Income < myIncome, "wrecked droppers lower the income")
		T.Check(#myPlot.Rubble:GetChildren() > 0, "rubble shows where items were")

		-- respawned, HUD survived the death (ResetOnSpawn = false)
		T.WaitFor(function()
			local h = T.Humanoid(me)
			return h and h.Health > 0
		end, 15, "exposed player to respawn")
		T.Check(gui:FindFirstChild("MegaTycoonUI") ~= nil, "HUD still there after dying")

		-- everything rebuilds by itself
		T.Wait(185)
		T.Check(TycoonService:WreckedCount(myPlot) == 0, "wrecked upgrades auto-repaired")
		T.Check(builtCount(myPlot) == myItems, "tower fully rebuilt (" .. builtCount(myPlot) .. "/" .. myItems .. ")")
		T.Check(math.abs(myPlot.Income - myIncome) < 1e-6, "income restored after repair")
		T.Check(#myPlot.Rubble:GetChildren() == 0, "rubble cleaned up")
	end,
})

add({
	Name = "meteors",
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local TycoonService = T.Service("TycoonService")
		local DataService = T.Service("DataService")
		TycoonService:UnlockAll(me, 1)
		waitBuilt(T, TycoonService:GetPlot(me))
		local since = T.Engine.Now
		T.Check(T.Admin(me, ";meteors"), "meteors command")
		local crystals = 0
		local grabbed = false
		local folder = game:GetService("Workspace"):FindFirstChild("Disasters")
		local limit = T.Engine.Now + 60
		while T.Engine.Now < limit and (game:GetService("Workspace"):GetAttribute("Disaster") ~= nil or T.Engine.Now < since + 3) do
			-- wander around the lobby so meteors target us
			T.MoveTo(me, CFrame.new(math.random(-100, 100), 4, math.random(-100, 100)))
			for _, part in folder:GetChildren() do
				if part.Name == "Crystal" then
					crystals += 1
					if not grabbed then
						local before = DataService:Get(me).Cash
						T.Engine.Touch(part, me)
						T.Wait(0.2)
						grabbed = DataService:Get(me).Cash > before
						T.Check(grabbed, "touching a cash crystal pays out")
					end
				end
			end
			T.Wait(0.5)
		end
		local meteors = 0
		for _, args in T.Sent(me, "Disaster", since) do
			if args[1].Phase == "Meteor" then
				meteors += 1
			end
		end
		T.Check(meteors > 40, "lots of meteors fell (" .. meteors .. ")")
		T.Check(crystals > 0, "meteors left cash crystals")
		T.Check(game:GetService("Workspace"):GetAttribute("Disaster") == nil, "storm ended")
	end,
})

add({
	Name = "tornado",
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local since = T.Engine.Now
		T.Check(T.Admin(me, ";tornado"), "tornado command")
		local folder = game:GetService("Workspace"):FindFirstChild("Disasters")
		local core = T.WaitFor(function()
			local model = folder:FindFirstChild("Tornado")
			return model and model:FindFirstChild("Core")
		end, 5, "tornado model")
		if core then
			local first = core.Position
			T.Wait(3)
			T.Check((core.Position - first).Magnitude > 20, "tornado moves")
			-- stand in it
			for _ = 1, 10 do
				T.MoveTo(me, CFrame.new(core.Position + Vector3.new(2, 4, 0)))
				T.Wait(0.3)
			end
			T.Check(lastCommand(T, me, "tornado", since) ~= nil, "tornado pulls the player")
			T.Check(T.Humanoid(me).Health < 100, "tornado hurts")
		end
		T.WaitFor(function()
			return game:GetService("Workspace"):GetAttribute("Disaster") == nil
		end, 60, "tornado to end")
		T.Check(folder:FindFirstChild("Tornado") == nil, "tornado model removed")
	end,
})

add({
	Name = "ufo",
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local DataService = T.Service("DataService")
		local since = T.Engine.Now
		T.Check(T.Admin(me, ";ufo"), "ufo command")
		local folder = game:GetService("Workspace"):FindFirstChild("Disasters")
		local grabbed = false
		local limit = T.Engine.Now + 55
		while T.Engine.Now < limit and (game:GetService("Workspace"):GetAttribute("Disaster") ~= nil or T.Engine.Now < since + 3) do
			local ufo = folder:FindFirstChild("UFO1")
			if ufo and ufo.PrimaryPart and not lastCommand(T, me, "abduct", since) then
				T.MoveTo(me, CFrame.new(ufo.PrimaryPart.Position * Vector3.new(1, 0, 1) + Vector3.new(0, 4, 0)))
			end
			for _, part in folder:GetChildren() do
				if part.Name == "AlienCash" and not grabbed then
					local before = DataService:Get(me).Cash
					T.Engine.Touch(part, me)
					T.Wait(0.2)
					grabbed = DataService:Get(me).Cash > before
					T.Check(grabbed, "touching alien cash pays out")
				end
			end
			T.Wait(0.5)
		end
		T.Check(lastCommand(T, me, "abduct", since) ~= nil, "a UFO abducted the player")
		T.Check(grabbed, "alien cash dropped and was collected")
		T.Check(#folder:GetChildren() == 0 or folder:FindFirstChild("UFO1") == nil, "UFOs left")
	end,
})

---------------------------------------------------------------------------
-- Duo building
---------------------------------------------------------------------------
add({
	Name = "duo",
	Run = function(T, place)
		local game, host = T.Boot(place, { Name = "Host" })
		local friend = T.AddPlayer("Friend")
		T.Wait(6)
		local TycoonService = T.Service("TycoonService")
		local DataService = T.Service("DataService")
		local TycoonItems = T.Shared("TycoonItems")
		local hostData, friendData = DataService:Get(host), DataService:Get(friend)
		local friendPlotIndex = friend:GetAttribute("Plot")
		T.Check(friendPlotIndex ~= nil and friendPlotIndex ~= host:GetAttribute("Plot"), "both players have their own tower")
		-- the friend buys something in their own tower first
		local friendFirst = cheapestAvailable(T, friendData)
		T.Check(T.Engine.InvokeServerAs(friend, T.Remote("BuyItem"), friendFirst.Id), "friend buys in their own tower")
		local friendCashBefore = friendData.Cash

		-- host opens the DUO panel and clicks INVITE next to Friend
		local UI = T.Controller("UI")
		T.Client(function()
			UI:Open("Duo")
		end)
		T.Wait(0.5)
		local invite
		for _, b in T.Buttons(host.PlayerGui) do
			if b.Text:find("INVITE") and b:IsDescendantOf(host.PlayerGui) then
				invite = b
			end
		end
		T.Check(invite ~= nil, "DUO panel lists the friend with an INVITE button")
		if invite then
			T.Client(function()
				T.Engine.Click(invite)
			end)
		end
		T.Wait(0.5)
		local invited = T.Sent(friend, "DuoInvited")
		T.Check(#invited == 1 and invited[1][1].HostUserId == host.UserId, "friend received the invite")

		-- friend accepts
		T.Engine.FireServerAs(friend, T.Remote("DuoRespond"), host.UserId, true)
		T.Wait(1)
		local plot = TycoonService:GetPlot(host)
		T.Check(plot.Partner == friend, "friend joined the host's tower")
		T.Check(friend:GetAttribute("DuoHost") == host.UserId and host:GetAttribute("DuoPartner") == friend.UserId, "duo attributes set")
		T.Check(TycoonService:GetPlot(friend) == plot, "friend's plot is the host's plot")
		T.Check(friend:GetAttribute("Cash") == hostData.Cash, "friend sees the shared wallet")
		local freed = TycoonService:GetPlots()[friendPlotIndex]
		T.Check(freed.Owner == nil, "friend's old tower was freed for others")

		-- shared wallet: the friend spends the host's cash, items go to the host's tower
		DataService:AddCash(host, 5000, false)
		local hostCash = hostData.Cash
		local item = cheapestAvailable(T, hostData)
		local friendOwned = count(friendData.Purchased)
		local ok = T.Engine.InvokeServerAs(friend, T.Remote("BuyItem"), item.Id)
		T.Check(ok, "partner can buy upgrades")
		T.Check(hostData.Purchased[item.Id] and count(friendData.Purchased) == friendOwned, "purchase saved to the host")
		T.Check(math.abs(hostData.Cash - (hostCash - item.Cost)) < 1e-6, "partner spent the host's cash")
		T.Check(friendData.Cash == friendCashBefore, "partner's own savings untouched")
		T.Check(friend:GetAttribute("Cash") == hostData.Cash, "partner's Cash attribute follows the host")
		-- income goes to the shared vault, either can collect
		T.Wait(4)
		T.Check(hostData.Vault > 0 and friend:GetAttribute("Vault") == hostData.Vault, "shared vault")
		TycoonService:CollectVault(friend)
		T.Check(hostData.Vault == 0, "partner collected the shared vault")
		-- partner can't rebirth the host's tower
		T.Engine.FireServerAs(friend, T.Remote("RequestRebirth"))
		T.Wait(0.5)
		T.Check(hostData.Rebirths == 0, "partner can't rebirth the host")

		-- friend leaves: gets their own tower back exactly as it was
		T.Engine.FireServerAs(friend, T.Remote("DuoLeave"))
		T.Wait(2)
		T.Check(friend:GetAttribute("DuoHost") == nil and host:GetAttribute("DuoPartner") == nil, "duo ended")
		local own = TycoonService:GetPlot(friend)
		T.Check(own ~= nil and own ~= plot and own.Owner == friend, "friend got their own tower back")
		if own then
			waitBuilt(T, own)
			T.Check(own.Built[friendFirst.Id] ~= nil, "friend's tower has their old upgrade")
		end
		T.Check(friend:GetAttribute("Cash") == friendData.Cash, "friend's own wallet is back")

		-- duo again, then the HOST leaves the game: friend gets their tower back
		T.Wait(5)
		T.Server(function()
			T.Service("DuoService"):Invite(host, friend)
		end)
		T.Engine.FireServerAs(friend, T.Remote("DuoRespond"), host.UserId, true)
		T.Wait(1)
		T.Check(plot.Partner == friend, "second duo formed")
		T.Engine.RemovePlayer(host)
		T.Wait(2)
		local back = TycoonService:GetPlot(friend)
		T.Check(back ~= nil and back.Owner == friend, "friend gets a tower when the host leaves")
		T.Check(friend:GetAttribute("DuoHost") == nil, "friend no longer in a duo")
		-- a declined invite does nothing
		local third = T.AddPlayer("Third")
		T.Wait(3)
		T.Server(function()
			T.Service("DuoService"):Invite(friend, third)
		end)
		T.Engine.FireServerAs(third, T.Remote("DuoRespond"), friend.UserId, false)
		T.Wait(0.5)
		T.Check(third:GetAttribute("DuoHost") == nil and T.Noticed(friend, "declined"), "declined invite")
		-- forged responses (no invite / wrong host) are ignored
		T.Engine.FireServerAs(third, T.Remote("DuoRespond"), friend.UserId, true)
		T.Wait(0.5)
		T.Check(third:GetAttribute("DuoHost") == nil, "can't join without an invite")
	end,
})

---------------------------------------------------------------------------
-- Secrets
---------------------------------------------------------------------------
add({
	Name = "secrets",
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local Config = T.Shared("Config")
		local data = DataService:Get(me)
		local plot = TycoonService:GetPlot(me)
		local folder = game:GetService("Workspace"):FindFirstChild("Secrets")
		T.Check(#folder:GetChildren() == #Config.Secrets, "every secret has a gem in the world (" .. #folder:GetChildren() .. ")")
		local incomeBefore
		T.Server(function()
			TycoonService:UnlockAll(me, 1)
		end)
		waitBuilt(T, plot)
		incomeBefore = plot.Income
		for i, secret in Config.Secrets do
			local model = folder:FindFirstChild("Secret_" .. secret.Id)
			local hitbox = model and model:FindFirstChild("Hitbox")
			T.Check(hitbox ~= nil, "secret " .. secret.Id .. " has a hitbox")
			if hitbox then
				T.MoveTo(me, CFrame.new(hitbox.Position))
				local cash = data.Cash
				T.Engine.Touch(hitbox, me)
				T.Wait(0.3)
				T.Check(data.Secrets[secret.Id], "found secret " .. secret.Id)
				T.Check(data.Cash > cash, "secret " .. secret.Id .. " paid cash")
				T.Check(plot.Built["Secret_" .. secret.Id] ~= nil, "relic for " .. secret.Id .. " built in the tower")
			end
		end
		T.Check(count(data.Secrets) == #Config.Secrets, "all secrets found")
		-- each secret adds +5% of the base income (additive with floor bonuses)
		local TycoonItems = T.Shared("TycoonItems")
		local base = TycoonItems.ComputeIncome(data.Purchased, {}, {}, false)
		local withAll = TycoonItems.ComputeIncome(data.Purchased, {}, data.Secrets, false)
		T.Check(math.abs(plot.Income - withAll) < 1e-6 and math.abs(base - incomeBefore) < 1e-6, "server income includes the secret bonus")
		T.Check(withAll > base * 1.4, ("12 secrets add a big bonus (%.1f -> %.1f)"):format(base, withAll))
		T.Check(#string.split(me:GetAttribute("SecretsFound"), ",") == #Config.Secrets, "SecretsFound attribute lists them all")
		-- touching again doesn't pay twice
		local cash = data.Cash
		T.Wait(3)
		T.Engine.Touch(folder:FindFirstChild("Secret_Board"):FindFirstChild("Hitbox"), me)
		T.Wait(0.3)
		T.Check(data.Cash == cash, "a secret only pays once")
		-- relics survive a rebirth
		T.Server(function()
			TycoonService:Rebirth(me, true)
		end)
		waitBuilt(T, plot)
		T.Wait(1)
		T.Check(plot.Built.Secret_Board ~= nil, "relics are kept after rebirth")
		-- the client's secrets panel shows them
		T.Client(function()
			T.Controller("UI"):Open("Secrets")
		end)
		T.Wait(0.5)
		T.Check(T.FindText(me.PlayerGui, "12/12") ~= nil or T.FindText(me.PlayerGui, "12 / 12") ~= nil, "secrets panel shows 12/12")
	end,
})

---------------------------------------------------------------------------
-- Admin commands
---------------------------------------------------------------------------
add({
	Name = "admin",
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Boss" })
		local target = T.AddPlayer("Target")
		T.Wait(6)
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local Config = T.Shared("Config")
		local data, tdata = DataService:Get(me), DataService:Get(target)
		T.Check(me:GetAttribute("AdminRank") == 4, "Studio play-testers are Owner")
		local function run(text: string, expectOk: boolean?)
			local ok, message = T.Admin(me, text)
			if expectOk ~= false then
				T.Check(ok == true, text .. " -> " .. tostring(message))
			end
			T.Wait(0.2)
			return ok, message
		end
		local humanoid = function(p)
			return T.Humanoid(p)
		end

		-- Mod commands
		run(";cmds")
		T.Wait(0.3)
		T.Check(T.Controller("UI").Current == "Admin", ";cmds opens the admin panel")
		run(";logs")
		run(";tp target me")
		T.Check((T.Root(target).Position - T.Root(me).Position).Magnitude < 10, ";tp moved Target to me")
		T.MoveTo(target, CFrame.new(100, 4, 100))
		run(";bring target")
		T.Check((T.Root(target).Position - T.Root(me).Position).Magnitude < 10, ";bring")
		T.MoveTo(target, CFrame.new(-100, 4, 100))
		run(";to target")
		T.Check((T.Root(target).Position - T.Root(me).Position).Magnitude < 10, ";to")
		run(";home all")
		T.Wait(0.5)
		run(";speed me 50")
		T.Check(humanoid(me).WalkSpeed == 50, ";speed")
		run(";jump me 120")
		T.Check(humanoid(me).JumpPower == 120, ";jump")
		run(";god me")
		T.Check(humanoid(me).MaxHealth == math.huge, ";god")
		run(";ungod me")
		T.Check(humanoid(me).MaxHealth == 100, ";ungod")
		run(";ff me")
		T.Check(me.Character:FindFirstChildOfClass("ForceField") ~= nil, ";ff")
		run(";unff me")
		T.Check(me.Character:FindFirstChild("ShieldBubble") == nil, ";unff")
		run(";heal me")
		run(";freeze target")
		T.Check(T.Root(target).Anchored, ";freeze anchors")
		run(";thaw target")
		T.Check(not T.Root(target).Anchored, ";thaw")
		for _, fx in { "sparkles", "fire", "smoke" } do
			run(";" .. fx .. " me")
		end
		run(";unfx me")
		run(";invisible me")
		run(";visible me")
		run(";jail target")
		T.Check(game:GetService("Workspace"):FindFirstChild("Jail_Target") ~= nil, ";jail builds a cage")
		run(";unjail target")
		T.Check(game:GetService("Workspace"):FindFirstChild("Jail_Target") == nil, ";unjail")
		run(";fly me")
		T.Wait(0.3)
		T.Check(T.Controller("Admin"):IsFlying(), ";fly makes the client fly")
		run(";unfly me")
		T.Wait(0.3)
		T.Check(not T.Controller("Admin"):IsFlying(), ";unfly")
		run(";noclip me")
		run(";clip me")
		run(";view target")
		run(";unview")
		run(";m Hello everyone")
		run(";h a hint")
		run(";kill target")
		T.Wait(0.2)
		T.Check(humanoid(target).Health == 0, ";kill")
		T.Wait(6)
		T.Check(humanoid(target) and humanoid(target).Health > 0, "killed player respawns")
		run(";respawn target")
		run(";floor 1")

		-- Admin commands
		local before = data.Cash
		run(";givecash me 1m")
		T.Check(data.Cash == before + 1e6, ";givecash 1m")
		run(";takecash me 500k")
		T.Check(data.Cash == before + 5e5, ";takecash 500k")
		run(";setcash me 2.5b")
		T.Check(data.Cash == 2.5e9, ";setcash 2.5b")
		run(";giverebirth target 2")
		T.Check(tdata.Rebirths == 2, ";giverebirth")
		run(";rebirth target")
		T.Check(tdata.Rebirths == 3, ";rebirth (free)")
		run(";unlockfloor me 3")
		T.WaitFor(function()
			return TycoonService:IsFloorUnlocked(TycoonService:GetPlot(me), 3)
		end, 5, "floor 3 unlocked")
		run(";explode target")
		run(";giant me")
		T.Check(me.Character:GetScale() == 2.5, ";giant")
		run(";tiny me")
		run(";normal me")
		T.Check(me.Character:GetScale() == 1, ";normal")
		run(";confetti all")
		run(";cashrain")
		run(";doublecash 10 3")
		T.Check(game:GetService("Workspace"):GetAttribute("EventMultiplier") == 3, ";doublecash sets the event multiplier")
		T.Check(me:GetAttribute("Multiplier") == 3, "event multiplier applies to income")
		run(";music 1837849285")
		run(";stopmusic")
		run(";time 6")
		T.Check(game:GetService("Lighting").ClockTime == 6, ";time")
		run(";wreck me 50")
		local plot = TycoonService:GetPlot(me)
		T.Check(TycoonService:WreckedCount(plot) > 0, ";wreck")
		run(";repair me")
		T.Check(TycoonService:WreckedCount(plot) == 0, ";repair")
		run(";givesecrets me")
		T.Check(count(data.Secrets) == #Config.Secrets, ";givesecrets")
		run(";duo me target")
		T.Check(target:GetAttribute("DuoHost") == me.UserId, ";duo")
		run(";unduo target")
		T.Wait(1)
		T.Check(target:GetAttribute("DuoHost") == nil, ";unduo")
		run(";minigame CoinRush")
		run(";nuke")
		run(";stopdisaster")

		-- Head admin commands
		run(";resetsecrets me")
		T.Check(count(data.Secrets) == 0, ";resetsecrets")
		run(";givepass me VIP")
		T.Check(me:GetAttribute("Pass_VIP") == true, ";givepass")
		run(";removepass me VIP")
		T.Check(me:GetAttribute("Pass_VIP") == nil, ";removepass")
		run(";resetdata target")
		T.Check(tdata.Rebirths == 0 and count(tdata.Purchased) == 1, ";resetdata wipes progress")
		run(";ban SomeoneOffline being mean")
		run(";unban SomeoneOffline")

		-- bad numbers must never corrupt the economy
		run(";doublecash nan nan", false)
		run(";giverebirth me inf", false)
		run(";givecash me " .. string.rep("9", 400), false)
		run(";speed me nan", false)
		run(";time nan", false)
		run(";wreck me nan", false)
		run(";unlockfloor me nan", false)
		T.Wait(3)
		T.Check(finite(game:GetService("Workspace"):GetAttribute("EventMultiplier")), "event multiplier stays finite")
		T.Check(finite(game:GetService("Workspace"):GetAttribute("EventEnds")), "event end time stays finite")
		T.Check(finite(data.Cash) and finite(data.Vault) and finite(data.Rebirths), "wallet stays finite")
		T.Check(finite(me:GetAttribute("Multiplier")), "multiplier stays finite")
		T.Check(finite(humanoid(me).WalkSpeed), "walk speed stays finite")

		-- unknown commands / ranks
		local okUnknown = run(";definitelynotacommand", false)
		T.Check(okUnknown == false, "unknown command fails")
		run(";kick target being rude")
		T.Wait(1)
		T.Check(target.Parent == nil and #T.Engine.Kicks == 1, ";kick removes the player")
		-- Owner
		run(";shutdown")
		T.Wait(6)
		T.Check(me.Parent == nil, ";shutdown kicks everyone")
	end,
})

add({
	Name = "admin_ranks",
	Run = function(T, place)
		T.Engine.Studio = false
		local game = T.Boot(place, { Client = false })
		local Config = T.Shared("Config")
		Config.Admin.Admins[5001] = 1
		T.Engine.CreatorId = 5002
		local mod = T.AddPlayer("Mod", { UserId = 5001 })
		local owner = T.AddPlayer("Owner", { UserId = 5002 })
		local pleb = T.AddPlayer("Pleb", { UserId = 5003 })
		T.Wait(6)
		T.Check(mod:GetAttribute("AdminRank") == 1, "Config admin gets Mod")
		T.Check(owner:GetAttribute("AdminRank") == 4, "place creator is Owner")
		T.Check(pleb:GetAttribute("AdminRank") == 0, "everyone else is a player")
		local remote = T.Remote("AdminCommand")
		local ok, message = T.Engine.InvokeServerAs(pleb, remote, ";givecash me 1b")
		T.Check(ok == false, "players can't run commands: " .. tostring(message))
		local data = T.Service("DataService"):Get(pleb)
		T.Check(data.Cash < 1e9, "no cash for players")
		T.Check(T.Engine.InvokeServerAs(pleb, T.Remote("AdminData"), "players") == nil, "players can't read admin data")
		ok = T.Engine.InvokeServerAs(mod, remote, ";speed me 30")
		T.Check(ok == true, "mod can use mod commands")
		ok, message = T.Engine.InvokeServerAs(mod, remote, ";givecash me 1b")
		T.Check(ok == false and tostring(message):find("Admin") ~= nil, "mod can't use admin commands")
		T.Engine.InvokeServerAs(mod, remote, ";kill owner")
		T.Wait(0.2)
		T.Check(T.Humanoid(owner).Health > 0, "mods can't kill higher ranks")
		T.Engine.InvokeServerAs(owner, remote, ";admin pleb 2")
		T.Wait(0.5)
		T.Check(pleb:GetAttribute("AdminRank") == 2, "owner can promote")
		T.Engine.InvokeServerAs(owner, remote, ";unadmin pleb")
		T.Wait(0.5)
		T.Check(pleb:GetAttribute("AdminRank") == 0, "owner can demote")
		-- bans persist and kick on join
		T.Engine.InvokeServerAs(owner, remote, ";ban pleb cheating")
		T.Wait(1)
		T.Check(pleb.Parent == nil, "banned player was kicked")
		local again = T.AddPlayer("Pleb", { UserId = 5003 })
		T.Wait(3)
		T.Check(again.Parent == nil, "banned player is kicked when rejoining")
		T.Engine.InvokeServerAs(owner, remote, ";unban Pleb")
		local back = T.AddPlayer("Pleb", { UserId = 5003 })
		T.Wait(3)
		T.Check(back.Parent ~= nil and back:GetAttribute("DataLoaded"), "unbanned player can join")
		-- legacy chat fallback is off with TextChatService (no double commands)
		T.Engine.Chat(owner, ";givecash me 5")
		T.Wait(0.5)
	end,
})

---------------------------------------------------------------------------
-- Robux shop
---------------------------------------------------------------------------
add({
	Name = "shop_studio",
	MaxSeconds = 1500,
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local Config = T.Shared("Config")
		local data = DataService:Get(me)
		TycoonService:UnlockAll(me, 1)
		local plot = TycoonService:GetPlot(me)
		waitBuilt(T, plot)
		T.Wait(2)
		local income = TycoonService:GetIncome(me)
		-- the shop UI has a card per pass/product; buying works through it
		T.Client(function()
			T.Controller("UI"):Open("Shop")
		end)
		T.Wait(0.5)
		local function buyButton(key: string)
			for _, d in me.PlayerGui:GetDescendants() do
				if d.Name == key and d:IsA("Frame") then
					return d:FindFirstChildWhichIsA("TextButton", true)
				end
			end
			return nil
		end
		local cards = 0
		for key in Config.GamePasses do
			cards += buyButton(key) and 1 or 0
		end
		for key in Config.Products do
			cards += buyButton(key) and 1 or 0
		end
		T.Check(cards == count(Config.GamePasses) + count(Config.Products), "shop shows every pass and product (" .. cards .. " cards)")

		-- passes (simulated in Studio), bought by clicking the cards
		for key in Config.GamePasses do
			local button = buyButton(key)
			T.Client(function()
				T.Engine.Click(button)
			end)
			T.Wait(0.5)
			T.Check(me:GetAttribute("Pass_" .. key) == true, "pass " .. key .. " granted")
			T.Check(button.Text:find("OWNED") ~= nil, "card for " .. key .. " shows OWNED")
		end
		T.Check(data.Passes.DoubleCash, "simulated passes are saved")
		-- the Auto Builder spends cash by itself; check it, then switch it off
		local owned = count(data.Purchased)
		T.Service("DataService"):AddCash(me, 1e5, false)
		T.Wait(5)
		T.Check(count(data.Purchased) > owned, "Auto Builder buys upgrades by itself")
		T.Client(function()
			T.Remote("SaveSettings"):FireServer({ AutoBuild = false })
		end)
		T.Wait(0.5)
		owned = count(data.Purchased)
		T.Wait(5)
		T.Check(count(data.Purchased) == owned, "Auto Builder can be switched off")
		local mult = me:GetAttribute("Multiplier")
		T.Check(math.abs(mult - 3) < 1e-9, "2x Cash * VIP 1.5x = 3x (" .. tostring(mult) .. ")")
		T.Check(T.Humanoid(me).WalkSpeed == 32, "Super Speed doubles walk speed")
		T.Check(T.Root(me):FindFirstChild("VIPAura") ~= nil, "VIP aura")
		T.Wait(2)
		T.Check(data.Vault == 0, "Auto Collect skips the vault")
		T.Check(math.abs(plot.Income - T.Shared("TycoonItems").ComputeIncome(data.Purchased, {}, data.Secrets, true)) < 1e-6, "Fast Droppers doubles dropper income")
		-- buying again just says you own it (the card ignores clicks; the server double-checks)
		T.Client(function()
			T.Remote("BuyPass"):FireServer("VIP")
		end)
		T.Wait(0.3)
		T.Check(T.Noticed(me, "already own"), "can't buy a pass twice")
		-- passes survive respawn
		T.Humanoid(me).Health = 0
		T.Wait(6.5)
		T.Check(T.Humanoid(me).WalkSpeed == 32 and T.Root(me):FindFirstChild("VIPAura") ~= nil, "pass perks re-applied after respawn")

		-- products
		income = TycoonService:GetIncome(me)
		local cash = data.Cash
		T.Client(function()
			T.Remote("BuyProduct"):FireServer("CashSmall")
		end)
		T.Wait(0.5)
		local expected = math.max(Config.Products.CashSmall.MinCash, income * Config.Products.CashSmall.Minutes * 60)
		-- (Auto Collect keeps paying income while we wait: allow up to 1.5 s of it on top)
		local gained = data.Cash - cash - expected
		T.Check(gained > -1 and gained < income * 1.5, ("cash pack pays max(min, minutes of income): got %s expected %s (income %s)"):format(tostring(data.Cash - cash), tostring(expected), tostring(income)))
		T.Client(function()
			T.Remote("BuyProduct"):FireServer("Boost")
		end)
		T.Wait(0.5)
		T.Check(data.BoostEnd > 0, "boost active")
		T.Check(math.abs(me:GetAttribute("Multiplier") - 6) < 1e-9, "2x boost doubles the multiplier")
		T.Server(function()
			T.Service("TycoonService"):KnockOutFraction(plot, 0.5, 600)
		end)
		T.Check(TycoonService:WreckedCount(plot) > 0, "tower wrecked for the repair test")
		T.Client(function()
			T.Remote("BuyProduct"):FireServer("InstantRepair")
		end)
		T.Wait(0.5)
		T.Check(TycoonService:WreckedCount(plot) == 0, "Instant Repair fixes everything")
		T.Client(function()
			T.Remote("BuyProduct"):FireServer("CashRain")
		end)
		T.Wait(0.5)
		T.Check(#T.Sent(me, "Announce") > 0, "cash rain announced")
		T.Client(function()
			T.Remote("BuyProduct"):FireServer("MeteorStorm")
		end)
		T.WaitFor(function()
			return game:GetService("Workspace"):GetAttribute("Disaster") == "Meteors"
		end, 5, "bought meteor storm")
		T.Client(function()
			T.Remote("BuyProduct"):FireServer("LaunchNuke")
		end)
		T.Wait(0.5)
		T.Check(T.Noticed(me, "queued"), "a nuke bought during a storm is queued, not lost")
		T.WaitFor(function()
			return game:GetService("Workspace"):GetAttribute("Disaster") == "Nuke"
		end, 70, "queued nuke to start")
		-- boost runs out
		T.Wait(15 * 60)
		T.Check(math.abs(me:GetAttribute("Multiplier") - 3) < 1e-9, "boost expired")
	end,
})

add({
	Name = "shop_live",
	Run = function(T, place)
		T.Engine.Studio = false
		local game = T.Boot(place, {
			Client = false,
			Setup = function(T2)
				-- a published game with real ids
				local Config = T2.Shared("Config")
				Config.GamePasses.VIP.Id = 111
				Config.Products.CashSmall.Id = 222
				Config.Products.LaunchNuke.Id = 333
			end,
		})
		local Config = T.Shared("Config")
		T.Engine.OwnedPasses[7002] = { [111] = true } -- bought VIP on the website
		local buyer = T.AddPlayer("Buyer", { UserId = 7001 })
		local fan = T.AddPlayer("Fan", { UserId = 7002 })
		T.Wait(6)
		local DataService = T.Service("DataService")
		local data = DataService:Get(buyer)
		T.Check(fan:GetAttribute("Pass_VIP") == true, "owned pass detected on join")
		T.Check(buyer:GetAttribute("Pass_VIP") == nil, "no pass without buying")
		-- unconfigured items can't be bought in a live game
		T.Engine.FireServerAs(buyer, T.Remote("BuyPass"), "DoubleCash")
		T.Wait(0.3)
		T.Check(buyer:GetAttribute("Pass_DoubleCash") == nil and T.Noticed(buyer, "isn't available"), "unconfigured pass is not free in live games")
		-- buying VIP: prompt -> purchase finished -> pass applied
		T.Engine.AutoBuy = true
		T.Engine.FireServerAs(buyer, T.Remote("BuyPass"), "VIP")
		T.Wait(0.5)
		T.Check(buyer:GetAttribute("Pass_VIP") == true, "VIP applied after the purchase prompt")
		T.Check(not data.Passes.VIP, "real passes aren't copied into saves (Roblox owns them)")
		-- developer product: ProcessReceipt grants exactly once
		local cash = data.Cash
		T.Engine.FireServerAs(buyer, T.Remote("BuyProduct"), "CashSmall")
		T.Wait(0.5)
		T.Check(#T.Engine.Receipts == 1, "receipt processed")
		local receipt = T.Engine.Receipts[1]
		T.Check(receipt and receipt.Decision == Enum.ProductPurchaseDecision.PurchaseGranted, "purchase granted")
		local paid = data.Cash - cash
		T.Check(paid >= Config.Products.CashSmall.MinCash, "cash pack paid (" .. paid .. ")")
		-- Roblox retries a receipt (e.g. after a timeout): no double grant
		local cb = T.Engine.Callback(game:GetService("MarketplaceService"), "ProcessReceipt")
		local decision = T.Server(function()
			return cb(receipt.Receipt)
		end)
		T.Check(decision == Enum.ProductPurchaseDecision.PurchaseGranted and data.Cash - cash == paid, "retried receipt is not granted twice")
		-- receipt for someone who left: not processed yet (Roblox retries on rejoin)
		local ghost = T.Server(function()
			return cb({ PlayerId = 99999, ProductId = 222, PurchaseId = "ghost", CurrencySpent = 25 })
		end)
		T.Check(ghost == Enum.ProductPurchaseDecision.NotProcessedYet, "offline buyer's receipt waits")
		-- the data store is down: don't grant (or Roblox would refund + we'd lose track)
		T.Engine.DataStoreFail = true
		local down = T.Server(function()
			return cb({ PlayerId = 7001, ProductId = 222, PurchaseId = "p-down", CurrencySpent = 25 })
		end)
		T.Engine.DataStoreFail = false
		T.Check(down == Enum.ProductPurchaseDecision.NotProcessedYet, "no grant while purchase history is unavailable")
		-- nuke product
		T.Engine.FireServerAs(buyer, T.Remote("BuyProduct"), "LaunchNuke")
		T.WaitFor(function()
			return game:GetService("Workspace"):GetAttribute("Disaster") == "Nuke"
		end, 5, "bought nuke to launch")
	end,
	AllowedWarnings = { "DataStores unavailable", "Could not load data", "Save failed", "API Services" },
})

---------------------------------------------------------------------------
-- Saving / loading
---------------------------------------------------------------------------
add({
	Name = "save_load",
	MaxSeconds = 4 * 3600,
	AllowedWarnings = { "Could not load data", "API Services", "Save failed" },
	Run = function(T, place)
		local game = T.Boot(place, { Client = false })
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local Config = T.Shared("Config")
		local saver = T.AddPlayer("Saver", { UserId = 8001 })
		T.Wait(6)
		local data = DataService:Get(saver)
		T.Check(data ~= nil and data.Cash == Config.StartingCash, "new player starts fresh")
		TycoonService:UnlockAll(saver, 2)
		local plot = TycoonService:GetPlot(saver)
		waitBuilt(T, plot)
		T.Server(function()
			T.Service("SecretService"):Find(saver, "Summit", true)
			T.Service("RewardService"):Redeem(saver, "release")
			T.Service("RewardService"):ClaimDaily(saver)
		end)
		T.Engine.FireServerAs(saver, T.Remote("SaveSettings"), { MusicVolume = 0.8, SFX = false, LowGraphics = true })
		T.Wait(5)
		local purchased = count(data.Purchased)
		local built = count(plot.Built)
		local cash = data.Cash
		local income = TycoonService:GetIncome(saver)

		-- leave: saved
		T.Engine.RemovePlayer(saver)
		T.Wait(1)
		local stored = T.Engine.DataStores[Config.DataStoreName]["Player_8001"]
		T.Check(stored ~= nil, "data saved on leave")
		if stored then
			T.Check(count(stored.Purchased) == purchased, "purchases saved")
			T.Check(stored.Secrets.Summit == true, "secrets saved")
			T.Check(stored.RedeemedCodes.RELEASE == true, "codes saved")
			T.Check(stored.DailyStreak == 1, "daily streak saved")
			T.Check(stored.Settings.MusicVolume == 0.8 and stored.Settings.SFX == false and stored.Settings.LowGraphics == true, "settings saved")
			T.Check(math.abs(stored.Cash - cash) < 1e-6, "cash saved")
			T.Check(math.abs(stored.LastIncome - income) < 1e-6, "income saved for offline earnings")
		end
		T.Check(plot.Owner == nil and #plot.Items:GetChildren() == 0, "tower cleared when the owner left")
		local board = T.Engine.OrderedStores[Config.DataStoreName .. "_TotalEarnedLog"]
		T.Check(board and board["8001"] ~= nil, "leaderboard entry saved")

		-- two hours later they come back
		T.SetDt(1)
		T.Wait(2 * 3600)
		T.SetDt(0.1)
		saver = T.AddPlayer("Saver", { UserId = 8001 })
		T.Wait(8)
		data = DataService:Get(saver)
		plot = TycoonService:GetPlot(saver)
		T.Check(count(data.Purchased) == purchased, "purchases loaded")
		T.Check(plot and count(plot.Built) == built, "tower rebuilt exactly (" .. (plot and count(plot.Built) or 0) .. "/" .. built .. ")")
		local expected = income * 2 * 3600 * Config.OfflineEarnings.Percent
		T.Check(data.Vault >= expected * 0.98 and data.Vault <= expected * 1.05, ("offline earnings in the vault (%.0f, expected ~%.0f)"):format(data.Vault, expected))
		T.Check(T.Noticed(saver, "While you were away"), "offline earnings message")
		T.Check(saver:GetAttribute("MusicVolume") == 0.8, "settings restored")

		-- data store outage while loading: play, but never overwrite the real save
		T.Engine.RemovePlayer(saver)
		T.Wait(1)
		local before = T.Engine.DeepCopy(T.Engine.DataStores[Config.DataStoreName]["Player_8001"])
		T.Engine.DataStoreFail = true
		saver = T.AddPlayer("Saver", { UserId = 8001 })
		T.Wait(8)
		T.Check(saver:GetAttribute("DataLoaded"), "can still play during an outage")
		T.Check(T.Warned("Could not load data"), "outage warned")
		T.Engine.DataStoreFail = false
		DataService:AddCash(saver, 123, false)
		T.Engine.RemovePlayer(saver)
		T.Wait(1)
		local after = T.Engine.DataStores[Config.DataStoreName]["Player_8001"]
		T.Check(after.Cash == before.Cash and count(after.Purchased) == count(before.Purchased), "outage session did not overwrite the save")

		-- corrupted save values are repaired on load
		local stored2 = T.Engine.DataStores[Config.DataStoreName]["Player_8001"]
		stored2.Cash = "lots"
		stored2.Settings = 7
		saver = T.AddPlayer("Saver", { UserId = 8001 })
		T.Wait(8)
		data = DataService:Get(saver)
		T.Check(type(data.Cash) == "number" and type(data.Settings) == "table", "corrupted values repaired on load")
		T.Check(count(data.Purchased) == purchased, "the rest of the save survived")

		-- shutdown saves everyone
		DataService:AddCash(saver, 1000, false)
		local final = data.Cash
		T.Engine.Close()
		T.Wait(4)
		T.Check(T.Engine.DataStores[Config.DataStoreName]["Player_8001"].Cash == final, "BindToClose saved the latest data")
	end,
})

---------------------------------------------------------------------------
-- Obby
---------------------------------------------------------------------------
add({
	Name = "obby",
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local DataService = T.Service("DataService")
		local data = DataService:Get(me)
		local obby = game:GetService("Workspace"):FindFirstChild("Obby")
		T.Check(obby ~= nil, "obby exists")
		-- find checkpoints / kill bricks / finish by their parts
		local checkpoints, killParts, finish, startLine = {}, {}, nil, nil
		for _, d in obby:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "StartLine" then
					startLine = d
				elseif d.Name == "Lava" or d.Name == "KillBrick" then
					table.insert(killParts, d)
				end
			end
		end
		local ObbyService = T.Service("ObbyService")
		local stage = 1
		while ObbyService:GetCheckpointCFrame(stage) do
			stage += 1
		end
		local stages = stage - 1
		T.Check(stages >= 6, "obby has checkpoints (" .. stages .. ")")
		for _, d in obby:GetDescendants() do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon and d.Size == Vector3.new(12, 1, 12) then
				for i = 1, stages do
					if (d.Position + Vector3.new(0, 4, 0) - ObbyService:GetCheckpointCFrame(i).Position).Magnitude < 0.1 then
						checkpoints[i] = d
					end
				end
				if d.Color == roblox.Color3.fromRGB(255, 200, 40) then
					finish = d
				end
			end
		end
		T.Check(startLine ~= nil and finish ~= nil and #killParts > 0, "start line, finish and lava exist")
		-- finishing without running the course gives nothing
		local cash = data.Cash
		T.Engine.Touch(finish, me)
		T.Wait(0.5)
		T.Check(data.Cash == cash, "can't skip to the finish")
		-- run it: start, checkpoints in order
		T.Engine.Touch(startLine, me)
		for i = 1, stages do
			if checkpoints[i] then
				T.MoveTo(me, ObbyService:GetCheckpointCFrame(i))
				T.Engine.Touch(checkpoints[i], me)
				T.Wait(0.3)
			end
		end
		T.Check(me:GetAttribute("ObbyStage") == stages, "reached the last checkpoint")
		-- die in the lava -> respawn at the checkpoint
		T.Engine.Touch(killParts[1], me)
		T.Wait(0.2)
		T.Check(T.Humanoid(me).Health == 0, "lava kills")
		T.Wait(7)
		local root = T.Root(me)
		T.Check(root and (root.Position - ObbyService:GetCheckpointCFrame(stages).Position).Magnitude < 8, "respawned at the checkpoint")
		-- finish: reward + sent home
		cash = data.Cash
		T.Engine.Touch(finish, me)
		T.Wait(0.5)
		T.Check(data.Cash > cash, "obby reward paid")
		T.Check(data.ObbyCompletions == 1, "completion counted")
		T.Wait(4)
		T.Check(me:GetAttribute("ObbyStage") == 0, "stage reset after finishing")
		local plotCenter = me:GetAttribute("PlotCenter")
		T.Check((T.Root(me).Position - plotCenter).Magnitude < 80, "sent home after finishing")
		-- second finish within the cooldown: no cash
		T.Engine.Touch(startLine, me)
		T.Engine.Touch(checkpoints[1], me)
		cash = data.Cash
		T.Engine.Touch(finish, me)
		T.Wait(0.5)
		T.Check(data.Cash == cash and T.Noticed(me, "Next reward"), "reward has a cooldown")
		-- the ghost path leads to a secret
		T.Check(obby:FindFirstChild("Ghost1", true) ~= nil, "secret ghost path exists")
	end,
})

---------------------------------------------------------------------------
-- Minigames
---------------------------------------------------------------------------
local function playMinigame(T, key: string)
	local game, me = T.Boot(T.Place)
	local other = T.AddPlayer("Rival")
	T.Wait(6)
	local DataService = T.Service("DataService")
	local data = DataService:Get(me)
	local cash = data.Cash
	T.Check(T.Admin(me, ";minigame " .. key), "force start " .. key)
	-- JOIN from the client UI once the join window opens (the card slides in)
	local since = T.Engine.Now
	T.WaitFor(function()
		for _, args in T.Sent(me, "MinigameState", since) do
			if args[1].Phase == "Join" then
				return true
			end
		end
		return false
	end, 8, "join window")
	T.Wait(1)
	local joinButton = T.FindButton(me.PlayerGui, "JOIN")
	T.Check(joinButton ~= nil, "JOIN button on screen")
	if joinButton then
		T.Client(function()
			T.Engine.Click(joinButton)
		end)
	end
	T.Engine.FireServerAs(other, T.Remote("MinigameJoin"))
	T.WaitFor(function()
		return me:GetAttribute("InMinigame") == true
	end, 30, "teleport into the arena")
	local Config = T.Shared("Config")
	local arena = Config.Minigames.ArenaCenter
	T.Check((T.Root(me).Position - arena).Magnitude < 80, "player placed in the arena")
	local folder = game:GetService("Workspace"):FindFirstChild("Minigame_" .. key)
	T.Check(folder ~= nil, "arena built")
	-- play: touch coins / tiles while the round runs; the rival falls off
	local limit = T.Engine.Now + 120
	local fell = false
	while T.Engine.Now < limit and (me:GetAttribute("InMinigame") or other:GetAttribute("InMinigame")) do
		if key == "CoinRush" and folder then
			for _, part in folder:GetChildren() do
				if part.Name == "Coin" then
					T.Engine.Touch(part, me)
					break
				end
			end
		end
		if not fell and T.Engine.Now > limit - 110 then
			fell = true
			if T.Root(other) then
				T.MoveTo(other, CFrame.new(arena - Vector3.new(0, 60, 0)))
			end
		end
		T.Wait(0.5)
	end
	T.Check(me:GetAttribute("InMinigame") == nil, "round ended")
	-- (everyone can be out a moment before the server posts the results)
	local results = T.WaitFor(function()
		for _, args in T.Sent(me, "MinigameState") do
			if args[1].Phase == "Results" then
				return args[1]
			end
		end
		return nil
	end, 10, "minigame results")
	T.Check(data.Cash > cash, key .. " paid a reward")
	T.Check(results ~= nil and #results.Results == 2, "results list both players")
	-- (if a meteor got us we respawn at home a few seconds later)
	T.WaitFor(function()
		local root = T.Root(me)
		return root and (root.Position - me:GetAttribute("PlotCenter")).Magnitude < 80
	end, 10, "sent home after the round")
	T.Check(T.Humanoid(me).WalkSpeed > 0, "can walk again after the round")
	T.WaitFor(function()
		return game:GetService("Workspace"):FindFirstChild("Minigame_" .. key) == nil
	end, 3, "arena cleanup")
end

for _, key in { "CoinRush", "FallingTiles", "MeteorShower", "LavaRise" } do
	add({
		Name = "minigame_" .. key,
		Run = function(T, place)
			T.Place = place
			playMinigame(T, key)
		end,
	})
end

---------------------------------------------------------------------------
-- UI: open every panel and click every button on screen
---------------------------------------------------------------------------
add({
	Name = "ui",
	MaxSeconds = 900,
	Run = function(T, place)
		local game, me = T.Boot(place)
		local buddy = T.AddPlayer("Buddy")
		T.Wait(6)
		local UI = T.Controller("UI")
		local gui = me.PlayerGui:FindFirstChild("MegaTycoonUI")
		T.Service("DataService"):AddCash(me, 1e6, false)
		local clicked = 0
		local function clickAll(root, skip)
			-- snapshot first: clicks can rebuild lists
			local list = {}
			for _, b in T.Buttons(root) do
				if T.IsShown(b) and not (skip and b:IsA("TextButton") and skip(b.Text)) then
					table.insert(list, b)
				end
			end
			for _, b in list do
				if b.Parent and T.IsShown(b) then
					T.Client(function()
						T.Engine.Click(b)
					end)
					clicked += 1
					T.Wait(0.15)
				end
			end
		end

		-- the side menu opens every panel
		local names = {}
		for name in UI.Panels do
			table.insert(names, name)
		end
		table.sort(names)
		T.Check(#names >= 10, "panels registered: " .. table.concat(names, ", "))
		local menu = gui:FindFirstChild("Menu")
		T.Check(menu ~= nil, "side menu exists")
		for _, b in T.Buttons(menu) do
			T.Client(function()
				T.Engine.Click(b)
			end)
			T.Wait(0.4)
			if UI.Current then
				T.Check(T.IsShown(UI.Panels[UI.Current].Frame), "panel " .. UI.Current .. " is visible after clicking its menu button")
			end
		end

		-- inside each panel: click everything (one level of tabs deep)
		local DANGEROUS = { "SHUTDOWN" }
		for _, name in names do
			T.Client(function()
				UI:Open(name)
			end)
			T.Wait(0.6)
			local frame = UI.Panels[name].Frame
			T.Check(T.IsShown(frame), name .. " opens")
			clickAll(frame, function(text)
				for _, word in DANGEROUS do
					if text:upper():find(word) then
						return true
					end
				end
				-- the close button is clicked last
				return text == "✕" or text == "X"
			end)
			if UI.Current ~= name then
				T.Client(function()
					UI:Open(name)
				end)
				T.Wait(0.3)
			end
			-- tabs may have shown new buttons
			clickAll(frame, function(text)
				return text:upper():find("SHUTDOWN") ~= nil
			end)
			T.Client(function()
				UI:Close()
			end)
			T.Wait(0.4)
			T.Check(UI.Current == nil, name .. " closes")
		end
		print("    clicked " .. clicked .. " buttons")
		T.Check(clicked > 40, "clicked lots of buttons (" .. clicked .. ")")
		-- keyboard shortcuts
		for _, key in { "G", "B", "R", "F2" } do
			T.Client(function()
				T.Engine.Input(Enum.KeyCode[key])
			end)
			T.Wait(0.3)
			T.Check(UI.Current ~= nil, key .. " opens a panel")
			T.Client(function()
				T.Engine.Input(Enum.KeyCode.Escape)
			end)
			T.Wait(0.3)
			T.Check(UI.Current == nil, "Esc closes the panel")
		end
		-- let any disasters / minigames the admin buttons started play out
		T.SetDt(0.5)
		T.Wait(200)
		T.Check(gui.Enabled and gui.Parent ~= nil, "HUD still fine")
	end,
})

---------------------------------------------------------------------------
-- Every effect / command the server can send the client
---------------------------------------------------------------------------
add({
	Name = "client_effects",
	Run = function(T, place)
		local game, me = T.Boot(place)
		local other = T.AddPlayer("Other")
		T.Wait(6)
		local pos = T.Root(me).Position
		local color = roblox.Color3.fromRGB(255, 100, 50)
		local effects = {
			{ "CashPop", { Position = pos, Amount = 100 } },
			{ "CashBurst", { Amount = 12345 } },
			{ "Purchase", { Position = pos, Color = color, Big = true } },
			{ "Purchase", { Position = nil, Color = color } },
			{ "BuildIn", { Model = T.Service("TycoonService"):GetPlot(me).Built.F1_1, Position = pos, Color = color } },
			{ "ButtonPop", { Position = pos, Color = color } },
			{ "Shockwave", { Position = pos, Color = color, Size = 80 } },
			{ "Confetti", {} },
			{ "Confetti", { Position = pos, Small = true } },
			{ "Rebirth", { Rebirths = 3 } },
			{ "CashRain", { Duration = 3 } },
			{ "CoinPop", { Position = pos } },
			{ "Error", {} },
			{ "PurchaseSound", {} },
			{ "WinSound", {} },
			{ "Flash", {} },
			{ "ShieldHit", { Center = pos, Radius = 50 } },
			{ "SecretFound", { Name = "Test", Count = 3, Total = 12, Color = color, Cash = 5000 } },
			{ "SpeedLines", { Duration = 1 } },
			{ "NotARealEffect", {} },
		}
		T.Server(function()
			local Remotes = T.Shared("Remotes")
			for _, e in effects do
				Remotes.VFX:FireAllClients(e[1], e[2])
			end
			local commands = {
				{ "fly", true },
				{ "fly", false },
				{ "noclip", true },
				{ "noclip", false },
				{ "view", other },
				{ "view", nil },
				{ "openadmin", "Logs" },
				{ "openfloors", 1 },
				{ "fling", Vector3.new(50, 80, 0) },
				{ "tornado", pos + Vector3.new(10, 0, 0) },
				{ "abduct", pos + Vector3.new(0, 50, 0), 2.5 },
				{ "launch", pos + Vector3.new(0, 200, 0) },
				{ "vaporized" },
				{ "unknowncommand" },
			}
			for _, c in commands do
				Remotes.ClientCommand:FireClient(me, table.unpack(c))
				T.Wait(0.3)
			end
			Remotes.Music:FireAllClients("play", { Id = "rbxassetid://1", Name = "Test" })
			Remotes.Music:FireAllClients("resume", {})
			Remotes.Notify:FireClient(me, { Text = "info", Type = "info" })
			Remotes.Notify:FireClient(me, { Text = "error", Type = "error", Duration = 1 })
			Remotes.Notify:FireClient(me, { Text = "success", Type = "success" })
			Remotes.Notify:FireClient(me, { Text = "odd", Type = "weird-type" })
			for i = 1, 12 do
				Remotes.Notify:FireClient(me, { Text = "spam " .. i })
			end
			Remotes.Announce:FireAllClients({ Title = "Hello", Text = "World", Color = color })
			Remotes.Announce:FireAllClients({ Title = "No color" })
			Remotes.TycoonUpdate:FireClient(me, { Type = "Disabled", Id = "F1_2", Seconds = 30 })
			Remotes.TycoonUpdate:FireClient(me, { Type = "Repaired", Id = "F1_2" })
			Remotes.TycoonUpdate:FireClient(me, { Type = "Secret", Id = "Summit" })
			Remotes.TycoonUpdate:FireClient(me, { Type = "Reset" })
		end, 30)
		T.Wait(15)
		T.Check(me.PlayerGui:FindFirstChild("MegaTycoonUI") ~= nil, "UI survived every effect")
	end,
})

---------------------------------------------------------------------------
-- Exploiters: garbage into every remote must never break the server
---------------------------------------------------------------------------
add({
	Name = "remote_fuzz",
	MaxSeconds = 900,
	AllowedWarnings = { "Ignored invalid", "DataStores unavailable", "Could not load data" },
	Run = function(T, place)
		T.Engine.Studio = false -- a live server: nobody is admin
		local game, me = T.Boot(place)
		local hacker = T.AddPlayer("Hacker")
		T.Wait(6)
		local DataService = T.Service("DataService")
		local data = DataService:Get(hacker)
		local startCash = data.Cash
		local deep = {}
		local node = deep
		for _ = 1, 25 do
			node.Next = {}
			node = node.Next
		end
		local payloads = {
			{},
			{ nil },
			{ true },
			{ 0 },
			{ -1 },
			{ 1e308 },
			{ 0 / 0 },
			{ math.huge },
			{ -math.huge },
			{ "" },
			{ "F1_1" },
			{ "F8_62" },
			{ "Roof_6" },
			{ "Secret_Summit" },
			{ string.rep("A", 5000) },
			{ "nan" },
			{ "inf" },
			{ "../../" },
			{ {} },
			{ { 1, 2, 3 } },
			{ { Text = "x", MusicVolume = 0 / 0, SFX = "yes", LowGraphics = 5 } },
			{ { MusicVolume = math.huge } },
			{ deep },
			{ hacker },
			{ game:GetService("Workspace") },
			{ me.UserId, true },
			{ hacker.UserId, true },
			{ 1, 9 },
			{ 1, 0 / 0 },
			{ "1", "9" },
			{ 99, 1 },
			{ me.UserId },
			{ "DoubleCash" },
			{ "LaunchNuke" },
			{ "CashHuge" },
			{ ";givecash me 1b" },
			{ "players" },
			{ "commands" },
		}
		local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes"):GetChildren()
		local fired = 0
		for _, remote in remotes do
			for _, args in payloads do
				if remote:IsA("RemoteEvent") then
					T.Engine.FireServerAs(hacker, remote, table.unpack(args))
				else
					T.Server(function()
						pcall(T.Engine.InvokeServerAs, hacker, remote, table.unpack(args))
					end)
				end
				fired += 1
			end
			T.Wait(0.2)
		end
		print("    fired " .. fired .. " garbage requests")
		-- NaN volume on its own (last write wins)
		T.Engine.FireServerAs(hacker, T.Remote("SaveSettings"), { MusicVolume = 0 / 0 })
		T.Wait(5)
		T.Check(finite(data.Cash) and finite(data.Vault) and finite(data.TotalEarned), "hacker's wallet is still valid")
		T.Check(finite(data.Settings.MusicVolume) and data.Settings.MusicVolume >= 0 and data.Settings.MusicVolume <= 1, "settings stay valid")
		T.Check(type(data.Settings.SFX) == "boolean" and type(data.Settings.LowGraphics) == "boolean", "settings keep their types")
		T.Check(data.Cash <= startCash + 1e6, "no free money from garbage (" .. tostring(data.Cash) .. ")")
		T.Check(hacker:GetAttribute("AdminRank") == 0 and data.Cash < 1e9, "non-admins can't run commands")
		T.Check(DataService:Get(me).Purchased.F1_1, "victim untouched")
		T.Check(me:GetAttribute("DuoHost") == nil, "can't force a duo")
		-- the server still works for normal players afterwards
		local ok = T.Client(function()
			return T.Remote("BuyItem"):InvokeServer(cheapestAvailable(T, DataService:Get(me)).Id)
		end)
		T.Check(ok == true, "server still serves normal players")
	end,
})

---------------------------------------------------------------------------
-- Daily rewards + codes (through the real panels)
---------------------------------------------------------------------------
add({
	Name = "rewards",
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local data = T.Service("DataService"):Get(me)
		local UI = T.Controller("UI")
		local function open(name)
			T.Client(function()
				UI:Open(name)
			end)
			T.Wait(1.2)
		end
		local function click(pattern)
			local button = T.FindButton(me.PlayerGui, pattern)
			T.Check(button ~= nil, "button " .. pattern)
			if button then
				T.Client(function()
					T.Engine.Click(button)
				end)
				T.Wait(0.5)
			end
		end
		open("Daily")
		local cash = data.Cash
		click("^CLAIM$")
		T.Check(data.Cash > cash and data.DailyStreak == 1, "daily reward claimed (day 1)")
		cash = data.Cash
		T.Wait(1.5)
		local cooldown = T.FindButton(me.PlayerGui, "%d+h")
		T.Check(cooldown ~= nil, "claim button shows the cooldown")
		T.Server(function()
			T.Service("RewardService"):ClaimDaily(me)
		end)
		T.Check(data.Cash == cash, "can't claim twice")
		-- next day (travel in time by moving the last claim back)
		local DataService = T.Service("DataService")
		data.LastDaily -= 20 * 3600 + 60
		DataService:Sync(me)
		open("Daily")
		click("^CLAIM$")
		T.Check(data.DailyStreak == 2, "streak continues the next day")
		-- skip two days: streak resets
		data.LastDaily -= 49 * 3600
		DataService:Sync(me)
		open("Daily")
		click("^CLAIM$")
		T.Check(data.DailyStreak == 1, "streak resets after 48h")
		T.Client(function()
			UI:Close()
		end)

		-- codes
		open("Codes")
		local box
		for _, d in me.PlayerGui:GetDescendants() do
			if d:IsA("TextBox") and T.IsShown(d) then
				box = d
			end
		end
		T.Check(box ~= nil, "code box on screen")
		local function redeem(code)
			box.Text = code
			cash = data.Cash
			click("REDEEM")
			T.Wait(2.1) -- server rate limit
		end
		redeem("  release ")
		T.Check(data.Cash > cash and data.RedeemedCodes.RELEASE, "code RELEASE (any case / spaces) works")
		redeem("RELEASE")
		T.Check(data.Cash == cash, "a code works once")
		T.Check(T.FindText(me.PlayerGui, "already redeemed") ~= nil, "panel says already redeemed")
		redeem("NOTACODE")
		T.Check(T.FindText(me.PlayerGui, "doesn't exist") ~= nil, "bad code message")
		redeem("BOOST")
		T.Check(data.BoostEnd > 0, "BOOST code gives a boost")
		-- spam is rate limited
		local okA = T.Client(function()
			return T.Remote("RedeemCode"):InvokeServer("MEGATYCOON")
		end)
		local okB, msgB = T.Client(function()
			return T.Remote("RedeemCode"):InvokeServer("THANKYOU")
		end)
		T.Check(okA == true and okB == false and tostring(msgB):find("Slow") ~= nil, "codes are rate limited")
	end,
})

---------------------------------------------------------------------------
-- Elevators + FLOORS menu
---------------------------------------------------------------------------
add({
	Name = "floors",
	Run = function(T, place)
		local game, me = T.Boot(place)
		local neighbour = T.AddPlayer("Neighbour")
		T.Wait(6)
		local TycoonService = T.Service("TycoonService")
		local TycoonBuilder = T.Service("TycoonBuilder")
		local Config = T.Shared("Config")
		local plot = TycoonService:GetPlot(me)
		local UI = T.Controller("UI")
		-- locked floors can't be visited
		T.Client(function()
			T.Remote("TeleportFloor"):FireServer(plot.Index, 3)
		end)
		T.Wait(0.5)
		T.Check(T.Noticed(me, "isn't built"), "locked floor refused")
		T.Admin(me, ";unlockfloor me 9")
		waitBuilt(T, plot)
		-- the elevator prompt on floor 1 opens the FLOORS menu
		local prompt
		for _, d in plot.Built.F1_1:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				prompt = d
			end
		end
		T.Check(prompt ~= nil, "floor 1 elevator has a prompt")
		T.Engine.TriggerPrompt(prompt, me)
		T.Wait(0.5)
		T.Check(UI.Current == "Floors", "elevator opens the FLOORS menu")
		for floor = 1, Config.Tycoon.Floors + 1 do
			T.Client(function()
				T.Controller("Build"):OpenFloors(nil)
			end)
			T.Wait(0.5)
			local button
			for _, d in me.PlayerGui:GetDescendants() do
				if d.Name == "Floor" .. floor and d:IsA("TextButton") then
					button = d
				end
			end
			T.Check(button ~= nil and not button.Text:find("🔒"), "floor " .. floor .. " button unlocked")
			if button then
				T.Client(function()
					T.Engine.Click(button)
				end)
				T.Wait(0.5)
				local y = T.Root(me).Position.Y
				local floorY = TycoonBuilder.FloorCF(plot, floor).Position.Y
				T.Check(math.abs(y - floorY - 4) < 1, ("teleported to floor %d (y=%.1f, floor at %.1f)"):format(floor, y, floorY))
			end
		end
		-- visiting a neighbour's tower: only built floors work
		T.Client(function()
			T.Remote("TeleportFloor"):FireServer(TycoonService:GetPlot(neighbour).Index, 1)
		end)
		T.Wait(0.5)
		local npos = TycoonService:GetPlot(neighbour).TowerCF.Position
		T.Check((T.Root(me).Position - npos).Magnitude < 70, "can visit a neighbour's floor 1")
		T.Client(function()
			T.Remote("TeleportFloor"):FireServer(TycoonService:GetPlot(neighbour).Index, 5)
		end)
		T.Wait(0.5)
		T.Check(T.Noticed(me, "isn't built"), "can't visit a neighbour's unbuilt floor")
		-- HOME button
		T.Client(function()
			T.Remote("GoHome"):FireServer()
		end)
		T.Wait(0.5)
		T.Check((T.Root(me).Position - plot.SpawnCFrame.Position).Magnitude < 1, "HOME teleports to the tower gate")
	end,
})

---------------------------------------------------------------------------
-- A full 8-player server with maxed towers: performance + nuke on everyone
---------------------------------------------------------------------------
add({
	Name = "full_server",
	MaxSeconds = 1200,
	Run = function(T, place)
		local clock = os.clock()
		local game, me = T.Boot(place)
		local players = { me }
		for i = 1, 7 do
			table.insert(players, T.AddPlayer("Player" .. i))
		end
		T.Wait(6)
		local TycoonService = T.Service("TycoonService")
		local TycoonItems = T.Shared("TycoonItems")
		for _, p in players do
			T.Check(p:GetAttribute("Plot") ~= nil, p.Name .. " has a tower")
			TycoonService:UnlockAll(p)
		end
		local buildStart = T.Engine.Now
		for _, p in players do
			waitBuilt(T, TycoonService:GetPlot(p))
		end
		local buildTime = T.Engine.Now - buildStart
		T.Check(buildTime < 15, ("8 maxed towers build in %.1fs of game time"):format(buildTime))
		local ws = game:GetService("Workspace")
		local towerParts = #ws:FindFirstChild("Tycoons"):GetDescendants()
		print(("    8 maxed towers: %d instances, built in %.1fs"):format(towerParts, buildTime))
		T.Check(towerParts < 120000, "instance count is sane (" .. towerParts .. ")")
		for _, p in players do
			T.Check(count(TycoonService:GetPlot(p).Built) >= TycoonItems.BuyableCount, p.Name .. " tower complete")
		end
		-- client: drops stay bounded on a full tower
		T.Admin(me, ";floor 1")
		local maxDrops = 0
		for _ = 1, 60 do
			T.Wait(0.5)
			maxDrops = math.max(maxDrops, #ws:FindFirstChild("LocalDrops"):GetChildren())
		end
		print("    max client drops alive: " .. maxDrops)
		T.Check(maxDrops > 5, "drops render on the client")
		T.Check(maxDrops <= 200, "client drops are capped")
		-- a nuke over 8 maxed towers
		local stepClock = os.clock()
		T.Admin(me, ";nuke")
		T.WaitFor(function()
			return ws:GetAttribute("Disaster") == nil and T.Engine.Now > buildStart + 60
		end, 120, "nuke over the full server")
		local wrecked = 0
		for _, p in players do
			wrecked += TycoonService:WreckedCount(TycoonService:GetPlot(p))
		end
		print(("    nuke wrecked %d items on 8 towers in %.1fs real time"):format(wrecked, os.clock() - stepClock))
		T.Check(wrecked == 0, "maxed towers own the Nuke Shield (no damage)")
		T.Check(os.clock() - clock < 120, ("whole scenario runs fast (%.1fs)"):format(os.clock() - clock))
	end,
})

---------------------------------------------------------------------------
-- Settings are saved and come back when you rejoin (client restarts)
---------------------------------------------------------------------------
add({
	Name = "settings_rejoin",
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Fan", UserId = 4242 })
		T.Wait(6)
		local UI = T.Controller("UI")
		T.Client(function()
			UI:Open("Settings")
		end)
		T.Wait(0.6)
		-- find the toggle rows
		local function toggleFor(label: string)
			for _, d in me.PlayerGui:GetDescendants() do
				if d:IsA("TextLabel") and d.Text:find(label, 1, true) and T.IsShown(d) then
					return d.Parent:FindFirstChildWhichIsA("TextButton")
				end
			end
			return nil
		end
		local low = toggleFor("Low Graphics")
		local sfx = toggleFor("Sound Effects")
		T.Check(low ~= nil and low.Text == "OFF", "low graphics starts OFF")
		T.Check(sfx ~= nil and sfx.Text == "ON", "sound effects start ON")
		T.Client(function()
			T.Engine.Click(low)
			T.Engine.Click(sfx)
		end)
		T.Wait(0.5)
		T.Check(T.Controller("Animator"):IsLowGraphics(), "low graphics applied")
		local data = T.Service("DataService"):Get(me)
		T.Check(data.Settings.LowGraphics == true and data.Settings.SFX == false, "settings saved on the server")
		-- particles made later are quiet too
		T.Wait(1)
		local emitter = T.Client(function()
			local part = T.Engine.Instance.new("Part")
			part.Parent = game:GetService("Workspace")
			local e = T.Engine.Instance.new("ParticleEmitter")
			e.Parent = part
			return e
		end)
		T.Wait(0.3)
		T.Check(emitter and emitter.Enabled == false, "new particle emitters are disabled in low graphics")

		-- quick close + reopen must leave the panel open
		T.Client(function()
			UI:Close()
			UI:Open("Settings")
		end)
		T.Wait(0.6)
		T.Check(UI.Current == "Settings" and T.IsShown(UI.Panels.Settings.Frame), "panel stays open after a quick close/reopen")

		-- rejoin: the settings come back
		T.LeaveClient()
		T.Wait(2)
		me = T.StartClient("Fan", { UserId = 4242 })
		T.Wait(8)
		T.Check(me:GetAttribute("LowGraphics") == true, "LowGraphics restored from the save")
		T.Check(T.Controller("Animator"):IsLowGraphics(), "client starts in low graphics")
		UI = T.Controller("UI")
		T.Client(function()
			UI:Open("Settings")
		end)
		T.Wait(0.6)
		low = toggleFor("Low Graphics")
		sfx = toggleFor("Sound Effects")
		T.Check(low ~= nil and low.Text == "ON", "toggle shows the saved low graphics")
		T.Check(sfx ~= nil and sfx.Text == "OFF", "toggle shows the saved sound setting")
		T.Check(#me.PlayerGui:GetChildren() >= 2, "the new client built its UI")
	end,
})

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
add({
	Name = "quests",
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Quester", UserId = 6001 })
		T.Wait(6)
		local QuestService = T.Service("QuestService")
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local data = DataService:Get(me)
		local Quests = T.Controller("Quests")
		T.Check(#data.Quests.List == 3, "new players get 3 quests (" .. #data.Quests.List .. ")")
		T.Check(#Quests.List == 3, "client tracker shows 3 quests")
		local types = {}
		for _, q in data.Quests.List do
			T.Check(not types[q.Type], "no duplicate quest types")
			types[q.Type] = true
		end
		-- buy a dropper so income quests are possible, then set known quests
		T.Client(function()
			return T.Remote("BuyItem"):InvokeServer(cheapestAvailable(T, data).Id)
		end)
		data.Quests.List = {
			{ Type = "Buy", Target = 3, Progress = 0 },
			{ Type = "Collect", Target = 2, Progress = 0 },
			{ Type = "Earn", Target = 30, Progress = 0 },
		}
		QuestService:Refresh(me)
		T.Wait(1.5)
		T.Check(#Quests.List == 3 and Quests.List[1].Type == "Buy", "client got the quest list")
		-- claiming early fails
		local early = T.Client(function()
			return T.Remote("ClaimQuest"):InvokeServer(1)
		end)
		T.Check(early == false, "can't claim an unfinished quest")
		-- do the quests
		DataService:AddCash(me, 1e4, false)
		for _ = 1, 3 do
			T.Client(function()
				return T.Remote("BuyItem"):InvokeServer(cheapestAvailable(T, data).Id)
			end)
		end
		T.Check(data.Quests.List[1].Progress == 3, "Buy quest counts purchases")
		T.Check(T.Noticed(me, "Quest complete"), "quest complete toast")
		T.Wait(1.5)
		T.Check(Quests:ReadyCount() >= 1, "tracker shows a quest ready")
		local claimButton = T.WaitFor(function()
			return T.FindButton(me.PlayerGui, "^CLAIM$")
		end, 3, "CLAIM button")
		local cash = data.Cash
		if claimButton then
			T.Client(function()
				T.Engine.Click(claimButton)
			end)
			T.Wait(1)
		end
		T.Check(data.Cash > cash, "claiming pays the reward")
		T.Check(data.Quests.Claimed == 1, "claimed quests are counted")
		T.Check(#data.Quests.List == 3, "a new quest replaces the claimed one")
		-- vault collect + earn
		for _, d in TycoonService:GetPlot(me).Built.F1_1:GetDescendants() do
			if d.Name == "VaultPad" then
				T.Wait(3)
				T.Engine.Touch(d, me)
				T.Wait(1.5)
				T.Engine.Touch(d, me)
			end
		end
		local collect, earn
		for _, q in data.Quests.List do
			if q.Type == "Collect" then
				collect = q
			elseif q.Type == "Earn" then
				earn = q
			end
		end
		T.Check(collect and collect.Progress == 2, "Collect quest counts vault collections")
		T.WaitFor(function()
			return earn.Progress >= earn.Target
		end, 30, "Earn quest from tower income")
		-- every other kind of quest progresses from the real game event
		data.Quests.List = {
			{ Type = "Floor", Target = 2, Progress = 1 },
			{ Type = "Survive", Target = 1, Progress = 0 },
			{ Type = "Secret", Target = 1, Progress = 0 },
		}
		QuestService:Refresh(me)
		DataService:AddCash(me, 1e9, false)
		T.Client(function()
			T.Remote("BuyAll"):FireServer()
		end)
		T.Wait(1)
		T.Check(data.Quests.List[1].Progress >= 2, "Floor quest completes when floor 2 is unlocked")
		T.Admin(me, ";meteors")
		T.Wait(3)
		T.Admin(me, ";stopdisaster")
		T.WaitFor(function()
			return game:GetService("Workspace"):GetAttribute("Disaster") == nil
		end, 10, "storm stop")
		T.Wait(1)
		T.Check(data.Quests.List[2].Progress == 1 or T.Humanoid(me).Health <= 0, "Survive quest after a disaster")
		T.Server(function()
			T.Service("SecretService"):Find(me, "Board", true)
		end)
		T.Check(data.Quests.List[3].Progress == 1, "Secret quest")
		data.Quests.List = {
			{ Type = "Obby", Target = 1, Progress = 0 },
			{ Type = "Minigame", Target = 1, Progress = 0 },
			{ Type = "Buy", Target = 1, Progress = 0 },
		}
		QuestService:Refresh(me)
		T.Server(function()
			T.Service("ObbyService"):_finish(me)
		end)
		T.Check(data.Quests.List[1].Progress == 1, "Obby quest")
		-- claim everything that's done
		local claimed = data.Quests.Claimed
		T.Client(function()
			T.Remote("ClaimQuest"):InvokeServer(1)
		end)
		T.Check(data.Quests.Claimed == claimed + 1, "claim by slot")
		-- quests are saved and come back after rejoining
		local before = {}
		for i, q in data.Quests.List do
			before[i] = q.Type .. ":" .. q.Target
		end
		T.LeaveClient()
		T.Wait(1)
		me = T.StartClient("Quester", { UserId = 6001 })
		T.Wait(8)
		data = DataService:Get(me)
		local same = #data.Quests.List == #before
		for i, q in data.Quests.List do
			same = same and before[i] == q.Type .. ":" .. q.Target
		end
		T.Check(same, "quests saved across sessions")
		T.Check(data.Quests.Claimed == claimed + 1, "claimed count saved")
		T.Check(#T.Controller("Quests").List == #data.Quests.List, "rejoined client shows the quests")
		-- a rebirth replaces floor quests that no longer fit
		data.Quests.List = { { Type = "Floor", Target = 5, Progress = 3 } }
		T.Server(function()
			TycoonService:Rebirth(me, true)
		end)
		T.Wait(1)
		for _, q in data.Quests.List do
			T.Check(q.Type ~= "Floor" or q.Target == 2, "floor quest re-targeted after rebirth")
		end
		T.Check(#data.Quests.List == 3, "still 3 quests after rebirth")
		-- two claims sent before the first update arrives both pay (claims go by type)
		data.Quests.List = {
			{ Type = "Obby", Target = 1, Progress = 1 },
			{ Type = "Minigame", Target = 1, Progress = 1 },
			{ Type = "Buy", Target = 5, Progress = 0 },
		}
		QuestService:Refresh(me)
		T.Wait(1.5)
		claimed = data.Quests.Claimed
		local both = T.Client(function()
			local first = T.Remote("ClaimQuest"):InvokeServer("Obby")
			local second = T.Remote("ClaimQuest"):InvokeServer("Minigame")
			return first and second
		end)
		T.Check(both == true and data.Quests.Claimed == claimed + 2, "back-to-back claims both pay")
		T.Check(#data.Quests.List == 3 and data.Quests.List[3].Type == "Buy", "unclaimed quests keep their place")
		local missing = T.Client(function()
			return T.Remote("ClaimQuest"):InvokeServer("Nope")
		end)
		T.Check(missing == false, "claiming a quest you don't have fails")
	end,
})

---------------------------------------------------------------------------
-- Playtime gifts
---------------------------------------------------------------------------
add({
	Name = "gifts",
	MaxSeconds = 2 * 3600,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Gifter", UserId = 6300 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local data = T.Service("DataService"):Get(me)
		local Gifts = T.Controller("Gifts")
		local button = me.PlayerGui:FindFirstChild("GiftButton", true)
		T.Check(button ~= nil and T.IsShown(button), "gift button on screen")
		T.Check(button and button.Text:find("in") ~= nil, "shows a countdown: " .. (button and button.Text or "?"))
		local okEarly = T.Client(function()
			return T.Remote("ClaimGift"):InvokeServer()
		end)
		T.Check(okEarly == false, "gift can't be opened early")
		T.SetDt(0.5)
		local total = #Config.Gifts.Minutes
		for index = 1, total do
			T.WaitFor(function()
				return Gifts:IsReady()
			end, 20 * 60, "gift " .. index)
			T.Wait(1.5)
			T.Check(button.Text:find("OPEN") ~= nil, "gift " .. index .. " button says OPEN")
			local cash = data.Cash
			T.Client(function()
				T.Engine.Click(button)
			end)
			T.Wait(0.5)
			T.Check(data.Cash > cash, "gift " .. index .. " paid cash")
		end
		T.Check(data.BoostEnd > 0, "last gift gives a boost")
		T.Wait(1.5)
		T.Check(not T.IsShown(button), "gift button hides after the last gift")
		local okMore = T.Client(function()
			return T.Remote("ClaimGift"):InvokeServer()
		end)
		T.Check(okMore == false, "no more gifts today")
		T.Check(T.Engine.Now < 70 * 60 + 60, "all gifts within ~an hour")

		-- leaving and rejoining doesn't restart the gifts
		T.LeaveClient()
		T.Wait(1)
		me = T.StartClient("Gifter", { UserId = 6300 })
		T.Wait(8)
		local DataService = T.Service("DataService")
		local GiftService = T.Service("GiftService")
		data = DataService:Get(me)
		T.Check(data.Gifts.Index == total + 1 and GiftService:GetState(me).ReadyIn == -1, "rejoining keeps the opened gifts")
		T.Check(not T.IsShown(me.PlayerGui:FindFirstChild("GiftButton", true)), "and no gift button")
		-- a new day starts over
		data.Gifts.Day -= 1
		T.Wait(35)
		T.Check(data.Gifts.Index == 1 and GiftService:GetState(me).ReadyIn > 0, "a new day starts the gifts over")
		T.Check(T.Controller("Gifts").State and T.Controller("Gifts").State.Index == 1, "and the client is told")
	end,
})

---------------------------------------------------------------------------
-- Guide beam
---------------------------------------------------------------------------
add({
	Name = "guide",
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local Guide = T.Controller("Guide")
		local DataService = T.Service("DataService")
		local TycoonItems = T.Shared("TycoonItems")
		local data = DataService:Get(me)
		local first = cheapestAvailable(T, data)
		T.Wait(1)
		T.Check(Guide.Target and Guide.Target.Kind == "Buy" and Guide.Target.Id == first.Id, "guide points at the first affordable button (" .. tostring(Guide.Target and Guide.Target.Id) .. ")")
		local anchor = game:GetService("Workspace"):FindFirstChild("GuideTarget")
		local beam = anchor and anchor:FindFirstChildOfClass("Beam")
		T.Check(beam and beam.Enabled and beam.Attachment0 and beam.Attachment0.Parent == T.Root(me), "beam goes from the player to the button")
		-- buy it by walking onto the pad
		local plot = T.Service("TycoonService"):GetPlot(me)
		T.Engine.Touch(plot.ButtonObjs[first.Id].Pad, me)
		T.Wait(1)
		T.Check(data.Purchased[first.Id], "bought the guided button")
		-- broke: nothing to point at, until the vault would pay for the next one
		DataService:SetCash(me, 0)
		T.Wait(1)
		T.Check(Guide.Target == nil or Guide.Target.Kind == "Vault", "no button target when broke")
		local next = cheapestAvailable(T, data)
		T.WaitFor(function()
			return data.Vault >= next.Cost
		end, 120, "vault to fill")
		T.Wait(1)
		T.Check(Guide.Target and Guide.Target.Kind == "Vault", "guide points at the vault when collecting lets you buy")
		-- the setting turns it off
		T.Client(function()
			T.Remote("SaveSettings"):FireServer({ Guide = false })
		end)
		T.Service("DataService"):Sync(me)
		T.Wait(1)
		T.Check(Guide.Target == nil and not beam.Enabled, "guide can be turned off")
		T.Client(function()
			T.Remote("SaveSettings"):FireServer({ Guide = true })
		end)
		T.Service("DataService"):Sync(me)
		-- far from home: hidden
		T.MoveTo(me, CFrame.new(0, 5, 0))
		T.Wait(1)
		T.Check(Guide.Target == nil, "guide hidden away from your tower")
	end,
})

---------------------------------------------------------------------------
-- Session locks: hopping servers never loses or rolls back progress
---------------------------------------------------------------------------
add({
	Name = "session_lock",
	AllowedWarnings = { "Took over a session lock", "open in another server" },
	Run = function(T, place)
		local game = T.Boot(place, { Client = false })
		local Config = T.Shared("Config")
		local DataService = T.Service("DataService")
		local db = T.Engine.DataStores[Config.DataStoreName]
		local function now()
			return math.floor(T.Engine.EpochBase + T.Engine.Now)
		end

		-- 1) another server still has the player: wait until it lets go
		db.Player_9001 = { Cash = 777, Purchased = { F1_1 = true }, Session = { Job = "other-server", Time = now() } }
		local hopper = T.AddPlayer("Hopper", { UserId = 9001 })
		T.Wait(2)
		T.Check(not hopper:GetAttribute("DataLoaded"), "waits while another server holds the save")
		-- the old server finishes its leave-save (newer progress) and releases the lock
		db.Player_9001 = { Cash = 888, Purchased = { F1_1 = true } }
		T.WaitFor(function()
			return hopper:GetAttribute("DataLoaded")
		end, 10, "load after the other server released")
		T.Check(DataService:Get(hopper).Cash == 888, "got the old server's final save (no rollback)")
		T.Check(db.Player_9001.Session and db.Player_9001.Session.Job == "sim-job", "this server holds the lock now")

		-- 2) a stale lock (that server crashed) is taken over right away
		db.Player_9002 = { Cash = 55, Purchased = { F1_1 = true }, Session = { Job = "dead-server", Time = now() - 3600 } }
		local crashed = T.AddPlayer("Crashed", { UserId = 9002 })
		T.Wait(2)
		T.Check(crashed:GetAttribute("DataLoaded") and DataService:Get(crashed).Cash == 55, "stale lock taken over immediately")

		-- 3) a lock that's never released: taken over after a while
		db.Player_9003 = { Cash = 66, Purchased = { F1_1 = true }, Session = { Job = "stuck-server", Time = now() } }
		local stuck = T.AddPlayer("Stuck", { UserId = 9003 })
		T.WaitFor(function()
			return stuck:GetAttribute("DataLoaded")
		end, 30, "stuck lock takeover")
		T.Check(T.Warned("Took over a session lock"), "takeover is logged")

		-- 4) another server takes OUR player: stop saving, never overwrite
		db.Player_9001.Session = { Job = "new-server", Time = now() }
		db.Player_9001.Cash = 999
		DataService:AddCash(hopper, 5, false)
		T.Server(function()
			DataService:Save(hopper)
		end)
		T.Check(db.Player_9001.Cash == 999, "lost lock: the other server's data is kept")
		T.Check(T.Warned("open in another server"), "lost lock is logged")
		T.Engine.RemovePlayer(hopper)
		T.Wait(1)
		T.Check(db.Player_9001.Cash == 999 and db.Player_9001.Session.Job == "new-server", "leaving doesn't overwrite it either")

		-- 5) a normal leave releases the lock (and saves)
		DataService:AddCash(crashed, 45, false)
		T.Engine.RemovePlayer(crashed)
		T.Wait(1)
		T.Check(db.Player_9002.Session == nil, "leaving releases the lock")
		T.Check(db.Player_9002.Cash == 100, "and saves the latest data")
		-- autosave keeps the lock fresh
		T.SetDt(1)
		T.Wait(100)
		T.Check(db.Player_9003.Session and now() - db.Player_9003.Session.Time < 100, "autosave refreshes the lock")
	end,
})

---------------------------------------------------------------------------
-- Premium + friends bonus, and messages that arrive during the loading screen
---------------------------------------------------------------------------
add({
	Name = "social_bonus",
	Run = function(T, place)
		T.Engine.Friends[3001] = { [3002] = true, [3003] = true }
		local game, me = T.Boot(place, { Name = "Social", UserId = 3001 })
		T.Wait(6)
		-- the welcome toast was sent during the loading screen: still shown after it
		T.Check(T.FindText(me.PlayerGui, "is yours") ~= nil, "welcome message visible after the loading screen")
		local Config = T.Shared("Config")
		local base = me:GetAttribute("Multiplier")
		T.Check(base == 1, "no bonus alone")
		T.AddPlayer("Friend1", { UserId = 3002 })
		T.Wait(2)
		T.Check(me:GetAttribute("FriendsHere") == 1, "friend detected")
		T.Check(math.abs(me:GetAttribute("Multiplier") - (1 + Config.Bonuses.FriendPercent / 100)) < 1e-9, "+10% for a friend in the server")
		local friend2 = T.AddPlayer("Friend2", { UserId = 3003 })
		local stranger = T.AddPlayer("Stranger", { UserId = 3004 })
		T.Wait(2)
		T.Check(me:GetAttribute("FriendsHere") == 2, "two friends, the stranger doesn't count")
		T.Check(stranger:GetAttribute("FriendsHere") == 0, "stranger has no friends here")
		T.Engine.RemovePlayer(friend2)
		T.Wait(1)
		T.Check(me:GetAttribute("FriendsHere") == 1, "friend leaving lowers the bonus")
		-- premium
		me.MembershipType = Enum.MembershipType.Premium
		T.Server(function()
			T.Engine.FireIfExists(game:GetService("Players"), "PlayerMembershipChanged", me)
		end)
		T.Wait(0.5)
		local expected = (1 + Config.Bonuses.PremiumPercent / 100) * (1 + Config.Bonuses.FriendPercent / 100)
		T.Check(math.abs(me:GetAttribute("Multiplier") - expected) < 1e-9, "Premium adds +10%")
		T.Wait(1)
		T.Check(T.FindText(me.PlayerGui, "⭐%+10%%") ~= nil and T.FindText(me.PlayerGui, "👫%+10%%") ~= nil, "HUD shows the bonuses")
		-- offline earnings don't include temporary social bonuses
		T.Check(T.Service("TycoonService"):GetOfflineIncome(me) == T.Shared("TycoonItems").ComputeIncome(T.Service("DataService"):Get(me).Purchased, nil, {}, false), "offline income ignores social bonuses")
	end,
})

---------------------------------------------------------------------------
-- A phone with a wrong clock still shows the right timers
---------------------------------------------------------------------------
add({
	Name = "client_clock",
	Run = function(T, place)
		T.Engine.ClientClockSkew = -3 * 3600 -- device clock 3 hours behind
		local game, me = T.Boot(place)
		T.Wait(6)
		T.Server(function()
			T.Service("DataService"):AddBoost(me, 15 * 60)
		end)
		T.Wait(1.5)
		local label = T.FindText(me.PlayerGui, "2x Boost")
		T.Check(label ~= nil, "boost timer shown")
		if label then
			local minutes = tonumber(label.Text:match("(%d+):%d%d"))
			T.Check(minutes ~= nil and minutes >= 14 and minutes <= 15, "boost timer is right despite the device clock (" .. label.Text .. ")")
		end
		-- the daily reward is available (server time), not "come back in 3h"
		T.Client(function()
			T.Controller("UI"):Open("Daily")
		end)
		T.Wait(1.5)
		T.Check(T.FindButton(me.PlayerGui, "^CLAIM$") ~= nil, "daily claim button available")
	end,
})

---------------------------------------------------------------------------
-- Exploiters faking touches from across the map get nothing
---------------------------------------------------------------------------
add({
	Name = "touch_exploits",
	Run = function(T, place)
		local game, me = T.Boot(place)
		local cheater = T.AddPlayer("Cheater")
		T.Wait(6)
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local data = DataService:Get(cheater)
		T.MoveTo(cheater, CFrame.new(0, 5, 0)) -- the lobby
		local cash = data.Cash
		-- every secret, from the lobby
		for _, model in game:GetService("Workspace"):FindFirstChild("Secrets"):GetChildren() do
			T.Engine.RemoteTouch(model:FindFirstChild("Hitbox"), cheater)
		end
		T.Wait(0.5)
		T.Check(count(data.Secrets) == 0 and data.Cash == cash, "remote secret touches give nothing")
		-- obby checkpoints + finish
		local obby = game:GetService("Workspace"):FindFirstChild("Obby")
		for _, d in obby:GetDescendants() do
			-- (not the kill bricks: those only ever hurt whoever touches them)
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon and not d:GetAttribute("Kill") then
				T.Engine.RemoteTouch(d, cheater)
			end
		end
		T.Wait(0.5)
		T.Check((cheater:GetAttribute("ObbyStage") or 0) == 0 and data.ObbyCompletions == 0, "remote obby touches give nothing")
		-- own tower buttons + vault from the lobby
		DataService:AddCash(cheater, 1e6, false)
		local plot = TycoonService:GetPlot(cheater)
		local owned = count(data.Purchased)
		for _, button in plot.ButtonObjs do
			T.Engine.RemoteTouch(button.Pad, cheater)
		end
		T.Wait(1)
		T.Check(count(data.Purchased) == owned, "remote button touches buy nothing")
		-- ...but walking onto them works
		local id, button = next(plot.ButtonObjs)
		T.Engine.Touch(button.Pad, cheater)
		T.Wait(1)
		T.Check(data.Purchased[id], "walking onto a button still buys it")
		-- the cloud launch pad
		local launches = #T.Sent(cheater, "ClientCommand")
		for _, pad in T.Service("WorldBuilder").LaunchPads do
			T.Engine.RemoteTouch(pad.Part, cheater)
		end
		T.Wait(0.5)
		T.Check(#T.Sent(cheater, "ClientCommand") == launches, "remote launch pad touches do nothing")
	end,
})

---------------------------------------------------------------------------
-- Automatic cash events
---------------------------------------------------------------------------
add({
	Name = "auto_event",
	MaxSeconds = 2 * 3600,
	Run = function(T, place)
		local game, me = T.Boot(place)
		local ws = game:GetService("Workspace")
		local Config = T.Shared("Config")
		local AE = Config.AutoEvents
		T.SetDt(2)
		T.Wait(AE.EveryMinutes * 60 - 30)
		T.Check(ws:GetAttribute("EventMultiplier") == 1, "no event before the first one is due")
		T.WaitFor(function()
			return ws:GetAttribute("EventMultiplier") == AE.Multiplier
		end, 90, "first auto event")
		T.Check(me:GetAttribute("Multiplier") == AE.Multiplier, "the event multiplies income")
		T.Wait(5)
		T.Check(T.FindText(me.PlayerGui, "x Event") ~= nil, "HUD shows the event timer")
		T.WaitFor(function()
			return ws:GetAttribute("EventMultiplier") == 1
		end, AE.DurationMinutes * 60 + 30, "event end")
		T.Check(me:GetAttribute("Multiplier") == 1, "income back to normal")
		-- an admin event running when the next one is due: no stacking
		T.Wait(AE.EveryMinutes * 60 - AE.DurationMinutes * 60 - 120)
		T.Admin(me, ";doublecash 10 3")
		T.Wait(240)
		T.Check(ws:GetAttribute("EventMultiplier") == 3, "auto event doesn't replace an admin event")
	end,
})

add({
	Name = "lava_rise",
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Climber" })
		local lazy = T.AddPlayer("Lazy")
		T.Wait(6)
		T.Admin(me, ";minigame LavaRise")
		T.Wait(2)
		T.Engine.FireServerAs(lazy, T.Remote("MinigameJoin"))
		T.Engine.FireServerAs(me, T.Remote("MinigameJoin"))
		T.WaitFor(function()
			return me:GetAttribute("InMinigame") and lazy:GetAttribute("InMinigame")
		end, 30, "both in the arena")
		local folder = game:GetService("Workspace"):FindFirstChild("Minigame_LavaRise")
		local summit = folder and folder:FindFirstChild("Summit")
		T.Check(summit ~= nil, "spiral tower with a summit")
		-- climb to the top; the lazy one stays on the floor
		T.Wait(4)
		T.MoveTo(me, CFrame.new(summit.Position + Vector3.new(0, 4, 0)))
		T.WaitFor(function()
			return lazy:GetAttribute("InMinigame") == nil
		end, 20, "lava to catch the player on the floor")
		T.Check(T.Noticed(lazy, "lava"), "eliminated by the lava")
		T.WaitFor(function()
			return me:GetAttribute("InMinigame") == nil
		end, 10, "round end")
		local results
		for _, args in T.Sent(me, "MinigameState") do
			if args[1].Phase == "Results" then
				results = args[1]
			end
		end
		local winner = results and results.Results[1]
		T.Check(winner and winner.Name == "Climber" and winner.Winner, "the climber wins")
	end,
})

add({
	Name = "earthquake",
	Run = function(T, place)
		local game, me = T.Boot(place)
		local sheltered = T.AddPlayer("Sheltered")
		T.Wait(6)
		local TycoonService = T.Service("TycoonService")
		local DataService = T.Service("DataService")
		TycoonService:UnlockAll(me, 1)
		local plot = TycoonService:GetPlot(me)
		waitBuilt(T, plot)
		local shelter = T.Service("WorldBuilder").Shelter
		T.MoveTo(sheltered, CFrame.new(shelter.CFrame.Position - Vector3.new(0, shelter.Size.Y / 2 - 3, 0)))
		T.MoveTo(me, CFrame.new(60, 4, 60))
		local since = T.Engine.Now
		T.Check(T.Admin(me, ";quake"), "earthquake command")
		local ws = game:GetService("Workspace")
		T.WaitFor(function()
			return ws:GetAttribute("Disaster") == "Earthquake"
		end, 5, "quake start")
		T.Wait(4)
		local folder = ws:FindFirstChild("Disasters")
		local geodes, cracks = 0, 0
		for _, child in folder:GetChildren() do
			if child.Name == "Crystal" then
				geodes += 1
			elseif child.Name == "Crack" then
				cracks += 1
			end
		end
		T.Check(geodes > 0, "cash geodes dug up (" .. geodes .. ")")
		T.Check(cracks > 0, "the ground cracks")
		local geode = folder:FindFirstChild("Crystal")
		if geode then
			local cash = DataService:Get(me).Cash
			T.Engine.Touch(geode, me)
			T.Wait(0.3)
			T.Check(DataService:Get(me).Cash > cash, "geodes pay out")
			T.MoveTo(me, CFrame.new(60, 4, 60))
		end
		T.WaitFor(function()
			return ws:GetAttribute("Disaster") == nil
		end, 40, "quake end")
		local shocks = 0
		for _, args in T.Sent(me, "Disaster", since) do
			if args[1].Phase == "Shock" then
				shocks += 1
			end
		end
		T.Check(shocks >= 6, "several shocks (" .. shocks .. ")")
		T.Check(T.Humanoid(me).Health < 100, "exposed player got hurt")
		T.Check(T.Humanoid(sheltered).Health == 100, "the bunker protects")
		T.Check(TycoonService:WreckedCount(plot) > 0, "unshielded tower got cracked")
		T.Wait(2)
		local left = 0
		for _, child in folder:GetChildren() do
			if child.Name == "Crack" then
				left += 1
			end
		end
		T.Check(left == 0, "cracks close afterwards")
	end,
})

---------------------------------------------------------------------------
-- Soak: a 5-hour server with bots coming and going, random disasters and
-- minigames. Nothing may error, leak instances or corrupt data.
---------------------------------------------------------------------------
add({
	Name = "soak",
	Slow = true,
	MaxSeconds = 6 * 3600,
	AllowedWarnings = { "DataStores unavailable", "Could not load data", "Took over a session lock" },
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.SetDt(2)
		local ws = game:GetService("Workspace")
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local bots = {}
		local nextId = 20000
		local function join()
			nextId += 1
			local bot = T.AddPlayer("Bot" .. nextId, { UserId = 20000 + (nextId % 6) })
			table.insert(bots, bot)
		end
		for _ = 1, 4 do
			join()
		end
		T.Wait(30)
		-- towers grow and shrink as bots buy, leave and rejoin; everything
		-- else in the world (effects, collectibles, rubble...) must not pile up
		local function outsideTowers(): number
			return #ws:GetDescendants() - #ws:FindFirstChild("Tycoons"):GetDescendants()
		end
		local baseline = outsideTowers()
		local maxOutside = baseline
		local samples = {}
		local start = T.Engine.Now
		local hour = 0
		while T.Engine.Now - start < 5 * 3600 do
			T.Wait(10)
			for i = #bots, 1, -1 do
				local bot = bots[i]
				if bot.Parent then
					TycoonService:CollectVault(bot)
					T.Engine.FireServerAs(bot, T.Remote("BuyAll"))
					if math.random() < 0.05 then
						T.Engine.FireServerAs(bot, T.Remote("MinigameJoin"))
					end
					if math.random() < 0.004 then
						T.Engine.RemovePlayer(bot) -- leaves...
						table.remove(bots, i)
						join() -- ...someone (maybe them again) joins
					end
				else
					table.remove(bots, i)
				end
			end
			TycoonService:CollectVault(me)
			T.Client(function()
				T.Remote("BuyAll"):FireServer()
			end)
			local h = math.floor((T.Engine.Now - start) / 3600)
			if h > hour then
				hour = h
				local count = #ws:GetDescendants()
				local outside = outsideTowers()
				maxOutside = math.max(maxOutside, outside)
				table.insert(samples, outside)
				print(("    hour %d: %d instances (%d outside the towers), %d players"):format(h, count, outside, #game:GetService("Players"):GetPlayers()))
			end
		end
		T.Check(samples[#samples] < baseline + 1500, ("nothing piles up outside the towers (%d -> %d)"):format(baseline, samples[#samples]))
		local towers = #ws:FindFirstChild("Tycoons"):GetDescendants()
		T.Check(towers < 8 * 4600, ("towers stay within their maximum size (%d)"):format(towers))
		for _, p in game:GetService("Players"):GetPlayers() do
			local data = DataService:Get(p)
			T.Check(data ~= nil and finite(data.Cash) and finite(data.Vault) and finite(data.TotalEarned), p.Name .. " data valid")
		end
		T.Check(#T.Engine.Kicks == 0, "nobody was kicked")
		T.Check(me.PlayerGui:FindFirstChild("MegaTycoonUI") ~= nil, "the local client survived 5 hours")
	end,
})

add({
	Name = "shop_live_ui",
	Run = function(T, place)
		T.Engine.Studio = false
		local game, me = T.Boot(place, {
			Setup = function(T2)
				-- server and client each have their own copy of Config
				T2.Shared("Config", "server").GamePasses.VIP.Id = 111
				T2.Shared("Config", "client").GamePasses.VIP.Id = 111
			end,
		})
		T.Wait(6)
		T.Client(function()
			T.Controller("UI"):Open("Shop")
		end)
		T.Wait(0.5)
		local passes, products
		for _, d in me.PlayerGui:GetDescendants() do
			if d:IsA("ScrollingFrame") and d.Name == "Passes" then
				passes = d
			elseif d:IsA("ScrollingFrame") and d.Name == "Products" then
				products = d
			end
		end
		local cards = 0
		for _, child in passes:GetChildren() do
			if child:IsA("Frame") then
				cards += 1
				T.Check(child.Name == "VIP", "only configured passes are listed (" .. child.Name .. ")")
			end
		end
		T.Check(cards == 1, "one configured pass shown (" .. cards .. ")")
		T.Check(T.FindText(products, "Coming soon") ~= nil, "no products configured: 'coming soon'")
	end,
})

add({
	Name = "quests_disabled",
	Run = function(T, place)
		local game, me = T.Boot(place, {
			Setup = function(T2)
				T2.Shared("Config", "server").Quests.Enabled = false
				T2.Shared("Config", "client").Quests.Enabled = false
			end,
		})
		T.Wait(6)
		local data = T.Service("DataService"):Get(me)
		T.Check(#data.Quests.List == 0, "no quests handed out when disabled")
		local tracker = me.PlayerGui:FindFirstChild("QuestTracker", true)
		T.Check(tracker ~= nil and not T.IsShown(tracker), "quest tracker hidden")
		local ok = T.Client(function()
			return T.Remote("ClaimQuest"):InvokeServer(1)
		end)
		T.Check(ok == false, "claiming does nothing")
	end,
})

add({
	Name = "disaster_cleanup",
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.Wait(6)
		local ws = game:GetService("Workspace")
		local fx = ws:FindFirstChild("DisasterFX")
		for _, kind in { "nuke", "meteors", "tornado", "ufo", "earthquake" } do
			T.Admin(me, ";" .. kind)
			T.WaitFor(function()
				return ws:GetAttribute("Disaster") ~= nil
			end, 5, kind .. " start")
			T.WaitFor(function()
				return ws:GetAttribute("Disaster") == nil
			end, 120, kind .. " end")
			T.Wait(30)
			local explosions = 0
			for _, d in ws:GetChildren() do
				if d:IsA("Explosion") then
					explosions += 1
				end
			end
			T.Check(#fx:GetChildren() == 0, kind .. ": every client effect cleaned up (" .. #fx:GetChildren() .. " left)")
			T.Check(explosions == 0, kind .. ": no Explosion objects left (" .. explosions .. ")")
			-- (collectibles live 30s after they drop; an abduction can drop one at the very end)
			T.WaitFor(function()
				return #ws:FindFirstChild("Disasters"):GetChildren() == 0
			end, 15, kind .. ": server disaster objects cleaned up")
		end
	end,
})

-- Diagnostics: with every tower maxed from the start, nothing should keep
-- piling up in the workspace. Prints what grew every 30 minutes. (Slow.)
add({
	Name = "leakprobe",
	Slow = true,
	MaxSeconds = 4 * 3600,
	AllowedWarnings = { "DataStores unavailable", "Could not load data", "Took over a session lock" },
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.SetDt(2)
		local ws = game:GetService("Workspace")
		local TycoonService = T.Service("TycoonService")
		local bots = {}
		for i = 1, 4 do
			table.insert(bots, T.AddPlayer("Bot" .. i))
		end
		T.Wait(10)
		for _, p in game:GetService("Players"):GetPlayers() do
			TycoonService:UnlockAll(p)
		end
		T.Wait(60)
		local function census()
			local byName = {}
			for _, d in ws:GetDescendants() do
				local key = d.ClassName .. ":" .. d.Name
				byName[key] = (byName[key] or 0) + 1
			end
			return byName
		end
		local first = #ws:GetDescendants()
		local last = census()
		for step = 1, 6 do
			T.Wait(1800)
			for _, b in bots do
				TycoonService:CollectVault(b)
			end
			local names = census()
			local grew = {}
			for k, v in names do
				local d = v - (last[k] or 0)
				if d > 20 then
					table.insert(grew, { k, d })
				end
			end
			table.sort(grew, function(a, b)
				return a[2] > b[2]
			end)
			local parts = {}
			for i = 1, math.min(6, #grew) do
				table.insert(parts, "+" .. grew[i][2] .. " " .. grew[i][1])
			end
			print(("    t=%dmin total=%d  %s"):format(step * 30, #ws:GetDescendants(), table.concat(parts, ", ")))
			last = names
		end
		local final = #ws:GetDescendants()
		T.Check(final < first * 1.03 + 300, ("no growth with maxed towers (%d -> %d)"):format(first, final))
	end,
})

-- Diagnostics: the client's UI, lighting and sound don't pile up objects. (Slow.)
add({
	Name = "uiprobe",
	Slow = true,
	MaxSeconds = 2 * 3600,
	Run = function(T, place)
		local game, me = T.Boot(place)
		T.SetDt(1)
		T.Wait(10)
		local function counts()
			return #me.PlayerGui:GetDescendants(), #game:GetService("Lighting"):GetDescendants(), #game:GetService("SoundService"):GetDescendants()
		end
		local kinds = { "meteors", "tornado", "ufo", "earthquake", "nuke" }
		local g0, l0, s0
		for round = 1, 10 do
			T.Admin(me, ";" .. kinds[(round - 1) % #kinds + 1])
			T.Admin(me, ";givecash me 1m")
			T.Client(function()
				T.Remote("BuyAll"):FireServer()
				T.Remote("ClaimDaily"):InvokeServer()
			end)
			T.Wait(300)
			local g, l, snd = counts()
			print(("    round %d: PlayerGui %d, Lighting %d, SoundService %d"):format(round, g, l, snd))
			if round == 2 then
				g0, l0, s0 = g, l, snd
			end
		end
		local g, l, snd = counts()
		T.Check(g < g0 * 1.1 + 50, ("PlayerGui doesn't grow (%d -> %d)"):format(g0, g))
		T.Check(l <= l0 + 3, ("Lighting doesn't grow (%d -> %d)"):format(l0, l))
		T.Check(snd <= s0 + 10, ("SoundService doesn't grow (%d -> %d)"):format(s0, snd))
	end,
})

---------------------------------------------------------------------------
-- Rebirth ranks
---------------------------------------------------------------------------
add({
	Name = "rebirth_ranks",
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Reborn", UserId = 6100 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local QuestService = T.Service("QuestService")
		local GiftService = T.Service("GiftService")
		local data = DataService:Get(me)
		T.Check(#Config.Rebirth.Ranks == 10, "10 rebirth ranks")
		for i = 2, #Config.Rebirth.Ranks do
			T.Check(Config.Rebirth.Ranks[i].Rebirths > Config.Rebirth.Ranks[i - 1].Rebirths, "ranks are in order")
		end
		T.Check(Config.RebirthRank(0) == nil, "no rank before the first rebirth")
		T.Check(Config.RebirthPerk(0, "Income") == 0 and Config.RebirthPerk(99, "Speed") == 4, "perks add up over ranks")
		local head = me.Character:FindFirstChild("Head")
		T.Check(head and not head:FindFirstChild("RankTag"), "no rank tag before the first rebirth")
		local baseQuest = QuestService:_reward(me, { Type = "Collect", Progress = 0, Target = 1 })
		T.Check(T.Humanoid(me).WalkSpeed == Config.BaseWalkSpeed, "normal walk speed")

		-- rebirth 1: starting cash + the first rank
		T.Server(function()
			TycoonService:Rebirth(me, true)
		end)
		T.Wait(2)
		T.Check(data.Rebirths == 1, "rebirthed once")
		T.Check(data.Cash >= Config.StartingCash + 500, "Reborn rank: bonus starting cash (" .. tostring(data.Cash) .. ")")
		T.Check(T.Noticed(me, "New rank: Reborn"), "rank-up message")
		local tag = me.Character.Head:FindFirstChild("RankTag")
		T.Check(tag and tag.Label.Text:find("Reborn") ~= nil, "rank tag above the head")

		-- rebirth 2..10: every rank is earned in turn
		for n = 2, 10 do
			T.Server(function()
				TycoonService:Rebirth(me, true)
			end)
			T.Wait(2)
			local _, rank = Config.RebirthRank(n)
			T.Check(data.Rebirths == n and rank.Rebirths == n, "rebirth " .. n .. " reaches " .. rank.Name)
			T.Check(me.Character.Head.RankTag.Label.Text:find(rank.Name, 1, true) ~= nil, "rank tag shows " .. rank.Name)
		end
		T.Check(T.Humanoid(me).WalkSpeed == Config.BaseWalkSpeed + 4, "Hustler + Sprinter speed (" .. tostring(T.Humanoid(me).WalkSpeed) .. ")")
		local mult = DataService:GetMultiplier(me, true)
		T.Check(mult == 1 + 10 * 0.5 + 1.5, "income perks: 6.5 + 1.5 = 8x (got " .. tostring(mult) .. ")")
		T.Check(QuestService:_reward(me, { Type = "Collect", Progress = 0, Target = 1 }) > baseQuest, "quest rewards grow with rebirths")
		local giftBonus = Config.RebirthPerk(10, "Gift")
		T.Check(math.abs(giftBonus - 0.25) < 1e-9, "gift perk 25% (got " .. tostring(giftBonus) .. ")")
		T.Check(GiftService:GetReward(me, 1) >= Config.Gifts.MinCash[1] * 11, "gift reward includes the bonus")

		-- the panel lists every rank, earned ones ticked
		T.Client(function()
			T.Controller("UI"):Open("Rebirth")
		end)
		T.Wait(1)
		local rows = 0
		local earned = 0
		for _, d in me.PlayerGui:GetDescendants() do
			if d:IsA("TextLabel") and d.Name:match("^Rank%d+$") then
				rows += 1
				if d.Text:find("✅", 1, true) then
					earned += 1
				end
			end
		end
		T.Check(rows == 10 and earned == 10, "panel shows 10 ranks, all earned (" .. rows .. "/" .. earned .. ")")

		-- rank and speed survive a respawn
		T.Server(function()
			me:LoadCharacter()
		end)
		T.Wait(3)
		T.Check(T.Humanoid(me).WalkSpeed == Config.BaseWalkSpeed + 4, "speed after respawn")
		T.Check(me.Character.Head:FindFirstChild("RankTag") ~= nil, "rank tag after respawn")
	end,
})

---------------------------------------------------------------------------
-- Lucky Wheel
---------------------------------------------------------------------------
add({
	Name = "wheel",
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Spinner", UserId = 6200 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local WC = Config.Wheel
		local DataService = T.Service("DataService")
		local WheelService = T.Service("WheelService")
		local Wheel = T.Controller("Wheel")
		local data = DataService:Get(me)

		-- the prize odds follow the weights
		local counts = {}
		local rolls = 6000
		for _ = 1, rolls do
			local i = WheelService:_pick()
			counts[i] = (counts[i] or 0) + 1
		end
		local total = 0
		for _, segment in WC.Segments do
			total += segment.Weight
		end
		for i, segment in WC.Segments do
			local expected = segment.Weight / total
			local seen = (counts[i] or 0) / rolls
			T.Check(math.abs(seen - expected) < 0.04 + expected * 0.3, segment.Name .. " odds " .. string.format("%.3f vs %.3f", seen, expected))
		end
		T.Check((counts[#WC.Segments] or 0) > 0, "the jackpot can be won")

		-- prizes: cash segments pay at least MinCash, boosts pay no cash
		for _, segment in WC.Segments do
			local cash, boost = WheelService:GetPrize(me, segment)
			if segment.Minutes then
				T.Check(cash >= segment.MinCash and boost == 0, segment.Name .. " pays cash")
			else
				T.Check(cash == 0 and boost == segment.BoostSeconds, segment.Name .. " pays a boost")
			end
		end

		-- a new player can spin right away, from the panel
		T.Check(Wheel:IsReady(), "first spin is ready")
		T.Client(function()
			T.Controller("UI"):Open("Wheel")
		end)
		T.Wait(1)
		local spinButton = T.FindButton(me.PlayerGui, "SPIN!")
		T.Check(spinButton ~= nil, "SPIN button is shown")
		local cash, boostEnd = data.Cash, data.BoostEnd
		T.Client(function()
			T.Engine.Click(spinButton)
		end)
		T.Wait(1)
		T.Check(data.Wheel.Spins == 1 and data.Wheel.Last > 0, "the spin is counted and saved")
		T.Check(data.Cash > cash or data.BoostEnd > boostEnd, "the prize was paid")
		T.Check(Wheel.Spinning, "the reel is spinning")
		T.Wait(WC.SpinSeconds + 1)
		T.Check(not Wheel.Spinning, "the reel stopped")
		T.Check(not Wheel:IsReady() and T.FindButton(me.PlayerGui, "Next spin in") ~= nil, "button shows the countdown")

		-- no second spin before the cooldown, even straight from the remote
		local early = T.Client(function()
			return { T.Remote("SpinWheel"):InvokeServer() }
		end)
		T.Check(early[1] == false and early[2] == 0 and tostring(early[3]):find("next free spin"), "can't spin early")
		T.Check(data.Wheel.Spins == 1, "no extra spin counted")

		-- it comes back after the cooldown
		data.Wheel.Last -= WC.CooldownMinutes * 60 -- (the cooldown has passed)
		WheelService:_sync(me)
		T.Wait(1)
		T.Check(Wheel:IsReady(), "ready again after the cooldown")
		local again = T.Client(function()
			return { T.Remote("SpinWheel"):InvokeServer() }
		end)
		T.Check(again[1] == true and WC.Segments[again[2]] ~= nil, "second spin works")
		T.Check(data.Wheel.Spins == 2, "two spins counted")

		-- the cooldown is saved: rejoining doesn't give a free spin
		T.LeaveClient()
		T.Wait(1)
		me = T.StartClient("Spinner", { UserId = 6200 })
		T.Wait(8)
		data = DataService:Get(me)
		T.Check(data.Wheel.Spins == 2, "spins saved")
		local rejoin = T.Client(function()
			return { T.Remote("SpinWheel"):InvokeServer() }
		end)
		T.Check(rejoin[1] == false, "rejoining doesn't skip the cooldown")
	end,
})

---------------------------------------------------------------------------
-- Anti-cheat
---------------------------------------------------------------------------
add({
	Name = "anticheat",
	MaxSeconds = 900,
	Run = function(T, place)
		T.Engine.Studio = false -- a live server: only the creator is an admin
		T.Engine.CreatorId = 7000
		local game, boss = T.Boot(place, { Name = "Boss", UserId = 7000, AntiCheat = true })
		local Config = T.Shared("Config")
		local AC = Config.AntiCheat
		Config.Admin.Admins[7005] = 1 -- a Mod
		local AntiCheat = T.Service("AntiCheatService")
		local BuildKit = T.Service("BuildKit")
		T.Wait(6)

		local function kicked(name)
			for i = #T.Engine.Kicks, 1, -1 do
				if T.Engine.Kicks[i].Player == name then
					return T.Engine.Kicks[i].Message
				end
			end
			return ""
		end
		local function registry()
			local saved = T.Engine.DataStores[AC.DataStore]
			return saved and saved.Registry or { Strikes = {}, Bans = {} }
		end
		-- moves `studs` every 0.25 s (studs x 4 = studs per second)
		local function run(player, studs, seconds)
			for _ = 1, math.floor(seconds / 0.25) do
				if player.Parent == nil then
					return
				end
				T.MoveTo(player, CFrame.new(T.Root(player).Position + Vector3.new(studs, 0, 0)))
				T.Wait(0.25)
			end
		end
		T.Check(AC.StrikesToBan == 5, "5 strikes ban")

		-- normal play isn't flagged
		local walker = T.AddPlayer("Walker", { UserId = 7002 })
		T.Wait(4)
		run(walker, 4, 12) -- 16 studs/s
		T.Check(walker.Parent ~= nil, "walking at normal speed is fine")
		T.Humanoid(walker).FloorMaterial = Enum.Material.Air
		T.Wait(1.5)
		T.Humanoid(walker).FloorMaterial = Enum.Material.Plastic
		T.Wait(1)
		T.Check(walker.Parent ~= nil, "a jump isn't flying")
		T.Humanoid(walker).FloorMaterial = Enum.Material.Air
		for _ = 1, 48 do -- a long fall (24 studs/s down)
			T.MoveTo(walker, CFrame.new(T.Root(walker).Position + Vector3.new(0, -6, 0)))
			T.Wait(0.25)
		end
		T.Humanoid(walker).FloorMaterial = Enum.Material.Plastic
		T.Wait(1)
		T.Check(walker.Parent ~= nil and kicked("Walker") == "", "falling isn't flying")

		-- the owner is never checked
		run(boss, 40, 5)
		T.Check(boss.Parent ~= nil and kicked("Boss") == "", "staff of the exempt rank aren't checked")

		-- speed hacking: strikes 1-4 kick
		local USER = 7001
		for strike = 1, 4 do
			local cheater = T.AddPlayer("Speedy", { UserId = USER })
			T.Wait(4)
			run(cheater, 40, 3) -- 160 studs/s
			T.Wait(2)
			local message = kicked("Speedy")
			T.Check(cheater.Parent == nil, "strike " .. strike .. " kicks")
			T.Check(message:find("Speed hacking", 1, true) ~= nil and message:find("strike " .. strike .. "/5", 1, true) ~= nil, "kick message says why (" .. message .. ")")
			local record = registry().Strikes[tostring(USER)]
			T.Check(record ~= nil and record.Count == strike and #record.Evidence == strike, "strike " .. strike .. " saved with its proof")
		end
		T.Check(kicked("Speedy"):find("permanent ban", 1, true) ~= nil, "the 4th kick warns about the ban")
		-- the 5th strike bans
		local fifth = T.AddPlayer("Speedy", { UserId = USER })
		T.Wait(4)
		run(fifth, 40, 3)
		T.Wait(2)
		T.Check(fifth.Parent == nil and kicked("Speedy"):find("banned for cheating", 1, true) ~= nil, "the 5th strike bans")
		local ban = registry().Bans[tostring(USER)]
		T.Check(ban ~= nil and ban.Strikes == 5 and #ban.Evidence == 5 and ban.By == "Anti-Cheat", "the ban keeps 5 pieces of evidence")
		T.Check(ban ~= nil and ban.Evidence[1].Detail:find("studs/s", 1, true) ~= nil and ban.Reason:find("Speed hacking x5", 1, true) ~= nil, "the proof says what was seen (" .. tostring(ban and ban.Reason) .. ")")
		T.Check(registry().Strikes[tostring(USER)] == nil, "strikes become the ban")
		T.Check(T.Engine.DataStores[Config.Admin.BanDataStore][tostring(USER)] ~= nil, "also in the main ban list")
		local again = T.AddPlayer("Speedy", { UserId = USER })
		T.Wait(3)
		T.Check(again.Parent == nil and kicked("Speedy"):find("banned from this game", 1, true) ~= nil, "a banned player is kicked on join")

		-- flying
		local flyer = T.AddPlayer("Flyer", { UserId = 7003 })
		T.Wait(4)
		T.Humanoid(flyer).FloorMaterial = Enum.Material.Air
		T.Wait(AC.Fly.Seconds + 3)
		T.Check(flyer.Parent == nil and kicked("Flyer"):find("Flying", 1, true) ~= nil, "hovering in the air is flying")

		-- teleporting
		local tp = T.AddPlayer("Teleporter", { UserId = 7004 })
		T.Wait(4)
		T.MoveTo(tp, CFrame.new(T.Root(tp).Position + Vector3.new(300, 0, 0)))
		T.Wait(1)
		T.Check(tp.Parent ~= nil, "a single teleport is fine")
		for i = 1, 16 do
			if tp.Parent == nil then
				break -- already caught
			end
			T.MoveTo(tp, CFrame.new(T.Root(tp).Position + Vector3.new(i % 2 == 0 and 300 or -300, 0, 0)))
			T.Wait(0.5)
		end
		T.Wait(2)
		T.Check(tp.Parent == nil and kicked("Teleporter"):find("Teleporting", 1, true) ~= nil, "constant teleporting is caught")

		-- grabbing things from far away
		local reacher = T.AddPlayer("Reacher", { UserId = 7006 })
		T.Wait(4)
		local pad = game:GetService("Workspace"):FindFirstChild("LaunchPad", true)
		T.Check(pad ~= nil, "found a part to reach for")
		T.MoveTo(reacher, CFrame.new(pad.Position + Vector3.new(500, 0, 0)))
		T.Wait(1)
		T.Server(function()
			for _ = 1, 4 do
				BuildKit.IsNear(reacher, pad)
			end
		end)
		T.Wait(2)
		T.Check(reacher.Parent ~= nil, "4 far touches aren't enough")
		T.Server(function()
			BuildKit.IsNear(reacher, pad)
		end)
		T.Wait(2)
		T.Check(reacher.Parent == nil and kicked("Reacher"):find("far away", 1, true) ~= nil, "5 far touches in a row are caught")

		-- remote spam
		local spammer = T.AddPlayer("Spammer", { UserId = 7007 })
		T.Wait(4)
		for _ = 1, 5 do
			for _ = 1, 100 do
				T.Engine.FireServerAs(spammer, T.Remote("RequestRebirth"))
			end
			T.Wait(1)
		end
		T.Wait(1)
		T.Check(spammer.Parent == nil and kicked("Spammer"):find("Spamming", 1, true) ~= nil, "remote spam is caught")

		-- admin remotes without a rank
		local snoop = T.AddPlayer("Snoop", { UserId = 7008 })
		local mod = T.AddPlayer("Mod", { UserId = 7005 })
		T.Wait(4)
		T.Engine.InvokeServerAs(mod, T.Remote("AdminCommand"), "m hello")
		T.Engine.InvokeServerAs(snoop, T.Remote("AdminCommand"), "m hello")
		T.Wait(2)
		T.Check(snoop.Parent == nil and kicked("Snoop"):find("admin commands", 1, true) ~= nil, "using the admin remote without a rank is caught")
		T.Check(mod.Parent ~= nil, "real admins are fine")

		-- the admin panel: bans, strikes, proof
		local report = T.Engine.InvokeServerAs(boss, T.Remote("AdminData"), "anticheat")
		local listed
		for _, entry in report.Bans do
			if entry.UserId == USER then
				listed = entry
			end
		end
		T.Check(listed ~= nil and #listed.Evidence == 5, "the report lists the ban with its proof")
		T.Check(#report.Strikes >= 5, "and the players with strikes (" .. #report.Strikes .. ")")
		T.Check(T.Engine.InvokeServerAs(mod, T.Remote("AdminData"), "anticheat") == nil, "only Head Admins see the evidence")
		T.Client(function()
			T.Controller("UI"):Open("Admin")
		end)
		T.Wait(1)
		local tab = T.FindButton(boss.PlayerGui, "ANTI%-CHEAT")
		T.Check(tab ~= nil, "the panel has an Anti-Cheat tab")
		T.Client(function()
			T.Engine.Click(tab)
		end)
		T.Wait(2)
		T.Check(T.FindText(boss.PlayerGui, "studs/s") ~= nil, "the tab shows the proof")
		T.Check(T.FindText(boss.PlayerGui, "Speedy") ~= nil, "and who was banned")
		local unban = T.FindButton(boss.PlayerGui, "^UNBAN$")
		T.Check(unban ~= nil, "with an UNBAN button")
		T.Client(function()
			T.Engine.Click(unban)
		end)
		T.Wait(2)
		T.Check(registry().Bans[tostring(USER)] == nil, "UNBAN removes the ban")
		T.Check(T.Engine.DataStores[Config.Admin.BanDataStore][tostring(USER)] == nil, "from the main ban list too")
		T.Check(AntiCheat:GetStrikes(USER) == 0, "and the strikes start over")
		local back = T.AddPlayer("Speedy", { UserId = USER })
		T.Wait(4)
		T.Check(back.Parent ~= nil, "an unbanned player can join again")

		-- commands
		local _, text = T.Admin(boss, ";strikes 7003")
		T.Check(tostring(text):find("1/5", 1, true) ~= nil, ";strikes shows the count (" .. tostring(text) .. ")")
		T.Admin(boss, ";clearstrikes 7003")
		T.Check(AntiCheat:GetStrikes(7003) == 0, ";clearstrikes")
		local victim = T.AddPlayer("Victim", { UserId = 7010 })
		T.Wait(3)
		T.Admin(boss, ";ban Victim griefing")
		T.Wait(1)
		report = T.Engine.InvokeServerAs(boss, T.Remote("AdminData"), "anticheat")
		local manual
		for _, entry in report.Bans do
			if entry.UserId == 7010 then
				manual = entry
			end
		end
		T.Check(manual ~= nil and manual.By == "Boss" and manual.Reason:find("griefing", 1, true) ~= nil, "manual bans are in the panel too")
		T.Admin(boss, ";unban 7010")
		T.Check(registry().Bans["7010"] == nil and T.Engine.DataStores[Config.Admin.BanDataStore]["7010"] == nil, ";unban works with a user id")
	end,
})

---------------------------------------------------------------------------
-- Personal shield
---------------------------------------------------------------------------
add({
	Name = "shield",
	MaxSeconds = 900,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Shielded", UserId = 6400 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local SC = Config.Shield
		local DataService = T.Service("DataService")
		local ShieldService = T.Service("ShieldService")
		local DisasterService = T.Service("DisasterService")
		local Shield = T.Controller("Shield")
		local data = DataService:Get(me)
		local position = T.Root(me).Position
		T.Check(Shield:GetState() == "ready" and not ShieldService:IsShielded(me), "a new player's shield is ready")
		T.Check(not DisasterService:IsProtected(me, position), "not protected without a shield")

		-- activate from the panel
		T.Client(function()
			T.Controller("UI"):Open("Shield")
		end)
		T.Wait(1)
		local button = T.FindButton(me.PlayerGui, "ACTIVATE")
		T.Check(button ~= nil, "ACTIVATE button")
		T.Client(function()
			T.Engine.Click(button)
		end)
		T.Wait(1)
		T.Check(ShieldService:IsShielded(me) and data.Shield.Start > 0, "shield on (and saved)")
		T.Check(me.Character:FindFirstChild("ShieldBubble") ~= nil, "force-field bubble")
		T.Check(DisasterService:IsProtected(me, position), "protected from disasters")
		T.Check(Shield:GetState() == "active", "client shows it active")
		T.Check(T.FindText(me.PlayerGui, "SHIELD ACTIVE") ~= nil, "the panel says so")

		-- a nuke can't hurt a shielded player
		T.Admin(me, ";nuke")
		T.Wait(45)
		T.Check(T.Humanoid(me).Health > 0, "the shield saved the player from a nuke")
		T.Check(T.Noticed(me, "shield absorbed"), "and says so")

		-- rejoining: the shield and its recharge carry on
		T.LeaveClient()
		T.Wait(1)
		me = T.StartClient("Shielded", { UserId = 6400 })
		T.Wait(8)
		data = DataService:Get(me)
		Shield = T.Controller("Shield") -- (a new client)
		T.Check(ShieldService:IsShielded(me), "still shielded after rejoining")
		T.Check(me.Character:FindFirstChild("ShieldBubble") ~= nil, "bubble comes back")
		local early = T.Client(function()
			return { T.Remote("ActivateShield"):InvokeServer() }
		end)
		T.Check(early[1] == false and tostring(early[2]):find("recharging"), "can't activate again yet")

		-- it runs out, then the cooldown
		T.SetDt(1)
		T.WaitFor(function()
			return not ShieldService:IsShielded(me)
		end, SC.Seconds + 5, "shield to run out")
		T.Wait(2)
		T.Check(me.Character:FindFirstChild("ShieldBubble") == nil, "bubble is gone")
		T.Check(not DisasterService:IsProtected(me, T.Root(me).Position), "not protected any more")
		T.Check(Shield:GetState() == "recharging", "client shows recharging")
		-- leaving and coming back doesn't reset the cooldown
		T.LeaveClient()
		T.Wait(1)
		me = T.StartClient("Shielded", { UserId = 6400 })
		T.Wait(8)
		local again = T.Client(function()
			return { T.Remote("ActivateShield"):InvokeServer() }
		end)
		T.Check(again[1] == false, "rejoining doesn't reset the cooldown")
		-- after the full cooldown it works again
		DataService:Get(me).Shield.Start -= SC.Cooldown
		T.Server(function()
			ShieldService:_apply(me)
		end)
		T.Wait(2)
		local ready = T.Client(function()
			return { T.Remote("ActivateShield"):InvokeServer() }
		end)
		T.Check(ready[1] == true, "ready again after the cooldown")
	end,
})

---------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------
add({
	Name = "pets",
	MaxSeconds = 900,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "PetOwner", UserId = 6500 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local PC = Config.Pets
		local DataService = T.Service("DataService")
		local PetService = T.Service("PetService")
		local data = DataService:Get(me)
		local ws = game:GetService("Workspace")
		local function pets(action, arg)
			T.Wait(0.3) -- (the server ignores actions closer than 0.25 s)
			return T.Client(function()
				return { T.Remote("PetAction"):InvokeServer(action, arg) }
			end)
		end
		local function floating()
			local n = 0
			for _, child in ws:GetChildren() do
				if child.Name:match("^Pet_") then
					n += 1
				end
			end
			return n
		end

		-- the data is consistent
		for _, pet in PC.List do
			T.Check(PC.Rarities[pet.Rarity] ~= nil, pet.Id .. " has a real rarity")
		end
		for _, egg in PC.Eggs do
			for rarity in egg.Weights do
				local any = false
				for _, pet in PC.List do
					any = any or pet.Rarity == rarity
				end
				T.Check(any, egg.Id .. " egg can hatch " .. rarity .. " pets")
			end
		end
		T.Check(Config.PetSlots(0) == 3 and Config.PetSlots(5) == 4 and Config.PetSlots(10) == 5, "slots grow with rebirths")

		-- the egg odds follow the weights
		for _, egg in PC.Eggs do
			local seen, rolls = {}, 4000
			for _ = 1, rolls do
				local rarity = PetService:_roll(egg).Rarity
				seen[rarity] = (seen[rarity] or 0) + 1
			end
			local total = 0
			for _, weight in egg.Weights do
				total += weight
			end
			for rarity, weight in egg.Weights do
				local expected = weight / total
				T.Check(math.abs((seen[rarity] or 0) / rolls - expected) < 0.04 + expected * 0.3, egg.Id .. " odds for " .. rarity)
			end
			for rarity in seen do
				T.Check(egg.Weights[rarity] ~= nil, egg.Id .. " never gives " .. rarity)
			end
		end

		-- too poor
		local broke = pets("Hatch", "Basic")
		T.Check(broke[1] == false and #data.Pets.Owned == 0, "can't hatch without the cash")
		T.Check(pets("Hatch", "Nope")[1] == false, "unknown egg")

		-- hatch from the panel
		DataService:AddCash(me, 1e6, false)
		T.Client(function()
			T.Controller("UI"):Open("Pets")
		end)
		T.Wait(1.5)
		local hatch = T.FindButton(me.PlayerGui, "^HATCH$")
		T.Check(hatch ~= nil, "HATCH button")
		local cash, mult = data.Cash, DataService:GetMultiplier(me)
		T.Client(function()
			T.Engine.Click(hatch)
		end)
		T.Wait(1)
		T.Check(#data.Pets.Owned == 1 and data.Pets.Hatched == 1 and data.Cash < cash, "hatching costs cash and gives a pet")
		T.Check(T.Controller("Pets").State and #T.Controller("Pets").State.Owned == 1, "the client sees it")
		-- equip from the card
		local equip = T.FindButton(me.PlayerGui, "^EQUIP$")
		T.Check(equip ~= nil, "EQUIP button on the pet card")
		T.Client(function()
			T.Engine.Click(equip)
		end)
		T.Wait(1)
		T.Check(#data.Pets.Equipped == 1 and me:GetAttribute("Pets") ~= "", "equipped")
		T.Check(DataService:GetMultiplier(me) > mult, "an equipped pet raises the income multiplier")
		T.Check(floating() == 1, "the pet floats behind the player")

		-- admin: more pets, slots, best first
		T.Admin(me, ";givepet me Dragon 2")
		T.Admin(me, ";givepet me Dog 4")
		T.Check(#data.Pets.Owned == 7, "givepet adds pets")
		local full = 0
		for _, owned in data.Pets.Owned do
			if not table.find(data.Pets.Equipped, owned.Uid) then
				full = full + 1
				if pets("Equip", owned.Uid)[1] then
					T.Check(#data.Pets.Equipped <= 3, "never above the slots")
				end
			end
		end
		T.Check(#data.Pets.Equipped == 3, "three slots at 0 rebirths")
		T.Check(pets("Equip", 9999)[1] == false, "can't equip a pet you don't have")
		T.Check(pets("Equip", "x")[1] == false, "bad ids are rejected")
		local best = pets("EquipBest")
		T.Check(best[1] == true, "equip best")
		local top = 0
		for _, owned in data.Pets.Owned do
			if table.find(data.Pets.Equipped, owned.Uid) then
				top += Config.PetBonus(owned.Id)
			end
		end
		T.Check(top >= 1.0, "the best pets are worn: two Dragons + the best other (bonus " .. tostring(top) .. ")")
		T.Check(math.abs(Config.PetsBonus(data.Pets) - top) < 1e-9, "the bonus counts equipped pets")
		T.Wait(1)
		T.Check(floating() == 3, "three pets float")
		local permanent = DataService:GetMultiplier(me, true)
		T.Check(math.abs(permanent - (1 + top)) < 1e-9, "offline earnings use the pet bonus too (" .. tostring(permanent) .. ")")

		-- selling
		local victim = data.Pets.Owned[#data.Pets.Owned]
		local cashBefore = data.Cash
		T.Check(pets("Sell", victim.Uid)[1] == true and #data.Pets.Owned == 6, "sell a pet")
		T.Check(data.Cash > cashBefore, "selling pays")
		T.Check(pets("Sell", victim.Uid)[1] == false, "can't sell it twice")
		T.Check(PetService:GetSellValue(me, "Dog") < PetService:GetEggCost(me, PC.Eggs[1]), "selling pays less than an egg costs")

		-- storage cap
		for _ = 1, 4 do
			T.Admin(me, ";givepet me Cat 20")
		end
		T.Check(#data.Pets.Owned == PC.MaxOwned, "storage is capped at " .. PC.MaxOwned .. " (" .. #data.Pets.Owned .. ")")
		T.Check(pets("Hatch", "Basic")[1] == false, "can't hatch with full storage")

		-- the Hatch quest
		DataService:AddCash(me, 1e6, false)
		data.Pets.Owned = { data.Pets.Owned[1] }
		data.Pets.Equipped = {}
		data.Quests.List = { { Type = "Hatch", Target = 1, Progress = 0 } }
		pets("Hatch", "Basic")
		T.Check(data.Quests.List[1] == nil or data.Quests.List[1].Type ~= "Hatch" or data.Quests.List[1].Progress >= 1, "hatching counts for the Hatch quest")

		-- saved across a rejoin
		pets("EquipBest")
		local ownedCount, equippedCount = #data.Pets.Owned, #data.Pets.Equipped
		T.LeaveClient()
		T.Wait(1)
		me = T.StartClient("PetOwner", { UserId = 6500 })
		T.Wait(8)
		data = DataService:Get(me)
		T.Check(#data.Pets.Owned == ownedCount and #data.Pets.Equipped == equippedCount and equippedCount > 0, "pets are saved")
		T.Check(me:GetAttribute("Pets") ~= "" and #T.Controller("Pets").State.Owned == ownedCount, "and shown after rejoining")
	end,
})

---------------------------------------------------------------------------
-- Islands and treasure chests
---------------------------------------------------------------------------
add({
	Name = "islands",
	MaxSeconds = 900,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Sailor", UserId = 6600 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local IC = Config.Islands
		local DataService = T.Service("DataService")
		local IslandService = T.Service("IslandService")
		local WorldBuilder = T.Service("WorldBuilder")
		local data = DataService:Get(me)
		local ws = game:GetService("Workspace")
		local function travel(destination)
			T.Wait(IC.TravelDelay + 0.5)
			return T.Client(function()
				return { T.Remote("Travel"):InvokeServer(destination) }
			end)
		end
		local function near(position, radius)
			return (T.Root(me).Position - position).Magnitude <= radius
		end

		-- the world has the islands, outside the world's edge, each with its chests
		T.Check(#IC.List == 3, "3 islands")
		local chestCount = 0
		for _, island in IC.List do
			local info = WorldBuilder.Islands[island.Id]
			T.Check(info ~= nil and math.max(math.abs(island.Position.X), math.abs(island.Position.Z)) > 1100, island.Name .. " is built beyond the edge")
			T.Check(ws.World:FindFirstChild("Island_" .. island.Id) ~= nil, island.Name .. " is in the world")
			for _, entry in WorldBuilder.Chests do
				if entry.Island == island.Id then
					chestCount += 1
				end
			end
		end
		T.Check(chestCount == 12, "12 treasure chests (" .. chestCount .. ")")
		T.Check(#WorldBuilder.ReturnPads == 3, "a return pad on each island")

		-- rebirth requirements
		local locked = travel("Volcano")
		T.Check(locked[1] == false and tostring(locked[2]):find("unlocks at 1"), "Volcano Isle needs a rebirth")
		T.Check(travel("Nowhere")[1] == false, "unknown places are rejected")
		T.Check(travel({})[1] == false, "bad destinations are rejected")

		-- go from the panel
		T.Client(function()
			T.Controller("UI"):Open("Travel")
		end)
		T.Wait(1)
		local goTreasure = T.FindButton(me.PlayerGui, "GO")
		T.Check(goTreasure ~= nil, "GO buttons in the Travel panel")
		local treasure = WorldBuilder.Islands.Treasure
		T.Wait(IC.TravelDelay + 0.5)
		local button = me.PlayerGui:FindFirstChild("DestTreasure", true):FindFirstChild("GoTreasure")
		T.Client(function()
			T.Engine.Click(button)
		end)
		T.Wait(1)
		T.Check(near(treasure.Spawn, 12), "travelled to Treasure Isle")
		local tooFast = T.Client(function()
			return { T.Remote("Travel"):InvokeServer("Plaza") }
		end)
		T.Check(tooFast[1] == false and tostring(tooFast[2]):find("Slow down"), "trips are rate limited")

		-- the chests
		local entry
		for _, e in WorldBuilder.Chests do
			if e.Island == "Treasure" then
				entry = e
				break
			end
		end
		T.Check(me:GetAttribute("ChestsReady_Treasure") == 4, "4 chests ready on Treasure Isle")
		local cash = data.Cash
		T.Engine.Touch(entry.Part, me)
		T.Wait(1)
		T.Check(data.Cash >= cash + 800 and data.Chests[entry.Id] ~= nil, "opening a chest pays and is saved")
		cash = data.Cash
		T.Engine.Touch(entry.Part, me)
		T.Wait(1)
		T.Check(data.Cash == cash, "the chest is closed for the cooldown")
		T.Wait(5.5)
		T.Check(me:GetAttribute("ChestsReady_Treasure") == 3 and me:GetAttribute("ChestNext_Treasure") > 0, "ready count goes down")
		-- a touch from far away doesn't count (the anti-exploit distance check)
		local other
		for _, e in WorldBuilder.Chests do
			if e.Island == "Treasure" and e ~= entry then
				other = e
				break
			end
		end
		cash = data.Cash
		T.Engine.RemoteTouch(other.Part, me)
		T.Wait(1)
		T.Check(data.Cash == cash and data.Chests[other.Id] == nil, "a chest can't be opened from far away")

		-- rejoining doesn't reopen it
		T.LeaveClient()
		T.Wait(1)
		me = T.StartClient("Sailor", { UserId = 6600 })
		T.Wait(8)
		data = DataService:Get(me)
		T.Check(data.Chests[entry.Id] ~= nil, "chest times are saved")
		T.Wait(5.5)
		T.Check(me:GetAttribute("ChestsReady_Treasure") == 3, "still 3 ready after rejoining")
		local before = data.Cash
		T.Engine.Touch(entry.Part, me)
		T.Wait(1)
		T.Check(data.Cash == before, "rejoining doesn't reopen the chest")
		-- after the cooldown it opens again
		data.Chests[entry.Id] -= IC.Cooldown
		T.Engine.Touch(entry.Part, me)
		T.Wait(1)
		T.Check(data.Cash > before, "it opens again after the cooldown")

		-- back by the pad, and Volcano Isle after a rebirth
		local pad
		for _, p in WorldBuilder.ReturnPads do
			if p.Island == "Treasure" then
				pad = p
			end
		end
		T.Wait(IC.TravelDelay + 0.5)
		T.Engine.Touch(pad.Part, me)
		T.Wait(1)
		T.Check(near(IC.Plaza, 12), "the pad brings you back to the plaza")
		data.Rebirths = 1
		DataService:Sync(me)
		local ok = travel("Volcano")
		T.Check(ok[1] == true and near(WorldBuilder.Islands.Volcano.Spawn, 12), "Volcano Isle opens at 1 rebirth")
		T.Check(travel("Frost")[1] == false, "Frost Isle still needs 3")
	end,
})

---------------------------------------------------------------------------
-- Weekly rewards
---------------------------------------------------------------------------
add({
	Name = "weekly",
	MaxSeconds = 900,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Weekly", UserId = 6700 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local WC = Config.Weekly
		local DataService = T.Service("DataService")
		local WeeklyService = T.Service("WeeklyService")
		local data = DataService:Get(me)
		local today = T.Engine.EpochBase // 86400 + math.floor(T.Engine.Now / 86400)
		local function claim(index)
			return T.Client(function()
				return { T.Remote("ClaimWeekly"):InvokeServer(index) }
			end)
		end
		local function state()
			return WeeklyService:GetState(me)
		end

		-- today counts as the first day
		T.Check(state().Days == 1 and data.Weekly.Days[tostring(today)] == true, "joining counts as a day")
		T.Check(#state().DayFlags == 7, "seven day flags")
		T.Check(claim(1)[1] == false, "not enough days for the first reward")
		T.Check(claim(99)[1] == false and claim("x")[1] == false, "bad milestones are rejected")

		-- three days: claim the first
		data.Weekly.Days[tostring(today - 1)] = true
		data.Weekly.Days[tostring(today - 2)] = true
		WeeklyService:Refresh(me)
		T.Wait(1)
		T.Check(state().Days == 3 and me:GetAttribute("WeeklyReady") == 1, "3 days unlock the first reward (badge)")
		-- (days before this week's Monday don't count, so keep the test inside one week)
		local cash = data.Cash
		local first = claim(1)
		T.Check(first[1] == true and data.Cash > cash, "claiming pays (" .. tostring(first[2]) .. ")")
		T.Check(claim(1)[1] == false, "once per week")
		T.Check(claim(2)[1] == false, "the 5-day reward isn't unlocked")

		-- all seven days: boost + a free pet
		for i = 1, 7 do
			data.Weekly.Days[tostring(data.Weekly.Week * 7 - 3 + i - 1)] = true
		end
		WeeklyService:Refresh(me)
		local pets = #data.Pets.Owned
		local boost = data.BoostEnd
		T.Check(claim(2)[1] == true and data.BoostEnd > boost, "the 5-day reward gives a boost")
		T.Check(claim(3)[1] == true and #data.Pets.Owned == pets + 1, "the 7-day reward gives a free pet")
		T.Check(state().Ready == 0, "nothing left to claim")

		-- the panel
		T.Client(function()
			T.Controller("UI"):Open("Daily")
		end)
		T.Wait(1.5)
		local weeklyButton = T.FindButton(me.PlayerGui, "WEEKLY REWARDS")
		T.Check(weeklyButton ~= nil, "a WEEKLY button in the daily panel")
		T.Client(function()
			T.Engine.Click(weeklyButton)
		end)
		T.Wait(1.5)
		T.Check(T.FindText(me.PlayerGui, "You joined on 7 day") ~= nil, "the weekly panel shows the days")
		T.Check(T.FindButton(me.PlayerGui, "CLAIMED") ~= nil, "claimed rewards say so")

		-- saved across a rejoin
		T.LeaveClient()
		T.Wait(1)
		me = T.StartClient("Weekly", { UserId = 6700 })
		T.Wait(8)
		data = DataService:Get(me)
		T.Check(state().Days >= 7 and state().Claimed[3] == true, "days and claims are saved")
		T.Check(claim(1)[1] == false, "rejoining doesn't reset the claims")

		-- a new week starts over (today still counts)
		data.Weekly.Week -= 1
		WeeklyService:Refresh(me)
		T.Check(state().Days == 1 and state().Claimed[1] == false, "a new week starts over")
		T.Check(state().ResetsIn > 0 and state().ResetsIn <= 7 * 86400, "and says when it resets")
	end,
})

---------------------------------------------------------------------------
-- The 15 extra disasters
---------------------------------------------------------------------------
add({
	Name = "extra_disasters",
	MaxSeconds = 4000,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Victim", UserId = 6800 })
		local safe = T.AddPlayer("Safe", { UserId = 6801 })
		T.Wait(8)
		local Config = T.Shared("Config")
		local DataService = T.Service("DataService")
		local ShieldService = T.Service("ShieldService")
		local DisasterService = T.Service("DisasterService")
		local ws = game:GetService("Workspace")
		local normalGravity = ws.Gravity
		local HUGE = 1e6

		T.Check(#Config.ExtraDisasters == 15, "15 extra disasters")
		local kinds = DisasterService:ListKinds()
		for _, def in Config.ExtraDisasters do
			T.Check(kinds:find(def.Name, 1, true) ~= nil, def.Name .. " is in the disaster list")
			T.Check(Config.Disasters[def.Name].Weight > 0, def.Name .. " can happen by itself")
		end
		T.Check(select(2, T.Admin(me, ";disaster")):find("Hailstorm", 1, true) ~= nil, ";disaster lists them")
		T.Check(select(2, T.Admin(me, ";disaster nonsense")):find("Unknown", 1, true) ~= nil, "unknown names are refused")

		local function leftovers()
			local n = 0
			for _, child in ws.Disasters:GetChildren() do
				if child.Name:match("^XD_") then
					n += 1
				end
			end
			return n
		end
		local function announced(title)
			for _, args in T.Sent(me, "Announce") do
				if type(args[1]) == "table" and args[1].Title == title then
					return true
				end
			end
			return false
		end

		-- stopping one early cleans up
		T.Humanoid(me).MaxHealth = HUGE
		T.Humanoid(me).Health = HUGE
		T.Admin(me, ";hailstorm")
		T.Wait(6)
		T.Check(ws:GetAttribute("Disaster") == "Hailstorm", "a hailstorm is running")
		T.Admin(me, ";stopdisaster")
		T.WaitFor(function()
			return ws:GetAttribute("Disaster") == nil
		end, 20, "the hailstorm to stop")
		T.Wait(2)
		T.Check(leftovers() == 0, "stopping cleans up everything (" .. leftovers() .. " left)")

		-- every disaster: it hurts whoever is out in the open, not a shielded player, and it cleans up after itself
		for _, def in Config.ExtraDisasters do
			T.Humanoid(me).MaxHealth = HUGE
			T.Humanoid(me).Health = HUGE
			T.Humanoid(safe).MaxHealth = HUGE
			T.Humanoid(safe).Health = HUGE
			local now = T.Engine.EpochBase + math.floor(T.Engine.Now)
			DataService:Get(safe).Shield.Start = now
			T.Server(function()
				ShieldService:_apply(safe)
			end)
			local ok, text = T.Admin(me, ";" .. def.Name:lower())
			T.Check(ok == true and tostring(text):find("incoming", 1, true) ~= nil, def.Name .. " starts (" .. tostring(text) .. ")")
			T.WaitFor(function()
				return ws:GetAttribute("Disaster") == def.Name
			end, 10, def.Name .. " to begin")
			T.Check(announced(def.Title), def.Name .. " is announced")
			local gravities = {}
			local deadline = T.Engine.Now + 200
			while ws:GetAttribute("Disaster") ~= nil and T.Engine.Now < deadline do
				gravities[ws.Gravity] = true
				T.Wait(0.5)
			end
			T.Wait(2)
			local taken = HUGE - T.Humanoid(me).Health
			if def.Gravities then
				local changes = 0
				for gravity in gravities do
					if gravity ~= normalGravity then
						changes += 1
					end
				end
				T.Check(changes >= 3, def.Name .. " changed gravity (" .. changes .. " different values)")
			else
				T.Check(taken > 0, def.Name .. " hurt the player in the open (took " .. tostring(taken) .. ")")
			end
			T.Check(T.Humanoid(safe).Health == HUGE, def.Name .. " didn't touch the shielded player")
			T.Check(leftovers() == 0, def.Name .. " cleaned up (" .. leftovers() .. " left)")
			T.Check(ws.Gravity == normalGravity, def.Name .. " restored gravity")
			T.Check(T.Humanoid(me).WalkSpeed == Config.BaseWalkSpeed, def.Name .. " restored walk speed (" .. tostring(T.Humanoid(me).WalkSpeed) .. ")")
			T.Check(me.Parent ~= nil and T.Humanoid(me).Health > 0, "the victim is still alive after " .. def.Name)
		end
	end,
})

table.insert(Scenarios, {
	Name = "new_passes",
	MaxSeconds = 300,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "PassFan", UserId = 6600 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local TycoonItems = T.Shared("TycoonItems")
		local DataService = T.Service("DataService")
		local PetService = T.Service("PetService")
		local TycoonService = T.Service("TycoonService")
		local data = DataService:Get(me)
		local ws = game:GetService("Workspace")

		-- every new pass is configured and has a card
		for _, key in { "PetLuck", "PetPower", "PetSlot", "OfflineBoost", "Discount", "IslandExpress", "WheelPlus", "ShieldPro", "RebirthBoost", "GiftBoost" } do
			T.Check(Config.GamePasses[key] ~= nil and Config.GamePasses[key].Name ~= nil, key .. " pass exists")
		end

		-- upgrade pads: only a few per floor, and spread out
		local pads = {}
		for _, d in ws:GetDescendants() do
			if d.Name == "Pad" and d.Parent and d.Parent:FindFirstChild("Pillar") then
				table.insert(pads, d)
			end
		end
		T.Check(#pads >= 1 and #pads <= Config.Tycoon.MaxVisibleButtons, "at most " .. Config.Tycoon.MaxVisibleButtons .. " pads on the first floor (" .. #pads .. ")")
		local closest = math.huge
		for i = 1, #pads do
			for j = i + 1, #pads do
				closest = math.min(closest, (pads[i].Position - pads[j].Position).Magnitude)
			end
		end
		T.Check(closest >= 5.2, "pads don't overlap (closest " .. string.format("%.1f", closest) .. ")")

		-- 10% Off Upgrades
		local target
		for _, item in TycoonItems.List do
			if item.Cost > 0 and item.Kind ~= "Secret" and TycoonItems.IsAvailable(item, data.Purchased) then
				target = item
				break
			end
		end
		T.Check(target ~= nil, "found an upgrade to buy")
		me:SetAttribute("Pass_Discount", true)
		DataService:AddCash(me, target.Cost * 2, false)
		local before = data.Cash
		local ok = TycoonService:TryPurchase(me, target.Id)
		T.Check(ok and before - data.Cash == math.floor(target.Cost * 0.9), ("Discount pays 90%% (paid %s of %s)"):format(tostring(before - data.Cash), tostring(target.Cost)))

		-- pets: +1 slot, Pet Power, Lucky Hatch
		local common = Config.Pets.List[1].Id
		PetService:Give(me, common, 5)
		local uids = {}
		for _, pet in data.Pets.Owned do
			table.insert(uids, pet.Uid)
		end
		for i = 1, Config.PetSlots(0) do
			T.Check(PetService:Equip(me, uids[i]), "slot " .. i .. " equips")
		end
		local full = PetService:Equip(me, uids[Config.PetSlots(0) + 1])
		T.Check(not full, "no extra slot without the pass")
		me:SetAttribute("Pass_PetSlot", true)
		T.Check(PetService:Equip(me, uids[Config.PetSlots(0) + 1]), "+1 Pet Slot gives another slot")
		local plain = DataService:GetMultiplier(me, true)
		me:SetAttribute("Pass_PetPower", true)
		local boosted = DataService:GetMultiplier(me, true)
		T.Check(math.abs((boosted - plain) - Config.PetsBonus(data.Pets) * 0.5) < 1e-6, "Pet Power adds half of the pet bonus")

		local egg = Config.Pets.Eggs[1]
		local function rares(lucky)
			local n = 0
			for _ = 1, 4000 do
				local pet = PetService:_roll(egg, lucky)
				if pet.Rarity ~= "Common" then
					n += 1
				end
			end
			return n
		end
		local normal, lucky = rares(false), rares(true)
		T.Check(lucky > normal * 1.25, ("Lucky Hatch gives more uncommon+ pets (%d vs %d)"):format(lucky, normal))

		-- Rebirth Booster
		data.Rebirths = 2
		local without = DataService:GetMultiplier(me, true)
		me:SetAttribute("Pass_RebirthBoost", true)
		local withPass = DataService:GetMultiplier(me, true)
		T.Check(math.abs((withPass - without) - 2 * Config.Rebirth.MultiplierPerRebirth * 0.5) < 1e-6, "Rebirth Booster adds +50% per rebirth")

		-- cooldown passes
		local IslandService, WheelService, ShieldService = T.Service("IslandService"), T.Service("WheelService"), T.Service("ShieldService")
		T.Check(IslandService:_cooldown(me) == Config.Islands.Cooldown and Config.Islands.Cooldown == 12 * 3600, "island chests close for 12 hours")
		me:SetAttribute("Pass_IslandExpress", true)
		T.Check(IslandService:_cooldown(me) == 6 * 3600, "Island Express halves it")
		local wheel = WheelService:_cooldown(me)
		me:SetAttribute("Pass_WheelPlus", true)
		T.Check(WheelService:_cooldown(me) == wheel / 2, "Double Spins halves the wheel wait")
		local shieldEnds, shieldReady = ShieldService:_times(me)
		me:SetAttribute("Pass_ShieldPro", true)
		local proEnds, proReady = ShieldService:_times(me)
		T.Check(proEnds - shieldEnds == Config.Shield.Seconds and shieldReady - proReady == Config.Shield.Cooldown / 2, "Shield Pro: twice as long, recharges twice as fast")

		-- Gift Boost
		local GiftService = T.Service("GiftService")
		local gift = GiftService:GetReward(me, 1)
		me:SetAttribute("Pass_GiftBoost", true)
		local boostedGift = GiftService:GetReward(me, 1)
		T.Check(boostedGift > gift * 1.2, ("Gift Boost pays more (%d vs %d)"):format(boostedGift, gift))
	end,
})

table.insert(Scenarios, {
	Name = "staff_gifts",
	MaxSeconds = 400,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Boss", UserId = 7000 })
		local helper = T.AddPlayer("Helper", { UserId = 7001 })
		local buddy = T.AddPlayer("Buddy", { UserId = 7002 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local DataService = T.Service("DataService")
		local StaffService = T.Service("StaffService")
		local CollectionService = game:GetService("CollectionService")
		T.Check(me:GetAttribute("AdminRank") == 4, "Boss is Owner in Studio")
		helper:SetAttribute("AdminRank", 0)
		buddy:SetAttribute("AdminRank", 0)
		local function run(player, text)
			local ok, message = T.Admin(player, text)
			T.Wait(0.2)
			return ok, tostring(message)
		end

		-- no rank, no permissions: nothing works
		local ok = run(helper, ";kill buddy")
		T.Check(ok == false, "a player with no rank and no permissions can't run commands")

		-- the Owner ticks permission groups
		for _, group in Config.Admin.Permissions do
			T.Check(group.Id ~= nil and group.Name ~= nil and (group.Commands ~= nil or group.MaxRank ~= nil), "group " .. tostring(group.Id) .. " is defined")
		end
		ok = run(me, ";giveperm helper Disasters")
		T.Check(ok == true and helper:GetAttribute("AdminPerms") == "Disasters", "giveperm sets AdminPerms (" .. tostring(helper:GetAttribute("AdminPerms")) .. ")")
		ok = run(helper, ";stopdisaster")
		T.Check(ok == true, "the Disasters group lets Helper stop disasters")
		ok = run(helper, ";givecash helper 1000")
		T.Check(ok == false, "...but not give cash (Economy isn't ticked)")
		ok = run(helper, ";kill buddy")
		T.Check(ok == false, "...and not Mod commands")
		ok = run(helper, ";giveperm helper all")
		T.Check(ok == false, "permissions can't be ticked by a non-owner")
		run(me, ";giveperm helper Mod")
		T.Check(helper:GetAttribute("AdminPerms") == "Disasters,Mod", "two groups: " .. tostring(helper:GetAttribute("AdminPerms")))
		ok = run(helper, ";freeze buddy")
		T.Check(ok == true and T.Root(buddy).Anchored, "Mod group: Helper can freeze Buddy")
		run(helper, ";thaw buddy")
		run(helper, ";kill me")
		T.Check(T.Humanoid(me).Health > 0, "a permission holder can't harm the Owner")
		ok = run(me, ";takeperm helper Mod")
		T.Check(helper:GetAttribute("AdminPerms") == "Disasters", "takeperm removes a group")
		run(me, ";takeperm helper all")
		T.Check((helper:GetAttribute("AdminPerms") or "") == "", "takeperm all removes everything")
		T.Check(run(helper, ";stopdisaster") == false, "...and the commands stop working")
		-- Owner-only commands can never be granted
		run(me, ";giveperm helper all")
		T.Check(run(helper, ";unadmin me") == false and run(helper, ";shutdown") == false, "Owner commands are never granted")
		run(me, ";takeperm helper all")

		-- glowing titles
		ok = run(helper, ";title buddy gold Nope")
		T.Check(ok == false, "no title without the Titles permission")
		run(me, ";giveperm helper Titles")
		ok = run(helper, ";title buddy gold Big Boss")
		T.Check(ok == true and buddy:GetAttribute("TitleText") == "Big Boss" and buddy:GetAttribute("TitleColor") == "#FFD700", "title set (" .. tostring(buddy:GetAttribute("TitleText")) .. ")")
		T.Wait(0.5)
		local function titleLabel(p)
			local head = p.Character and p.Character:FindFirstChild("Head")
			local tag = head and head:FindFirstChild("StaffTitle")
			return tag and tag:FindFirstChild("Label"), tag
		end
		local label = titleLabel(buddy)
		T.Check(label ~= nil and label.Text == "Big Boss" and CollectionService:HasTag(label, "GlowTitle"), "glowing title above the head")
		T.Check(label ~= nil and label:FindFirstChildOfClass("UIStroke") ~= nil, "the title has a glow outline")
		run(me, ";title buddy #00ff88 Mint <b>Boss</b>")
		T.Check(buddy:GetAttribute("TitleColor") == "#00FF88" and buddy:GetAttribute("TitleText") == "Mint bBoss/b", "custom hex colour, markup stripped (" .. tostring(buddy:GetAttribute("TitleText")) .. ")")
		run(me, ";title buddy rainbow Rainbow King")
		label = titleLabel(buddy)
		T.Check(buddy:GetAttribute("TitleColor") == "rainbow" and label and label:GetAttribute("Rainbow") == true, "rainbow titles")
		ok = run(me, ";title buddy notacolour Hi")
		T.Check(ok == true and buddy:GetAttribute("TitleText") == "Rainbow King", "a bad colour changes nothing")
		ok = run(me, ";title buddy red " .. string.rep("x", 60))
		T.Check(#tostring(buddy:GetAttribute("TitleText")) <= Config.Admin.MaxTitleLength, "titles are length limited")
		-- stays after dying
		T.Humanoid(buddy).Health = 0
		T.Wait(7)
		T.Check(titleLabel(buddy) ~= nil, "the title comes back after respawning")
		-- saved: a fresh read of the registry still has it
		local info = StaffService:GetInfo(7002, "Buddy")
		T.Check(info.Title ~= nil and info.Title.Text:sub(1, 1) == "x", "titles are saved in the registry")
		run(me, ";cleartitle buddy")
		T.Wait(0.5)
		T.Check(buddy:GetAttribute("TitleText") == nil and titleLabel(buddy) == nil, "cleartitle removes it")

		-- passes for players who are offline arrive when they join
		ok = run(me, ";givepass 7003 VIP")
		T.Check(ok == true, "givepass works for an offline UserId")
		T.Check(table.find(StaffService:GetInfo(7003, "Late").Pending, "VIP") ~= nil, "the pass is waiting")
		local late = T.AddPlayer("Late", { UserId = 7003 })
		T.Wait(6)
		T.Check(late:GetAttribute("Pass_VIP") == true, "the waiting pass is granted on join")
		T.Check(DataService:Get(late).Passes.VIP == true, "...and saved")
		T.Check(#StaffService:GetInfo(7003, "Late").Pending == 0, "...and no longer waiting")
		run(me, ";givepass buddy DoubleCash")
		T.Check(buddy:GetAttribute("Pass_DoubleCash") == true and T.Noticed(buddy, "Boss gave you"), "admins can give passes (buddy is told who gave it)")
		run(me, ";removepass buddy DoubleCash")

		-- the Staff tab
		run(me, ";giveperm buddy Fun")
		T.Client(function()
			T.Controller("UI"):Open("Admin")
		end)
		T.Wait(0.5)
		local gui = me.PlayerGui
		local tab = T.FindButton(gui, "^STAFF$")
		T.Check(tab ~= nil, "the admin panel has a Staff tab")
		T.Client(function()
			T.Engine.Click(tab)
		end)
		T.Wait(1)
		T.Check(T.FindText(gui, "Staff & titles") ~= nil, "the Staff tab lists staff")
		local box
		for _, d in gui:GetDescendants() do
			if d:IsA("TextBox") and d.PlaceholderText == "Username or UserId..." then
				box = d
			end
		end
		T.Check(box ~= nil, "the Staff tab has a player box")
		if box then
			box.Text = "Buddy"
			T.Client(function()
				T.Engine.Click(T.FindButton(gui, "^SELECT$"))
			end)
			T.Wait(1)
			T.Check(T.FindText(gui, "⚙️ Buddy") ~= nil, "Buddy is selected")
			local ticks = 0
			for _, b in T.Buttons(gui) do
				if b:IsA("TextButton") and (b.Text == "☐" or b.Text == "☑") then
					ticks += 1
				end
			end
			T.Check(ticks == #Config.Admin.Permissions, "one tick box per group (" .. ticks .. ")")
			-- tick "Economy" for Buddy
			local before = buddy:GetAttribute("AdminPerms")
			local row = T.FindText(gui, "💰 Cash & progress")
			local tick = row and row.Parent and row.Parent:FindFirstChildWhichIsA("TextButton")
			T.Check(tick ~= nil, "found the Economy row")
			if tick then
				T.Client(function()
					T.Engine.Click(tick)
				end)
			end
			T.Wait(1)
			T.Check(before == "Fun" and buddy:GetAttribute("AdminPerms") == "Economy,Fun", "ticking Economy in the panel gives it (" .. tostring(buddy:GetAttribute("AdminPerms")) .. ")")
		end
		T.Client(function()
			T.Controller("UI"):Close()
		end)
		run(me, ";takeperm buddy all")

		-- gifts (simulated in Studio): chat/remote
		local function gift(kind, key, target)
			T.Client(function()
				T.Remote("GiftItem"):FireServer(kind, key, target)
			end)
			T.Wait(2.2)
		end
		T.Check(Config.CanGift("Pass", "VIP") and Config.CanGift("Product", "CashSmall"), "passes and cash packs can be gifted")
		T.Check(not Config.CanGift("Product", "CashRain") and not Config.CanGift("Product", "LaunchNuke") and not Config.CanGift("Pass", "Nope"), "server events and unknown items can't")
		for key in Config.GamePasses do
			T.Check(Config.GiftProducts[key] ~= nil, "gift slot for " .. key)
		end
		gift("Pass", "DoubleCash", 7002)
		T.Check(buddy:GetAttribute("Pass_DoubleCash") == true and me:GetAttribute("Pass_DoubleCash") == nil, "gifted pass goes to Buddy, not the buyer")
		T.Check(T.Noticed(buddy, "gave you") and T.Noticed(me, "got your gift"), "both are told")
		gift("Pass", "DoubleCash", 7002)
		T.Check(T.Noticed(me, "already owns"), "can't gift a pass they own")
		gift("Pass", "SuperSpeed", me.UserId)
		T.Check(me:GetAttribute("Pass_SuperSpeed") == nil, "can't gift to yourself")
		gift("Pass", "SuperSpeed", 999999)
		gift("Pass", "NotAPass", 7002)
		gift("Product", "CashRain", 7002)
		T.Check(buddy:GetAttribute("Pass_SuperSpeed") == nil, "bad gifts are ignored")
		local cash = DataService:Get(buddy).Cash
		gift("Product", "CashSmall", 7002)
		T.Check(DataService:Get(buddy).Cash > cash, "gifted cash pack pays Buddy")

		-- the Gift button and the picker in the shop
		T.Client(function()
			T.Controller("UI"):Open("Shop")
		end)
		T.Wait(0.5)
		local card
		for _, d in me.PlayerGui:GetDescendants() do
			if d.Name == "VIP" and d:IsA("Frame") then
				card = d
			end
		end
		local giftButton = card and card:FindFirstChildWhichIsA("TextButton", true)
		local found
		if card then
			for _, b in T.Buttons(card) do
				if b:IsA("TextButton") and b.Text == "🎁" then
					found = b
				end
			end
		end
		T.Check(found ~= nil and giftButton ~= nil, "the VIP card has a Gift button")
		if found then
			T.Client(function()
				T.Engine.Click(found)
			end)
			T.Wait(0.5)
			local pickButton = T.FindButton(me.PlayerGui, "Buddy")
			T.Check(pickButton ~= nil, "the picker lists the other players")
			T.Check(T.FindButton(me.PlayerGui, "%(@Boss%)") == nil, "...but not yourself")
			if pickButton then
				T.Client(function()
					T.Engine.Click(pickButton)
				end)
				T.Wait(2.2)
				T.Check(buddy:GetAttribute("Pass_VIP") == true, "picking Buddy sends the VIP gift")
			end
		end
	end,
})

table.insert(Scenarios, {
	Name = "progress_systems",
	MaxSeconds = 600,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Pro", UserId = 7100, Achievements = true, LiveEvents = true, Tutorial = true })
		local ws = game:GetService("Workspace")
		local function now()
			return T.Engine.EpochBase + T.Engine.Now -- the game's clock
		end
		local friend = T.AddPlayer("Friend", { UserId = 7101 })
		T.Wait(6)
		local Config = T.Shared("Config")
		local DataService = T.Service("DataService")
		local AchievementService = T.Service("AchievementService")
		local SeasonService = T.Service("SeasonService")
		local CosmeticService = T.Service("CosmeticService")
		local EventService = T.Service("EventService")
		local PetService = T.Service("PetService")
		local TradeService = T.Service("TradeService")
		local SocialService = T.Service("SocialService")
		local TutorialService = T.Service("TutorialService")
		local TycoonService = T.Service("TycoonService")
		local data, fdata = DataService:Get(me), DataService:Get(friend)

		---------------- achievements ----------------
		T.Check(#Config.Achievements.List >= 40, "plenty of achievements (" .. #Config.Achievements.List .. ")")
		for _, a in Config.Achievements.List do
			T.Check(a.Target > 0 and a.Reward ~= nil and a.Name ~= nil, a.Id .. " is well formed")
			if a.Reward.Cosmetic then
				T.Check(Config.Cosmetics.ById[a.Reward.Cosmetic] ~= nil, a.Id .. " rewards a real cosmetic")
			end
		end
		local cash = data.Cash
		data.Stats.Upgrades = 10
		AchievementService:Check(me)
		T.Check(data.Achievements.Upgrades_1 == true and data.Cash > cash, "Builder I pays when 10 upgrades are bought")
		T.Check(not data.Achievements.Upgrades_2, "...but not the next tier")
		cash = data.Cash
		AchievementService:Check(me)
		T.Check(data.Cash == cash, "an achievement pays only once")
		T.Check(T.Noticed(me, "Achievement"), "the player is told")
		local state = T.Client(function()
			return { T.Remote("AchievementsGet"):InvokeServer() }
		end)[1]
		T.Check(state and state.Done.Upgrades_1 and state.Stats.Upgrades >= 10 and state.Total == #Config.Achievements.List, "the panel data has progress and done flags")
		local page = T.Client(function()
			return { T.Remote("StatsGet"):InvokeServer() }
		end)[1]
		T.Check(page and #page >= 12, "the stats page has " .. tostring(page and #page) .. " lines")
		-- upgrades keep counting through a rebirth
		TycoonService:Rebirth(me, true)
		T.Wait(1)
		T.Check(AchievementService:GetStat(me, data, "Upgrades") >= 10, "total upgrades survive a rebirth")

		---------------- season ----------------
		data.Season = { Id = (Config.CurrentSeason(now())), XP = 0, Free = {}, Premium = {} } -- (the achievements above gave XP)
		SeasonService:Sync(me)
		local season = SeasonService:GetState(me)
		T.Check(season ~= nil and season.Level == 0 and season.Name ~= nil and season.EndsAt > now(), "the season has started")
		T.Check(SeasonService:LevelOf(0) == 0 and SeasonService:LevelOf(100) == 1 and SeasonService:LevelOf(240) == 2, "levels follow the XP curve")
		T.Check(SeasonService:LevelOf(1e9) == Config.Season.Levels, "the level is capped")
		local ok = T.Server(function()
			return SeasonService:Claim(me, "Free", 1)
		end)
		T.Check(not ok, "can't claim a level you haven't reached")
		T.Server(function()
			SeasonService:AddXp(me, "Admin", 100)
		end)
		T.Check(SeasonService:GetLevel(me) == 1 and me:GetAttribute("SeasonReady") == 1, "100 XP = level 1 with a reward waiting")
		cash = data.Cash
		ok = T.Server(function()
			return SeasonService:Claim(me, "Free", 1)
		end)
		T.Check(ok and data.Cash > cash, "free level 1 pays")
		ok = T.Server(function()
			return SeasonService:Claim(me, "Free", 1)
		end)
		T.Check(not ok, "a reward can't be claimed twice")
		ok = T.Server(function()
			return SeasonService:Claim(me, "Premium", 1)
		end)
		T.Check(not ok, "the premium track needs the Season Pass")
		T.Check(not (T.Server(function()
			return SeasonService:Claim(me, "Nope", 1)
		end)) and not (T.Server(function()
			return SeasonService:Claim(me, "Free", 9999)
		end)), "bad claims are refused")
		me:SetAttribute("Pass_SeasonPass", true)
		T.Server(function()
			SeasonService:AddXp(me, "Admin", 30000)
		end)
		T.Check(SeasonService:GetLevel(me) == Config.Season.Levels, "plenty of XP reaches the top level")
		local claimedAll = true
		for level, reward in Config.Season.Premium do
			local good = T.Server(function()
				return SeasonService:Claim(me, "Premium", level)
			end)
			claimedAll = claimedAll and good
			T.Wait(0.01)
		end
		T.Check(claimedAll, "every premium reward can be claimed with the pass")
		for level in Config.Season.Free do
			T.Server(function()
				return SeasonService:Claim(me, "Free", level)
			end)
		end
		T.Check(CosmeticService:GetState(me).Owned.Hat_Season and CosmeticService:GetState(me).Owned.Trail_Season, "season cosmetic rewards arrive")
		T.Check(#data.Pets.Owned >= 3, "season pet rewards arrive (" .. #data.Pets.Owned .. ")")
		T.Check(me:GetAttribute("SeasonReady") == 0, "nothing left to claim")
		data.Season.Id = -4 -- an old season
		local fresh = SeasonService:GetState(me)
		T.Check(fresh.XP == 0 and fresh.Level == 0 and next(fresh.Free) == nil, "a new season starts from zero")
		me:SetAttribute("Pass_SeasonPass", nil)

		---------------- cosmetics ----------------
		local function visuals(p)
			local character = p.Character
			return character:FindFirstChild("Cosmetic_Hat"), character:FindFirstChild("Cosmetic_Trail", true), character:FindFirstChild("Cosmetic_Aura", true)
		end
		data.Cash = 0
		local bought = T.Server(function()
			return CosmeticService:Buy(me, "Hat_Party")
		end)
		T.Check(not bought, "can't buy without cash")
		data.Cash = 1e9
		bought = T.Server(function()
			return CosmeticService:Buy(me, "Hat_Party")
		end)
		T.Check(bought and data.Cosmetics.Owned.Hat_Party and data.Cash == 1e9 - Config.Cosmetics.ById.Hat_Party.Price, "buying with cash")
		T.Check(not (T.Server(function()
			return CosmeticService:Buy(me, "Hat_Party")
		end)), "can't buy twice")
		T.Check(not (T.Server(function()
			return CosmeticService:Buy(me, "Hat_Season")
		end)), "reward cosmetics can't be bought")
		T.Check(not (T.Server(function()
			return CosmeticService:Equip(me, "Trail_Flame")
		end)), "can't wear what you don't own")
		T.Check(T.Server(function()
			return CosmeticService:Equip(me, "Hat_Party")
		end), "equip")
		local hat = visuals(me)
		T.Check(hat ~= nil and #hat:GetChildren() >= 4, "the hat is built from parts (" .. tostring(hat and #hat:GetChildren()) .. ")")
		for _, id in { "Trail_Flame", "Trail_Rainbow", "Aura_Sparkle", "Aura_Void", "Hat_Halo", "Hat_Horns", "Hat_TopHat", "Hat_Crown", "Hat_Wizard" } do
			T.Server(function()
				return CosmeticService:Buy(me, id)
			end)
			T.Check(data.Cosmetics.Owned[id], "bought " .. id .. " (Robux ones are simulated in Studio)")
		end
		for _, id in { "Trail_Rainbow", "Aura_Void" } do
			T.Server(function()
				return CosmeticService:Equip(me, id)
			end)
		end
		local _, trail, aura = visuals(me)
		T.Check(trail ~= nil and aura ~= nil, "trail and aura are on the character")
		for _, id in { "Hat_Halo", "Hat_Horns", "Hat_TopHat", "Hat_Crown", "Hat_Wizard" } do
			T.Server(function()
				return CosmeticService:Equip(me, id)
			end)
			local worn = visuals(me)
			T.Check(worn ~= nil and #worn:GetChildren() >= 2, id .. " builds")
		end
		T.Check(select(1, visuals(me)) ~= nil and #me.Character:GetChildren() < 40, "only one hat at a time")
		T.Humanoid(me).Health = 0
		T.Wait(7)
		hat, trail, aura = visuals(me)
		T.Check(hat ~= nil and trail ~= nil and aura ~= nil, "cosmetics come back after respawning")
		T.Server(function()
			return CosmeticService:Unequip(me, "Hat")
		end)
		T.Check(visuals(me) == nil, "unequip removes the hat")
		T.Check(CosmeticService:GetState(me).Equipped.Hat == nil, "...and it is saved as off")
		local shown = T.Client(function()
			return { T.Remote("CosmeticsAction"):InvokeServer("Equip", "Hat_Crown") }
		end)
		T.Check(shown[1] == true, "equip works through the remote")
		T.Check(CosmeticService:Take(me, "Hat_Crown") and visuals(me) == nil, "taking a cosmetic removes it from the character")
		T.Check(select(1, T.Server(function()
			return CosmeticService:Give(me, "Hat_Crown")
		end)), "giving works")

		---------------- live events ----------------
		local function at(t)
			EventService.Clock = function()
				return t
			end
			EventService:Update()
		end
		local WED, HALLOWEEN, WINTER, NEWYEAR, SUMMER = 1773230400, 1793188800, 1797940800, 1798804800, 1783512000
		at(WED)
		T.Check(ws:GetAttribute("LiveEventMult") == 1 and #EventService:GetActive() == 0, "a normal Wednesday has no event")
		local base = me:GetAttribute("Multiplier")
		at(1773421200) -- Friday 17:00 UTC
		T.Check(not EventService:IsActive("Weekend"), "the weekend starts at 18:00 on Friday")
		at(1773424800) -- Friday 18:00
		T.Check(EventService:IsActive("Weekend") and ws:GetAttribute("LiveEventMult") == 2, "Friday 18:00 starts the weekend bonus")
		T.Check(math.abs(me:GetAttribute("Multiplier") - base * 2) < 1e-9, "everyone earns 2x (" .. tostring(me:GetAttribute("Multiplier")) .. ")")
		at(1773615600) -- Sunday 23:00
		T.Check(EventService:IsActive("Weekend"), "still on Sunday night")
		at(1773622800) -- Monday 01:00
		T.Check(not EventService:IsActive("Weekend") and ws:GetAttribute("LiveEventMult") == 1, "over on Monday")
		T.Check(math.abs(me:GetAttribute("Multiplier") - base) < 1e-9, "the multiplier goes back")
		at(HALLOWEEN)
		T.Check(EventService:IsActive("Halloween") and not EventService:IsActive("Winter"), "Halloween event")
		at(NEWYEAR)
		T.Check(EventService:IsActive("Winter"), "the winter event runs over New Year")
		at(WINTER)
		T.Check(EventService:IsActive("Winter") and ws:GetAttribute("LiveEvents") == "Winter", "winter event")
		at(SUMMER)
		T.Check(EventService:IsActive("Summer") and ws:GetAttribute("LiveEventMult") == 1.5, "summer event is 1.5x")
		at(WED)
		-- event eggs
		data.Cash = 1e12
		local hatched, why = T.Server(function()
			return PetService:Hatch(me, "Spooky")
		end)
		T.Check(not hatched, "the Spooky Egg can't be bought outside its event")
		T.Check(select(1, T.Server(function()
			return PetService:Hatch(me, "Basic")
		end)), "normal eggs always work")
		for _ = 1, 400 do
			local pet = PetService:_roll(Config.Pets.Eggs[2], false)
			if pet.Event then
				T.Check(false, "a normal egg hatched an event pet: " .. pet.Id)
				break
			end
		end
		at(HALLOWEEN)
		data.Pets.Owned = {}
		data.Pets.Equipped = {}
		hatched = T.Server(function()
			return PetService:Hatch(me, "Spooky")
		end)
		T.Check(hatched, "the Spooky Egg works during Halloween")
		T.Check(Config.PetById[data.Pets.Owned[1].Id].Event == "Halloween", "...and gives a Halloween pet")
		local eggs = PetService:_state(me).Eggs
		local spooky
		for _, egg in eggs do
			if egg.Id == "Spooky" then
				spooky = egg
			end
		end
		T.Check(spooky and spooky.Active == true, "the pet panel data marks the egg as on sale")
		EventService:Force("Winter", true)
		T.Check(EventService:IsActive("Winter"), ";event can force an event on")
		EventService:Force("Winter", false)
		EventService:Force("Halloween", false)
		T.Check(not EventService:IsActive("Winter") and not EventService:IsActive("Halloween"), "...and off")
		EventService:Force("Winter", nil)
		EventService:Force("Halloween", nil)
		local okEvent = T.Admin(me, ";event Summer on")
		T.Check(okEvent and EventService:IsActive("Summer"), "the admin command ;event")
		T.Admin(me, ";event Summer auto")
		at(WED)
		T.Check(not EventService:IsActive("Summer"), "auto follows the calendar again")

		---------------- trading ----------------
		data.Pets = { Owned = {}, Equipped = {}, NextUid = 1, Hatched = data.Pets.Hatched }
		fdata.Pets = { Owned = {}, Equipped = {}, NextUid = 1, Hatched = 0 }
		PetService:Give(me, "Dog", 3)
		PetService:Give(me, "Dragon", 1)
		PetService:Give(friend, "Cat", 2)
		PetService:Equip(me, 4)
		T.Check(select(1, T.Server(function()
			return TradeService:Invite(me, friend.UserId)
		end)), "invite")
		T.Check(not (T.Server(function()
			return TradeService:Invite(me, me.UserId)
		end)), "can't trade with yourself")
		T.Check(not (T.Server(function()
			return TradeService:Add(me, 1)
		end)), "can't add pets before the trade starts")
		T.Check(select(1, T.Server(function()
			return TradeService:Respond(friend, true)
		end)), "accepting an invite starts the trade")
		T.Check(#T.Sent(friend, "TradeUpdate") >= 1, "both players get the trade state")
		T.Check(not (T.Server(function()
			return TradeService:Add(me, 999)
		end)), "can't offer a pet you don't have")
		T.Check(select(1, T.Server(function()
			return TradeService:Add(me, 4)
		end)) and select(1, T.Server(function()
			return TradeService:Add(friend, 1)
		end)), "both offer a pet")
		T.Check(not (T.Server(function()
			return TradeService:Accept(me)
		end)), "Accept is locked for a moment after a change")
		T.Wait(Config.Trading.ConfirmDelay + 0.5)
		T.Check(select(1, T.Server(function()
			return TradeService:Accept(me)
		end)), "first accept waits for the other")
		T.Check(select(1, T.Server(function()
			return TradeService:Add(friend, 2)
		end)), "adding another pet...")
		T.Check(not (T.Server(function()
			return TradeService:Accept(friend)
		end)), "...resets the delay")
		T.Wait(Config.Trading.ConfirmDelay + 0.5)
		T.Check(not data.Pets.Owned[1].Gone, "nothing moved yet")
		T.Check(select(1, T.Server(function()
			return TradeService:Accept(friend)
		end)), "friend accepts")
		T.Check(#data.Pets.Owned == 4 and #fdata.Pets.Owned == 2, "the accept before the change was reset - still waiting")
		T.Check(select(1, T.Server(function()
			return TradeService:Accept(me)
		end)), "me accepts again")
		T.Wait(0.5)
		T.Check(#data.Pets.Owned == 5 and #fdata.Pets.Owned == 1, "pets swapped (" .. #data.Pets.Owned .. " / " .. #fdata.Pets.Owned .. ")")
		local mineIds, theirIds = {}, {}
		for _, pet in data.Pets.Owned do
			table.insert(mineIds, pet.Id)
		end
		for _, pet in fdata.Pets.Owned do
			table.insert(theirIds, pet.Id)
		end
		T.Check(table.find(theirIds, "Dragon") ~= nil and table.find(mineIds, "Cat") ~= nil and table.find(mineIds, "Dragon") == nil, "the right pets moved")
		T.Check(#data.Pets.Equipped == 0, "a traded pet is unequipped for its old owner")
		local uids = {}
		for _, pet in data.Pets.Owned do
			T.Check(not uids[pet.Uid], "uid " .. pet.Uid .. " is unique")
			uids[pet.Uid] = true
		end
		T.Check((data.Stats.Trades or 0) == 1 and (fdata.Stats.Trades or 0) == 1, "trades are counted")
		-- cancel, decline, leaving
		T.Server(function()
			TradeService:Invite(me, friend.UserId)
			TradeService:Respond(friend, true)
			TradeService:Add(me, data.Pets.Owned[1].Uid)
			return TradeService:Cancel(friend)
		end)
		T.Check(select(1, T.Server(function()
			return TradeService:Invite(me, friend.UserId)
		end)), "a new trade can start after a cancel")
		T.Server(function()
			return TradeService:Respond(friend, false)
		end)
		T.Check(not (T.Server(function()
			return TradeService:Add(me, data.Pets.Owned[1].Uid)
		end)), "a declined invite starts nothing")
		-- a full storage cancels the trade
		fdata.Pets.Owned = {}
		for i = 1, Config.Pets.MaxOwned do
			table.insert(fdata.Pets.Owned, { Uid = 100 + i, Id = "Dog" })
		end
		T.Server(function()
			TradeService:Invite(me, friend.UserId)
			TradeService:Respond(friend, true)
			TradeService:Add(me, data.Pets.Owned[1].Uid)
		end)
		T.Wait(Config.Trading.ConfirmDelay + 0.5)
		local before = #data.Pets.Owned
		T.Server(function()
			TradeService:Accept(me)
			return TradeService:Accept(friend)
		end)
		T.Check(#data.Pets.Owned == before, "a trade that would overfill someone's storage is cancelled")
		-- the remote enforces its rate limit and types
		local bad = T.Client(function()
			return { T.Remote("TradeAction"):InvokeServer("Add", "x") }
		end)
		T.Check(bad[1] == false, "bad trade input is refused")

		---------------- social ----------------
		T.Engine.PrivateServer = true
		DataService:RefreshMultiplier(me)
		local vip = me:GetAttribute("Multiplier")
		T.Engine.PrivateServer = false
		DataService:RefreshMultiplier(me)
		T.Check(math.abs(vip / me:GetAttribute("Multiplier") - 1 + Config.Social.PrivateServerBonus * -1 - 0) < 1e-6 or math.abs(vip / me:GetAttribute("Multiplier") - (1 + Config.Social.PrivateServerBonus)) < 1e-6, "private servers earn +" .. Config.Social.PrivateServerBonus * 100 .. "%")
		local claim = T.Server(function()
			return SocialService:ClaimGroup(me)
		end)
		T.Check(not claim, "no group reward while no group is set")
		Config.Social.GroupId = 5555
		claim = T.Server(function()
			return SocialService:ClaimGroup(me)
		end)
		T.Check(not claim, "can't claim without being in the group")
		T.Engine.Groups[me.UserId] = { [5555] = true }
		cash = data.Cash
		claim = T.Server(function()
			return SocialService:ClaimGroup(me)
		end)
		T.Check(claim and data.Cash > cash and data.Social.Group, "group members get the reward")
		T.Check(not (T.Server(function()
			return SocialService:ClaimGroup(me)
		end)), "only once")
		Config.Social.GroupId = 0

		---------------- tutorial ----------------
		T.Check(me:GetAttribute("TutorialDone") ~= nil, "the tutorial flag is set")
		data.Tutorial.Done = false
		data.Purchased = { F1_1 = true }
		data.Stats.Upgrades = 0
		data.Wheel.Spins = 0
		data.DailyStreak = 0
		cash = data.Cash
		T.Client(function()
			T.Remote("TutorialClaim"):FireServer()
		end)
		T.Wait(0.5)
		T.Check(not data.Tutorial.Done and data.Cash == cash, "the tutorial can't be skipped by faking the client")
		data.Stats.Upgrades = Config.Tutorial.BuyUpgrades
		data.Wheel.Spins = 1
		data.DailyStreak = 1
		T.Client(function()
			T.Remote("TutorialClaim"):FireServer()
		end)
		T.Wait(0.5)
		T.Check(data.Tutorial.Done and data.Cash > cash and me:GetAttribute("TutorialDone") == true, "finishing it pays")
		cash = data.Cash
		T.Client(function()
			T.Remote("TutorialClaim"):FireServer()
		end)
		T.Wait(0.5)
		T.Check(data.Cash == cash, "...once")

		---------------- boards ----------------
		local boards = T.Client(function()
			return { T.Remote("BoardsGet"):InvokeServer() }
		end)[1]
		T.Check(boards and #boards.Earned >= 1 and #boards.Rebirths >= 1 and #boards.Hatched >= 1, "the boards list the players here")
	end,
})

table.insert(Scenarios, {
	Name = "new_panels",
	MaxSeconds = 600,
	Run = function(T, place)
		local game, me = T.Boot(place, { Name = "Ui", UserId = 7200, Achievements = true, LiveEvents = true, Tutorial = true })
		local friend = T.AddPlayer("Pal", { UserId = 7201 })
		T.Wait(9)
		local Config = T.Shared("Config")
		local DataService = T.Service("DataService")
		local TycoonService = T.Service("TycoonService")
		local SeasonService = T.Service("SeasonService")
		local EventService = T.Service("EventService")
		local PetService = T.Service("PetService")
		local TradeService = T.Service("TradeService")
		local UI = T.Controller("UI")
		local ws = game:GetService("Workspace")
		local data = DataService:Get(me)
		local gui = me.PlayerGui
		local function click(button)
			T.Client(function()
				T.Engine.Click(button)
			end)
			T.Wait(0.6)
		end
		local function openFromMenu(icon, panel)
			local more = T.FindButton(gui, "➕")
			T.Check(more ~= nil, "the MORE button exists")
			click(more)
			local button = T.FindButton(gui, icon)
			T.Check(button ~= nil, "MORE lists " .. icon)
			if button then
				click(button)
			end
			T.Check(UI.Current == panel, panel .. " opens from the menu (current: " .. tostring(UI.Current) .. ")")
		end
		local function close()
			T.Client(function()
				UI:Close()
			end)
			T.Wait(0.3)
		end

		---------------- the menu ----------------
		T.Check(T.FindButton(gui, "🛒") ~= nil and T.FindButton(gui, "🐾") ~= nil, "the main menu buttons are on screen")
		T.Check(T.FindButton(gui, "🎫") == nil, "the extra buttons are hidden until MORE is pressed")
		local menuScale
		for _, d in gui:GetDescendants() do
			if d.Name == "Menu" and d:IsA("Frame") then
				menuScale = d:FindFirstChildOfClass("UIScale")
			end
		end
		T.Check(menuScale ~= nil, "the menu has a scale")
		local before = menuScale.Scale
		me:SetAttribute("UISize", 1.4)
		T.Wait(0.3)
		T.Check(menuScale.Scale > before * 1.3, "the UI size setting scales the menu (" .. before .. " -> " .. menuScale.Scale .. ")")
		T.Client(function()
			T.Remote("SaveSettings"):FireServer({ UISize = 99 })
		end)
		T.Wait(0.3)
		T.Check(data.Settings.UISize == 1.5, "the saved UI size is clamped")
		me:SetAttribute("UISize", 1)

		---------------- achievements ----------------
		data.Stats.Upgrades = 50
		T.Service("AchievementService"):Check(me)
		openFromMenu("🏆", "Achievements")
		T.Wait(0.6)
		T.Check(T.FindText(gui, "unlocked") ~= nil, "the achievements panel shows the total")
		T.Check(T.FindText(gui, "COMPLETE") == nil and T.FindText(gui, "Builder") ~= nil, "...and the next goal of each group")
		close()

		---------------- season ----------------
		T.Server(function()
			SeasonService:AddXp(me, "Admin", 300)
		end)
		T.Check(me:GetAttribute("SeasonReady") ~= nil and me:GetAttribute("SeasonReady") >= 1, "rewards are waiting")
		openFromMenu("🎫", "Season")
		T.Wait(0.8)
		T.Check(T.FindText(gui, "Season of") ~= nil, "the season panel shows its name")
		local claimButton = T.FindButton(gui, "^CLAIM$")
		T.Check(claimButton ~= nil, "a CLAIM button is available")
		local cash = data.Cash
		if claimButton then
			click(claimButton)
		end
		T.Check(data.Cash > cash, "claiming from the panel pays")
		T.Check(T.FindButton(gui, "GET SEASON PASS") ~= nil, "the pass button is shown to free players")
		close()

		---------------- style ----------------
		data.Cash = 1e7
		openFromMenu("✨", "Style")
		T.Wait(0.6)
		local buy = T.FindButton(gui, "%$40")
		T.Check(buy ~= nil, "the Flame Trail shows its price")
		for _, kind in Config.Cosmetics.Kinds do
			T.Check(T.FindButton(gui, kind.Name:upper()) ~= nil, kind.Name .. " tab")
		end
		if buy then
			click(buy)
		end
		T.Check(data.Cosmetics.Owned.Trail_Flame == true, "buying from the panel works")
		local wear = T.FindButton(gui, "^WEAR$")
		T.Check(wear ~= nil, "...then it can be worn")
		if wear then
			click(wear)
		end
		T.Check(data.Cosmetics.Equipped.Trail == "Trail_Flame" and T.FindButton(gui, "WEARING") ~= nil, "wearing from the panel works")
		click(T.FindButton(gui, "HATS"))
		T.Check(T.FindText(gui, "Party Hat") ~= nil, "the Hats tab lists hats")
		close()

		---------------- pets: event eggs hidden ----------------
		local petsFrame
		for _, d in gui:GetDescendants() do
			if d.Name == "EggSpooky" then
				petsFrame = d
			end
		end
		T.Check(petsFrame ~= nil and not petsFrame.Visible, "the Spooky Egg is hidden outside its event")
		EventService:Force("Halloween", true)
		T.Server(function()
			PetService:Resync(me)
		end)
		T.Wait(0.5)
		T.Check(petsFrame ~= nil and petsFrame.Visible, "...and shown during it")
		local hud = T.FindText(gui, "Spooky Season")
		T.Check(hud ~= nil, "the HUD announces the live event")
		EventService:Force("Halloween", nil)

		---------------- stats and boards ----------------
		openFromMenu("📊", "Stats")
		T.Wait(0.6)
		T.Check(T.FindText(gui, "Time played") ~= nil and T.FindText(gui, "Achievements") ~= nil, "the stats page lists the numbers")
		close()
		openFromMenu("🏅", "Boards")
		T.Wait(0.6)
		T.Check(T.FindButton(gui, "RICHEST") ~= nil and T.FindText(gui, "Ui") ~= nil, "the leaderboards show the players")
		click(T.FindButton(gui, "REBIRTHS"))
		close()

		---------------- social ----------------
		openFromMenu("🌐", "Social")
		T.Wait(0.6)
		T.Check(T.FindText(gui, "Group reward") ~= nil and T.FindText(gui, "Private") ~= nil, "the social panel has its sections")
		T.Check(T.FindButton(gui, "INVITE") ~= nil, "...and an invite button")
		close()

		---------------- trade ----------------
		PetService:Give(me, "Dog", 2)
		PetService:Give(friend, "Cat", 1)
		T.Server(function()
			PetService:Resync(me)
		end)
		T.Wait(0.5)
		openFromMenu("🤝", "Trade")
		T.Wait(0.5)
		local tradeButton = T.FindButton(gui, "TRADE$")
		T.Check(tradeButton ~= nil and T.FindText(gui, "Pal") ~= nil, "the trade panel lists other players")
		if tradeButton then
			click(tradeButton)
		end
		T.Check(#T.Sent(friend, "TradeInvited") >= 1, "pressing TRADE sends the other player a request")
		T.Server(function()
			return TradeService:Respond(friend, false)
		end)
		close()
		T.Server(function()
			TradeService:Invite(friend, me.UserId)
		end)
		T.Wait(1)
		local acceptPopup = T.FindButton(gui, "✅ YES")
		T.Check(acceptPopup ~= nil, "a trade request pops up")
		if acceptPopup then
			click(acceptPopup)
		end
		T.Wait(1)
		T.Check(UI.Current == "Trade", "accepting opens the trade window")
		T.Check(T.FindText(gui, "YOUR OFFER") ~= nil and T.FindText(gui, "Pal") ~= nil, "both offers are shown")
		local petCard
		for _, b in T.Buttons(gui) do
			if b:IsA("TextButton") and b.Text == "" and b.Parent and b.Parent.Name ~= "Content" and T.IsShown(b) then
				petCard = petCard or b
			end
		end
		T.Check(petCard ~= nil, "my pets are listed")
		if petCard then
			click(petCard)
		end
		T.Check(select(1, T.Server(function()
			return TradeService:Add(friend, 1)
		end)), "the other player offers a pet")
		T.Wait(0.8)
		T.Check(T.FindButton(gui, "ACCEPT %(") ~= nil, "Accept shows a countdown after a change")
		T.Wait(Config.Trading.ConfirmDelay + 1)
		local accept = T.FindButton(gui, "✅ ACCEPT")
		T.Check(accept ~= nil, "then Accept is ready")
		if accept then
			click(accept)
		end
		T.Check(T.FindButton(gui, "WAITING") ~= nil, "waiting for the other side")
		T.Server(function()
			return TradeService:Accept(friend)
		end)
		T.Wait(1)
		local cats = 0
		for _, pet in data.Pets.Owned do
			cats += pet.Id == "Cat" and 1 or 0
		end
		T.Check(cats == 1, "the trade completed and I got the Cat")
		T.Check(T.FindButton(gui, "✅ ACCEPT") == nil and T.FindButton(gui, "TRADE$") ~= nil, "the window goes back to the player list")
		close()

		---------------- tutorial ----------------
		local banner
		for _, d in gui:GetDescendants() do
			if d.Name == "Tutorial" and d:IsA("Frame") then
				banner = d
			end
		end
		T.Check(banner ~= nil and banner.Visible, "the tutorial banner is up for a new player")
		T.Check(T.FindText(gui, "1/3") ~= nil or T.FindText(gui, "2/3") ~= nil or T.FindText(gui, "3/3") ~= nil, "it shows a step")
		data.Tutorial.Done = false
		me:SetAttribute("TutorialDone", false)
		T.Client(function()
			T.Remote("SpinWheel"):InvokeServer()
		end)
		T.Client(function()
			T.Remote("ClaimDaily"):InvokeServer()
		end)
		DataService:AddCash(me, 1e6, false)
		for _ = 1, 3 do
			local target
			for _, item in T.Shared("TycoonItems").List do
				if item.Cost > 0 and item.Kind ~= "Secret" and T.Shared("TycoonItems").IsAvailable(item, data.Purchased) then
					target = item
					break
				end
			end
			TycoonService:TryPurchase(me, target.Id)
		end
		T.Wait(5)
		T.Check(data.Tutorial.Done == true, "finishing every step completes the tutorial")
		T.Check(T.FindText(gui, "Well done") ~= nil or not banner.Visible, "the banner says well done")
	end,
})

return Scenarios
