--[[ Test helpers on top of the Engine: boot the game, run scenario steps ]]
local Engine = require("./Engine")

local Harness = {}
Harness.Engine = Engine
Harness.Failures = {}
Harness.Checks = 0
Harness.Dt = 0.1

function Harness.Check(condition: any, message: string)
	Harness.Checks += 1
	if not condition then
		table.insert(Harness.Failures, { Message = message, Time = Engine.Now })
		print("    ✗ " .. message)
	end
	return condition
end

function Harness.Wait(seconds: number)
	return Engine.Task.wait(seconds)
end

function Harness.SetDt(dt: number)
	Harness.Dt = dt
end

-- wait until fn() is truthy (or timeout)
function Harness.WaitFor(fn, timeout: number?, label: string?)
	local limit = Engine.Now + (timeout or 10)
	while Engine.Now < limit do
		local ok, value = pcall(fn)
		if ok and value then
			return value
		end
		Engine.Task.wait(0.1)
	end
	Harness.Check(false, "timed out waiting for " .. (label or "condition"))
	return nil
end

-- run fn inside a client-context thread and wait for it to finish
function Harness.Client(fn, timeout: number?)
	local done, result = false, nil
	Engine.SpawnIn("client", function()
		result = table.pack(fn())
		done = true
	end)
	local limit = Engine.Now + (timeout or 15)
	while not done and Engine.Now < limit do
		Engine.Task.wait(0.05)
	end
	Harness.Check(done, "client action timed out")
	if result then
		return table.unpack(result, 1, result.n)
	end
	return nil
end

function Harness.Server(fn, timeout: number?)
	local done, result = false, nil
	Engine.SpawnIn("server", function()
		result = table.pack(fn())
		done = true
	end)
	local limit = Engine.Now + (timeout or 15)
	while not done and Engine.Now < limit do
		Engine.Task.wait(0.05)
	end
	Harness.Check(done, "server action timed out")
	if result then
		return table.unpack(result, 1, result.n)
	end
	return nil
end

local game

-- server service module table (the same one the game uses)
function Harness.Service(name: string)
	local module = game:GetService("ServerScriptService"):FindFirstChild("Services"):FindFirstChild(name)
	assert(module, "no service " .. name)
	local previous = Engine.Context
	Engine.Context = "server"
	local result = Engine.Require(module)
	Engine.Context = previous
	return result
end

function Harness.Controller(name: string)
	local module = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Controllers"):FindFirstChild(name)
	assert(module, "no controller " .. name)
	local previous = Engine.Context
	Engine.Context = "client"
	local result = Engine.Require(module)
	Engine.Context = previous
	return result
end

function Harness.Shared(name: string, ctx: string?)
	local module = game:GetService("ReplicatedStorage"):FindFirstChild("Shared"):FindFirstChild(name)
	local previous = Engine.Context
	Engine.Context = ctx or "server"
	local result = Engine.Require(module)
	Engine.Context = previous
	return result
end

-- boot the server (and optionally a local client player)
function Harness.Boot(placePath: string, opts)
	opts = opts or {}
	game = Engine.Load(placePath)
	Harness.Game = game
	-- the anti-cheat only runs in scenarios that ask for it (opts.AntiCheat): other
	-- scenarios teleport characters around instantly, which it would rightly flag
	Harness.Shared("Config").AntiCheat.Enabled = opts.AntiCheat == true
	if opts.Setup then
		-- runs before any game script: tweak Config (server copy) etc.
		local previous = Engine.Context
		Engine.Context = "server"
		opts.Setup(Harness, game)
		Engine.Context = previous
	end
	local main = game:GetService("ServerScriptService"):FindFirstChild("Main")
	Engine.RunScript(main, "server")
	Harness.Wait(1)
	local player
	if opts.Client ~= false then
		player = Harness.StartClient(opts.Name or "Tester", { UserId = opts.UserId })
	end
	return game, player
end

-- a player joins on the local client: runs the loading screen + client scripts
function Harness.StartClient(name: string, opts)
	opts = opts or {}
	local player = Engine.AddPlayer(name, { Local = true, UserId = opts.UserId })
	Harness.Wait(0.2)
	local loading = game:GetService("ReplicatedFirst"):FindFirstChild("LoadingScreen")
	if loading then
		Engine.RunScript(loading, "client")
	end
	local client = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")
	Engine.RunScript(client, "client")
	return player
end

-- the local player leaves (their whole client shuts down)
function Harness.LeaveClient()
	local player = Engine.LocalPlayer
	assert(player, "no local player")
	Engine.RemovePlayer(player)
	Engine.ResetClient()
end

function Harness.AddPlayer(name: string, opts)
	return Engine.AddPlayer(name, opts or {})
end

function Harness.Remote(name: string)
	return game:GetService("ReplicatedStorage"):FindFirstChild("Remotes"):FindFirstChild(name)
end

-- run an admin command as `executor` (server side, like the chat / panel do)
function Harness.Admin(executor, text: string)
	return Harness.Server(function()
		return Harness.Service("AdminService"):Execute(executor, text)
	end)
end

-- every message the server sent `player` on a remote (newest last)
function Harness.Sent(player, remoteName: string, since: number?)
	local list = {}
	for _, entry in Engine.Outbox[player.Name] or {} do
		if entry.Remote == remoteName and entry.Time >= (since or 0) then
			table.insert(list, entry.Args)
		end
	end
	return list
end

-- toast texts the server sent `player`
function Harness.Notices(player, since: number?)
	local list = {}
	for _, args in Harness.Sent(player, "Notify", since) do
		table.insert(list, type(args[1]) == "table" and tostring(args[1].Text) or "")
	end
	return list
end

function Harness.Noticed(player, pattern: string, since: number?): boolean
	for _, text in Harness.Notices(player, since) do
		if text:find(pattern) then
			return true
		end
	end
	return false
end

function Harness.MoveTo(player, cframe)
	local character = player.Character
	assert(character, player.Name .. " has no character")
	character:PivotTo(cframe)
end

function Harness.Root(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

function Harness.Humanoid(player)
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end

-- warnings recorded so far whose text matches
function Harness.Warned(pattern: string): boolean
	for _, w in Engine.Warnings do
		if w.Message:find(pattern) then
			return true
		end
	end
	return false
end

-- every descendant of `root` that is a GuiButton
function Harness.Buttons(root)
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") then
			table.insert(list, d)
		end
	end
	return list
end

-- is a GUI object actually on screen? (it and every ancestor visible)
function Harness.IsShown(gui): boolean
	local node = gui
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

-- first on-screen button whose text matches
function Harness.FindButton(root, pattern: string)
	for _, b in Harness.Buttons(root) do
		if b:IsA("TextButton") and b.Text:find(pattern) and Harness.IsShown(b) then
			return b
		end
	end
	return nil
end

function Harness.FindText(root, pattern: string)
	for _, d in root:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text:find(pattern) then
			return d
		end
	end
	return nil
end

return Harness
