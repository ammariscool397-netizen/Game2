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
		while count(data.Purchased) < TycoonItems.BuyableCount and T.Engine.Now - start < 7 * 3600 do
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
		T.Check(elapsed > 1.5 * 3600 and elapsed < 5 * 3600, ("full tower takes 1.5-5 hours of optimal play (took %.2f h)"):format(elapsed / 3600))

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
		T.Check(player:GetAttribute("Multiplier") == 1.5, "rebirth multiplier 1.5x (got " .. tostring(player:GetAttribute("Multiplier")) .. ")")
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
		T.Check(me.Character:FindFirstChildOfClass("ForceField") == nil, ";unff")
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
		T.Check(math.abs(data.Cash - cash - expected) < 1, "cash pack pays max(min, minutes of income)")
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

for _, key in { "CoinRush", "FallingTiles", "MeteorShower" } do
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
	end,
})

---------------------------------------------------------------------------
-- Playtime gifts
---------------------------------------------------------------------------
add({
	Name = "gifts",
	MaxSeconds = 2 * 3600,
	Run = function(T, place)
		local game, me = T.Boot(place)
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
		T.Check(okMore == false, "no more gifts this session")
		T.Check(T.Engine.Now < 70 * 60 + 60, "all gifts within ~an hour")
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

return Scenarios
