--[[
	Mega Tycoon simulation engine (runs on Lune: https://lune-org.github.io)

	Loads the Rojo-built place file and runs the REAL game scripts against a
	simulated Roblox engine:

	  • Lune's roblox library provides the real datatypes (Vector3, CFrame...)
	    and Instance storage with Roblox's property validation (wrong property
	    names / types error exactly like in Roblox)
	  • every Instance the game sees is a Lua proxy, so this engine can add
	    Roblox behaviour Lune doesn't have: events, Destroy() + locked Parent,
	    Position <-> CFrame, attribute change signals, WaitForChild, remotes...
	  • a virtual clock + task scheduler: hours of gameplay run in seconds
	  • server and client run in one DataModel as two "contexts" linked by
	    the remotes, like a Studio play-test
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local RInstance = roblox.Instance
local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local Enum = roblox.Enum
local nativeTypeof = typeof

local Engine = {}
Engine.Now = 0
Engine.EpochBase = 1_760_000_000
Engine.Context = "server"
Engine.Errors = {}
Engine.Warnings = {}
Engine.Logs = {}
Engine.Kicks = {}
Engine.Studio = true
Engine.LocalPlayer = nil
Engine.Verbose = false
Engine.DataStoreFail = false
Engine.AutoBuy = false
Engine.Stats = { FireClient = 0, FireServer = 0, Invokes = 0, Tweens = 0, Steps = 0, Instances = 0 }

---------------------------------------------------------------------------
-- proxies
---------------------------------------------------------------------------
local proxies: { [string]: any } = {} -- debug id -> proxy
local natives = setmetatable({}, { __mode = "k" }) -- proxy -> native instance
local ProxyMeta = {}

local function wrap(value)
	if nativeTypeof(value) == "Instance" then
		local id = value:GetDebugId()
		local proxy = proxies[id]
		if not proxy then
			proxy = setmetatable({}, ProxyMeta)
			natives[proxy] = value
			proxies[id] = proxy
		end
		return proxy
	end
	return value
end

local function unwrap(value)
	if type(value) == "table" then
		local native = natives[value]
		if native then
			return native
		end
	end
	return value
end

local function isInstance(value): boolean
	return type(value) == "table" and natives[value] ~= nil
end

local function typeofValue(value): string
	if isInstance(value) then
		return "Instance"
	end
	return nativeTypeof(value)
end

local function idOf(proxyOrNative): string
	return unwrap(proxyOrNative):GetDebugId()
end

Engine.Wrap = wrap
Engine.Unwrap = unwrap
Engine.IsInstance = isInstance
Engine.Typeof = typeofValue
Engine.IdOf = idOf

local function wrapResults(...)
	local n = select("#", ...)
	if n == 1 then
		local v = ...
		if type(v) == "table" and getmetatable(v) == nil and #v > 0 and nativeTypeof(v[1]) == "Instance" then
			local list = table.create(#v)
			for i, item in v do
				list[i] = wrap(item)
			end
			return list
		end
		return wrap(v)
	end
	local out = table.pack(...)
	for i = 1, out.n do
		out[i] = wrap(out[i])
	end
	return table.unpack(out, 1, out.n)
end

local function unwrapArgs(...)
	local n = select("#", ...)
	if n == 0 then
		return
	end
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = unwrap(args[i])
	end
	return table.unpack(args, 1, args.n)
end

local function deepCopy(value, seen)
	if type(value) ~= "table" or isInstance(value) then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for k, v in value do
		copy[deepCopy(k, seen)] = deepCopy(v, seen)
	end
	return copy
end
Engine.DeepCopy = deepCopy

local function packCopy(...)
	local args = table.pack(...)
	for i = 1, args.n do
		args[i] = deepCopy(args[i])
	end
	return args
end

---------------------------------------------------------------------------
-- scheduler
---------------------------------------------------------------------------
local threadCtx = setmetatable({}, { __mode = "k" })
local sleeping = {}
local deferred = {}
local cancelled = setmetatable({}, { __mode = "k" })
local waiters = {}

local function record(kind: string, ctx: string, message: string, trace: string?)
	local entry = { Kind = kind, Context = ctx, Message = message, Trace = trace, Time = Engine.Now }
	if kind == "error" then
		table.insert(Engine.Errors, entry)
		if Engine.Verbose then
			print(("[%s ERROR t=%.1f] %s\n%s"):format(ctx, Engine.Now, message, trace or ""))
		end
	else
		table.insert(Engine.Warnings, entry)
		if Engine.Verbose then
			print(("[%s WARN t=%.1f] %s"):format(ctx, Engine.Now, message))
		end
	end
end
Engine.Record = record

local function resume(thread: thread, ...)
	if cancelled[thread] or coroutine.status(thread) ~= "suspended" then
		return true
	end
	local previous = Engine.Context
	Engine.Context = threadCtx[thread] or previous
	local ok, err = coroutine.resume(thread, ...)
	Engine.Context = previous
	if not ok then
		record("error", threadCtx[thread] or "?", tostring(err), debug.traceback(thread))
	end
	return ok
end
Engine.Resume = resume

local function newThread(fn, ctx: string?)
	local thread = coroutine.create(fn)
	threadCtx[thread] = ctx or Engine.Context
	return thread
end

local function spawnIn(ctx: string, fn, ...)
	local thread = type(fn) == "thread" and fn or newThread(fn, ctx)
	threadCtx[thread] = threadCtx[thread] or ctx
	resume(thread, ...)
	return thread
end
Engine.SpawnIn = spawnIn

-- any yieldable coroutine may wait (e.g. one made with coroutine.wrap); it
-- inherits the current context. Only Lune's main thread can't.
local function isSimThread(thread): boolean
	if threadCtx[thread] ~= nil then
		return true
	end
	if coroutine.isyieldable() then
		threadCtx[thread] = Engine.Context
		return true
	end
	return false
end

local taskLib = {}
function taskLib.spawn(fn, ...)
	assert(type(fn) == "function" or type(fn) == "thread", "task.spawn expects a function or thread")
	return spawnIn(Engine.Context, fn, ...)
end
function taskLib.defer(fn, ...)
	assert(type(fn) == "function" or type(fn) == "thread", "task.defer expects a function or thread")
	local thread = type(fn) == "thread" and fn or newThread(fn)
	table.insert(deferred, { Thread = thread, Args = table.pack(...) })
	return thread
end
function taskLib.delay(t, fn, ...)
	assert(type(fn) == "function" or type(fn) == "thread", "task.delay expects a function or thread")
	local thread = type(fn) == "thread" and fn or newThread(fn)
	table.insert(sleeping, { Thread = thread, Wake = Engine.Now + (tonumber(t) or 0), Args = table.pack(...) })
	return thread
end
function taskLib.wait(t)
	local thread = coroutine.running()
	if not isSimThread(thread) then
		error("task.wait called outside a simulated thread")
	end
	local start = Engine.Now
	table.insert(sleeping, { Thread = thread, Wake = Engine.Now + math.max(tonumber(t) or 0, 0), Args = table.pack() })
	coroutine.yield()
	return Engine.Now - start
end
function taskLib.cancel(thread)
	cancelled[thread] = true
end
function taskLib.synchronize() end
function taskLib.desynchronize() end
Engine.Task = taskLib

---------------------------------------------------------------------------
-- signals
---------------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection
function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self.Signal.Connections
	local index = table.find(list, self)
	if index then
		table.remove(list, index)
	end
end

function Signal.new(name: string?)
	return setmetatable({ Name = name or "Signal", Connections = {}, Waiting = {} }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Attempt to connect failed: Passed value is not a function")
	local conn = setmetatable({ Connected = true, Fn = fn, Ctx = Engine.Context, Signal = self }, Connection)
	table.insert(self.Connections, conn)
	-- remote events that arrived with nobody listening are delivered now (Roblox queues them)
	local queued = self.Queued
	if queued and #queued > 0 then
		self.Queued = {}
		for _, args in queued do
			spawnIn(conn.Ctx, conn.Fn, table.unpack(args, 1, args.n))
		end
	end
	return conn
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Wait()
	local thread = coroutine.running()
	assert(isSimThread(thread), "Signal:Wait called outside a simulated thread")
	table.insert(self.Waiting, thread)
	return coroutine.yield()
end

-- Roblox doesn't promise an order for event handlers: SIM_SIGNAL_ORDER=reverse
-- runs them last-connected-first to shake out order-dependent bugs
Engine.SignalOrder = "forward"
function Signal:Fire(...)
	local n = select("#", ...)
	local args = table.pack(...)
	for i = 1, n do
		args[i] = wrap(args[i])
	end
	local list = table.clone(self.Connections)
	if Engine.SignalOrder == "reverse" then
		for i = 1, #list // 2 do
			list[i], list[#list - i + 1] = list[#list - i + 1], list[i]
		end
	end
	if self.Queued and #list == 0 and #self.Waiting == 0 then
		if #self.Queued >= 256 then
			record("warning", Engine.Context, "Remote event invocation queue exhausted for " .. self.Name .. "; did you forget to implement OnClientEvent?")
		else
			table.insert(self.Queued, args)
		end
		return
	end
	for _, conn in list do
		if conn.Connected then
			spawnIn(conn.Ctx, conn.Fn, table.unpack(args, 1, n))
		end
	end
	local waiting = self.Waiting
	self.Waiting = {}
	for _, thread in waiting do
		resume(thread, table.unpack(args, 1, n))
	end
end

function Signal:DisconnectAll()
	for _, conn in table.clone(self.Connections) do
		conn:Disconnect()
	end
	self.Waiting = {}
end

Engine.Signal = Signal

local instanceSignals: { [string]: { [string]: any } } = {}
local function signalFor(inst, name: string)
	local id = idOf(inst)
	local bucket = instanceSignals[id]
	if not bucket then
		bucket = {}
		instanceSignals[id] = bucket
	end
	local sig = bucket[name]
	if not sig then
		sig = Signal.new(name)
		bucket[name] = sig
	end
	return sig
end
Engine.SignalFor = signalFor

local function hasSignal(inst, name: string): boolean
	local bucket = instanceSignals[idOf(inst)]
	return bucket ~= nil and bucket[name] ~= nil and #bucket[name].Connections + #bucket[name].Waiting > 0
end

local function fireIfExists(inst, name: string, ...)
	local bucket = instanceSignals[idOf(inst)]
	local sig = bucket and bucket[name]
	if sig then
		sig:Fire(...)
	end
end
Engine.FireIfExists = fireIfExists

---------------------------------------------------------------------------
-- custom members (by class, resolved through IsA)
---------------------------------------------------------------------------
local customProps: { [string]: { [string]: { Get: any, Set: any } } } = {}
local customMethods: { [string]: { [string]: any } } = {}

local function prop(className: string, name: string, getter, setter)
	customProps[className] = customProps[className] or {}
	customProps[className][name] = { Get = getter, Set = setter }
end

local function method(className: string, name: string, fn)
	customMethods[className] = customMethods[className] or {}
	customMethods[className][name] = fn
end
Engine.Prop = prop
Engine.Method = method

local reflection = roblox.getReflectionDatabase()
local superclassCache: { [string]: string | false } = {}
local function superclassOf(className: string): string?
	local cached = superclassCache[className]
	if cached == nil then
		local class = reflection:GetClass(className)
		cached = (class and class.Superclass) or false
		superclassCache[className] = cached
	end
	return cached or nil
end

-- the most specific class wins (CollectionService:AddTag beats Instance:AddTag)
local resolveCache: { [string]: { [string]: any } } = {}
local function resolve(native, key: string)
	local className = native.ClassName
	local cache = resolveCache[className]
	if not cache then
		cache = {}
		resolveCache[className] = cache
	end
	local entry = cache[key]
	if entry == nil then
		entry = false
		local cls: string? = className
		while cls do
			local methods = customMethods[cls]
			if methods and methods[key] then
				entry = { Kind = "method", Fn = methods[key] }
				break
			end
			local props = customProps[cls]
			if props and props[key] then
				entry = { Kind = "prop", Prop = props[key] }
				break
			end
			cls = superclassOf(cls)
		end
		cache[key] = entry
	end
	return entry
end

-- properties Lune can't read on fresh instances ("missing default value" /
-- "malformed property info"): the value a fresh Roblox instance would have
local DEFAULTS: { [string]: { [string]: any } } = {
	Humanoid = { PlatformStand = false, Sit = false, FloorMaterial = Enum.Material.Plastic, Jump = false },
	Player = {
		AccountAge = 365,
		MembershipType = Enum.MembershipType.None,
		Neutral = true,
		TeamColor = roblox.BrickColor.new("White"),
		CameraMaxZoomDistance = 128,
		CameraMinZoomDistance = 0.5,
		DevEnableMouseLock = true,
		HealthDisplayDistance = 100,
		NameDisplayDistance = 100,
		AutoJumpEnabled = true,
		CanLoadCharacterAppearance = true,
		CharacterAppearanceId = 0,
		FollowUserId = 0,
		LocaleId = "en-us",
		GameplayPaused = false,
	},
}
local ZERO_BY_TYPE = {
	Bool = false,
	Float32 = 0,
	Float64 = 0,
	Int32 = 0,
	Int64 = 0,
	String = "",
	Content = "",
	Vector3 = Vector3.new(0, 0, 0),
	Vector2 = Vector2.new(0, 0),
	CFrame = CFrame.new(),
	Color3 = roblox.Color3.new(1, 1, 1),
}
local function fallbackDefault(native, key: string, err: string)
	local cls: string? = native.ClassName
	while cls do
		local defaults = DEFAULTS[cls]
		if defaults and defaults[key] ~= nil then
			return defaults[key]
		end
		local class = reflection:GetClass(cls)
		local property = class and class.Properties[key]
		if property then
			local zero = ZERO_BY_TYPE[property.Datatype]
			if zero ~= nil then
				return zero
			end
			break
		end
		cls = superclassOf(cls)
	end
	error(err, 0)
end

local function readNative(native, key: string)
	local ok, value = pcall(function()
		return native[key]
	end)
	if ok then
		return value
	end
	local message = tostring(value)
	if message:find("missing default value", 1, true) or message:find("malformed property info", 1, true) then
		return fallbackDefault(native, key, message)
	end
	error(message:gsub("^runtime error: ", ""):match("^[^\n]*"), 3)
end

local nativeMethodCache: { [string]: any } = {}
local destroyed: { [string]: boolean } = {}
Engine.Destroyed = destroyed

ProxyMeta.__index = function(proxy, key)
	local native = natives[proxy]
	local entry = resolve(native, key)
	if entry then
		if entry.Kind == "method" then
			return entry.Fn
		end
		if entry.Prop.Get then
			return entry.Prop.Get(proxy, native)
		end
	end
	local value = readNative(native, key)
	if type(value) == "function" then
		local cached = nativeMethodCache[key]
		if not cached then
			cached = function(self, ...)
				local n = natives[self]
				if not n then
					error("Expected ':' not '.' calling member function " .. tostring(key), 2)
				end
				return wrapResults(n[key](n, unwrapArgs(...)))
			end
			nativeMethodCache[key] = cached
		end
		return cached
	end
	return wrap(value)
end

ProxyMeta.__newindex = function(proxy, key, value)
	local native = natives[proxy]
	local entry = resolve(native, key)
	if entry and entry.Kind == "prop" then
		if entry.Prop.Set then
			entry.Prop.Set(proxy, native, value)
			return
		end
		error(tostring(key) .. " is read-only", 2)
	end
	-- Changed / GetPropertyChangedSignal only cost something when listened to
	local bucket = instanceSignals[native:GetDebugId()]
	if bucket and (bucket["Prop:" .. key] or bucket.Changed) then
		local ok, old = pcall(readNative, native, key)
		native[key] = unwrap(value)
		if not ok or old ~= unwrap(value) then
			if bucket["Prop:" .. key] then
				bucket["Prop:" .. key]:Fire()
			end
			if bucket.Changed then
				bucket.Changed:Fire(key)
			end
		end
		return
	end
	native[key] = unwrap(value)
end

ProxyMeta.__tostring = function(proxy)
	return natives[proxy].Name
end

---------------------------------------------------------------------------
-- events & callbacks
---------------------------------------------------------------------------
local EVENTS = {
	Instance = { "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "Destroying", "AttributeChanged", "Changed" },
	BasePart = { "Touched", "TouchEnded" },
	Humanoid = { "Died", "HealthChanged", "StateChanged", "Running", "Jumping" },
	Player = { "CharacterAdded", "CharacterRemoving", "Chatted" },
	Players = { "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	BindableEvent = { "Event" },
	GuiButton = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click" },
	GuiObject = { "MouseEnter", "MouseLeave", "InputBegan", "InputEnded", "InputChanged" },
	TextBox = { "FocusLost", "Focused" },
	ProximityPrompt = { "Triggered", "TriggerEnded", "PromptShown", "PromptHidden" },
	Sound = { "Ended", "Loaded", "Played" },
	RunService = { "Heartbeat", "RenderStepped", "Stepped", "PreSimulation", "PostSimulation" },
	UserInputService = { "InputBegan", "InputEnded", "InputChanged", "TouchStarted", "LastInputTypeChanged" },
	TextChatService = { "SendingMessage", "MessageReceived" },
	MarketplaceService = { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "PromptPurchaseFinished" },
	DataModel = { "Loaded" },
}
for className, names in EVENTS do
	for _, name in names do
		local queues = className == "RemoteEvent"
		prop(className, name, function(proxy)
			local sig = signalFor(proxy, name)
			if queues and not sig.Queued then
				sig.Queued = {}
			end
			return sig
		end)
	end
end

local callbacks: { [string]: any } = {}
local CALLBACKS = {
	RemoteFunction = { "OnServerInvoke", "OnClientInvoke" },
	BindableFunction = { "OnInvoke" },
	MarketplaceService = { "ProcessReceipt" },
	TextChatService = { "OnIncomingMessage" },
}
for className, names in CALLBACKS do
	for _, name in names do
		prop(className, name, function(proxy)
			return callbacks[idOf(proxy) .. "." .. name]
		end, function(proxy, _, value)
			assert(value == nil or type(value) == "function", name .. " must be a function")
			callbacks[idOf(proxy) .. "." .. name] = value
		end)
	end
end

function Engine.Callback(inst, name: string)
	return callbacks[idOf(inst) .. "." .. name]
end

---------------------------------------------------------------------------
-- Instance basics
---------------------------------------------------------------------------
local function fireAncestry(child, newParent)
	-- ChildAdded / DescendantAdded only if someone listens (cheap). Like
	-- Roblox, DescendantAdded fires for the child AND everything inside it.
	if newParent then
		fireIfExists(newParent, "ChildAdded", child)
		local ancestor = newParent
		local subtree
		while ancestor do
			if hasSignal(ancestor, "DescendantAdded") then
				if not subtree then
					subtree = unwrap(child):GetDescendants()
				end
				fireIfExists(ancestor, "DescendantAdded", child)
				for _, d in subtree do
					fireIfExists(ancestor, "DescendantAdded", d)
				end
			end
			ancestor = ancestor.Parent
		end
	end
end

prop("Instance", "Parent", function(proxy, native)
	return wrap(native.Parent)
end, function(proxy, native, value)
	local id = native:GetDebugId()
	if destroyed[id] then
		error(("The Parent property of %s is locked, current parent: NULL, new parent %s"):format(native.Name, value and tostring(value) or "NULL"), 3)
	end
	local newParent = unwrap(value)
	if newParent ~= nil and nativeTypeof(newParent) ~= "Instance" then
		error("Parent must be an Instance (got " .. typeofValue(value) .. ")", 3)
	end
	local old = native.Parent
	native.Parent = newParent
	if old ~= newParent then
		if old then
			fireIfExists(old, "ChildRemoved", proxy)
		end
		fireIfExists(proxy, "AncestryChanged", proxy, value)
		fireAncestry(proxy, value)
	end
end)

-- like Roblox: Destroy() fires Destroying, disconnects everything, locks the
-- Parent and destroys every child too (so their Parent becomes nil as well)
local function simDestroy(proxy)
	local native = unwrap(proxy)
	local id = native:GetDebugId()
	if destroyed[id] then
		return
	end
	fireIfExists(native, "Destroying")
	destroyed[id] = true
	local bucket = instanceSignals[id]
	if bucket then
		for _, sig in bucket do
			sig:DisconnectAll()
		end
	end
	for _, child in native:GetChildren() do
		simDestroy(child)
	end
	native.Parent = nil
end
Engine.Destroy = simDestroy

method("Instance", "Destroy", function(self)
	simDestroy(self)
end)
method("Instance", "Remove", function(self)
	simDestroy(self)
end)
method("Instance", "ClearAllChildren", function(self)
	for _, child in unwrap(self):GetChildren() do
		simDestroy(child)
	end
end)

method("Instance", "WaitForChild", function(self, name: string, timeout: number?)
	assert(type(name) == "string", "WaitForChild expects a string")
	local native = unwrap(self)
	local child = native:FindFirstChild(name)
	if child then
		return wrap(child)
	end
	local thread = coroutine.running()
	if not isSimThread(thread) then
		error("WaitForChild called outside a simulated thread")
	end
	table.insert(waiters, { Instance = native, Name = name, Thread = thread, Deadline = timeout and (Engine.Now + timeout) or nil, Start = Engine.Now, Warned = false })
	return coroutine.yield()
end)

-- Lune keeps attribute numbers as float32 (os.time() would lose up to 64 s); Roblox keeps
-- doubles, so the exact numbers are remembered here
local exactAttributes = setmetatable({}, { __mode = "k" })
method("Instance", "GetAttribute", function(self, name: string)
	local native = unwrap(self)
	local exact = exactAttributes[native]
	local value = exact and exact[name]
	if value ~= nil and native:GetAttribute(name) ~= nil then
		return value
	end
	return native:GetAttribute(name)
end)

method("Instance", "SetAttribute", function(self, name: string, value)
	assert(type(name) == "string", "SetAttribute expects a string name")
	local native = unwrap(self)
	if isInstance(value) then
		error("Instances can't be stored as attributes", 2)
	end
	local exact = exactAttributes[native]
	local old = exact and exact[name]
	if old == nil then
		old = native:GetAttribute(name)
	end
	native:SetAttribute(name, value)
	if type(value) == "number" then
		if not exact then
			exact = {}
			exactAttributes[native] = exact
		end
		exact[name] = value
	elseif exact then
		exact[name] = nil
	end
	if old ~= value then
		fireIfExists(native, "Attr:" .. name)
		fireIfExists(native, "AttributeChanged", name)
	end
end)

method("Instance", "GetAttributeChangedSignal", function(self, name: string)
	assert(type(name) == "string", "GetAttributeChangedSignal expects a string")
	return signalFor(self, "Attr:" .. name)
end)

method("Instance", "GetPropertyChangedSignal", function(self, name: string)
	local _ = self[name] -- validates the property like Roblox does
	return signalFor(self, "Prop:" .. name)
end)

method("Instance", "IsDestroyed", function(self)
	return destroyed[idOf(self)] == true
end)

-- CollectionService index
local tagIndex: { [string]: { [string]: any } } = {}
local tagReported: { [string]: { [string]: boolean } } = {}
local tagAdded: { [string]: any } = {}
local tagRemoved: { [string]: any } = {}
local dataModel

local function inGame(native): boolean
	return dataModel ~= nil and native:IsDescendantOf(dataModel)
end

local function addTag(proxy, tag: string)
	assert(type(tag) == "string", "tag must be a string")
	local native = unwrap(proxy)
	native:AddTag(tag)
	tagIndex[tag] = tagIndex[tag] or {}
	tagIndex[tag][native:GetDebugId()] = native
end

local function removeTag(proxy, tag: string)
	local native = unwrap(proxy)
	native:RemoveTag(tag)
	local id = native:GetDebugId()
	local index = tagIndex[tag]
	if index and index[id] then
		index[id] = nil
		if tagReported[tag] and tagReported[tag][id] then
			tagReported[tag][id] = nil
			if tagRemoved[tag] then
				tagRemoved[tag]:Fire(native)
			end
		end
	end
end

method("Instance", "AddTag", function(self, tag)
	addTag(self, tag)
end)
method("Instance", "RemoveTag", function(self, tag)
	removeTag(self, tag)
end)
method("Instance", "Clone", function(self)
	local copy = unwrap(self):Clone()
	if copy == nil then
		return nil -- Archivable = false
	end
	local all = copy:GetDescendants()
	table.insert(all, 1, copy)
	for _, d in all do
		for _, tag in d:GetTags() do
			tagIndex[tag] = tagIndex[tag] or {}
			tagIndex[tag][d:GetDebugId()] = d
		end
	end
	return wrap(copy)
end)

local function sweepTags()
	for tag, index in tagIndex do
		tagReported[tag] = tagReported[tag] or {}
		local reported = tagReported[tag]
		for id, native in index do
			local alive = not destroyed[id] and inGame(native)
			if alive and not reported[id] then
				reported[id] = true
				if tagAdded[tag] then
					tagAdded[tag]:Fire(native)
				end
			elseif not alive and reported[id] then
				reported[id] = nil
				if tagRemoved[tag] then
					tagRemoved[tag]:Fire(native)
				end
			end
			if destroyed[id] and not reported[id] then
				index[id] = nil
			end
		end
	end
end

method("CollectionService", "GetTagged", function(_, tag: string)
	local list = {}
	for id, native in tagIndex[tag] or {} do
		if not destroyed[id] and inGame(native) then
			table.insert(list, wrap(native))
		end
	end
	return list
end)
method("CollectionService", "AddTag", function(_, inst, tag)
	addTag(inst, tag)
end)
method("CollectionService", "RemoveTag", function(_, inst, tag)
	removeTag(inst, tag)
end)
method("CollectionService", "HasTag", function(_, inst, tag)
	return unwrap(inst):HasTag(tag)
end)
method("CollectionService", "GetTags", function(_, inst)
	return unwrap(inst):GetTags()
end)
method("CollectionService", "GetInstanceAddedSignal", function(_, tag: string)
	tagAdded[tag] = tagAdded[tag] or Signal.new("TagAdded:" .. tag)
	return tagAdded[tag]
end)
method("CollectionService", "GetInstanceRemovedSignal", function(_, tag: string)
	tagRemoved[tag] = tagRemoved[tag] or Signal.new("TagRemoved:" .. tag)
	return tagRemoved[tag]
end)

---------------------------------------------------------------------------
-- geometry
---------------------------------------------------------------------------
prop("BasePart", "Position", function(_, native)
	return native.CFrame.Position
end, function(_, native, value)
	assert(nativeTypeof(value) == "Vector3", "Unable to assign property Position. Vector3 expected, got " .. typeofValue(value))
	native.CFrame = CFrame.new(value) * native.CFrame.Rotation
end)
prop("BasePart", "Orientation", function(_, native)
	local rx, ry, rz = native.CFrame:ToOrientation()
	return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end, function(_, native, value)
	native.CFrame = CFrame.new(native.CFrame.Position) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
end)
local velocities: { [string]: any } = {}
for _, name in { "AssemblyLinearVelocity", "AssemblyAngularVelocity", "Velocity", "RotVelocity" } do
	prop("BasePart", name, function(_, native)
		return velocities[native:GetDebugId() .. name] or Vector3.new(0, 0, 0)
	end, function(_, native, value)
		assert(nativeTypeof(value) == "Vector3", "Unable to assign property " .. name .. ". Vector3 expected")
		velocities[native:GetDebugId() .. name] = value
	end)
end
prop("Attachment", "WorldPosition", function(_, native)
	local parent = native.Parent
	if parent and parent:IsA("BasePart") then
		return (parent.CFrame * native.CFrame).Position
	end
	return native.CFrame.Position
end)
prop("Attachment", "WorldCFrame", function(_, native)
	local parent = native.Parent
	if parent and parent:IsA("BasePart") then
		return parent.CFrame * native.CFrame
	end
	return native.CFrame
end)

local function modelPivot(native)
	local primary = native.PrimaryPart
	if primary then
		return primary.CFrame
	end
	for _, d in native:GetDescendants() do
		if d:IsA("BasePart") then
			return d.CFrame
		end
	end
	return CFrame.new()
end

method("PVInstance", "GetPivot", function(self)
	local native = unwrap(self)
	if native:IsA("BasePart") then
		return native.CFrame
	end
	return modelPivot(native)
end)

method("PVInstance", "PivotTo", function(self, cf)
	assert(nativeTypeof(cf) == "CFrame", "PivotTo expects a CFrame")
	local native = unwrap(self)
	if native:IsA("BasePart") then
		native.CFrame = cf
		return
	end
	local delta = cf * modelPivot(native):Inverse()
	for _, d in native:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
end)

method("Model", "ScaleTo", function(self, scale: number)
	assert(type(scale) == "number" and scale > 0, "ScaleTo expects a positive number")
	unwrap(self):SetAttribute("SimScale", scale)
end)
method("Model", "GetScale", function(self)
	return unwrap(self):GetAttribute("SimScale") or 1
end)
method("Model", "GetBoundingBox", function(self)
	return modelPivot(unwrap(self)), Vector3.new(4, 4, 4)
end)
method("BasePart", "SetNetworkOwner", function(_, owner)
	assert(owner == nil or (isInstance(owner) and unwrap(owner):IsA("Player")), "SetNetworkOwner expects a Player or nil")
end)
method("BasePart", "GetNetworkOwner", function()
	return nil
end)
method("BasePart", "ApplyImpulse", function() end)
method("BasePart", "GetMass", function(self)
	local s = unwrap(self).Size
	return s.X * s.Y * s.Z * 0.7
end)

---------------------------------------------------------------------------
-- Humanoid
---------------------------------------------------------------------------
local healths: { [string]: number } = {}
local deadHumanoids: { [string]: boolean } = {}

local function setHealth(proxy, native, value)
	assert(type(value) == "number", "Unable to assign property Health. Number expected")
	local id = native:GetDebugId()
	local maxHealth = native.MaxHealth
	if value ~= math.huge and maxHealth ~= math.huge then
		value = math.clamp(value, 0, maxHealth)
	end
	if value ~= value then
		value = 0
	end
	healths[id] = value
	fireIfExists(native, "HealthChanged", value)
	if value <= 0 and not deadHumanoids[id] then
		deadHumanoids[id] = true
		fireIfExists(native, "Died")
		Engine.OnHumanoidDied(proxy)
	end
end

prop("Humanoid", "Health", function(_, native)
	return healths[native:GetDebugId()] or native.MaxHealth
end, setHealth)
method("Humanoid", "TakeDamage", function(self, amount: number)
	assert(type(amount) == "number", "TakeDamage expects a number")
	local native = unwrap(self)
	local character = native.Parent
	if character and character:FindFirstChildOfClass("ForceField") then
		return
	end
	setHealth(self, native, self.Health - amount)
end)
method("Humanoid", "ChangeState", function(_, state)
	assert(nativeTypeof(state) == "EnumItem", "ChangeState expects an EnumItem")
end)
method("Humanoid", "Move", function() end)
method("Humanoid", "GetState", function()
	return Enum.HumanoidStateType.Running
end)
prop("Humanoid", "MoveDirection", function()
	return Vector3.new(0, 0, 0)
end)
prop("Humanoid", "RootPart", function(_, native)
	local character = native.Parent
	return character and wrap(character:FindFirstChild("HumanoidRootPart"))
end)

---------------------------------------------------------------------------
-- GUI / sound / particles defaults
---------------------------------------------------------------------------
prop("GuiBase2d", "AbsoluteSize", function(_, native)
	if native:IsA("LayerCollector") then
		return Vector2.new(1280, 720)
	end
	return Vector2.new(120, 40)
end)
prop("GuiBase2d", "AbsolutePosition", function()
	return Vector2.new(0, 0)
end)
prop("GuiBase2d", "AbsoluteRotation", function()
	return 0
end)
for _, cls in { "TextLabel", "TextButton", "TextBox" } do
	prop(cls, "TextBounds", function()
		return Vector2.new(60, 20)
	end)
	prop(cls, "TextFits", function()
		return true
	end)
end
local soundState: { [string]: { [string]: any } } = {}
local function soundField(native, key, default)
	local s = soundState[native:GetDebugId()]
	if s and s[key] ~= nil then
		return s[key]
	end
	return default
end
prop("Sound", "IsLoaded", function(_, native)
	return soundField(native, "IsLoaded", false)
end)
prop("Sound", "IsPlaying", function(_, native)
	return soundField(native, "IsPlaying", false)
end)
prop("Sound", "TimeLength", function(_, native)
	return soundField(native, "TimeLength", 0)
end)
prop("Sound", "TimePosition", function(_, native)
	return soundField(native, "TimePosition", 0)
end, function(_, native, value)
	soundState[native:GetDebugId()] = soundState[native:GetDebugId()] or {}
	soundState[native:GetDebugId()].TimePosition = value
end)
local function setSound(native, key, value)
	soundState[native:GetDebugId()] = soundState[native:GetDebugId()] or {}
	soundState[native:GetDebugId()][key] = value
end
method("Sound", "Play", function(self)
	setSound(unwrap(self), "IsPlaying", true)
	fireIfExists(self, "Played")
end)
method("Sound", "Stop", function(self)
	setSound(unwrap(self), "IsPlaying", false)
end)
method("Sound", "Pause", function(self)
	setSound(unwrap(self), "IsPlaying", false)
end)
method("Sound", "Resume", function(self)
	setSound(unwrap(self), "IsPlaying", true)
end)
method("ParticleEmitter", "Emit", function(_, n)
	assert(n == nil or type(n) == "number", "Emit expects a number")
end)
method("ParticleEmitter", "Clear", function() end)
method("TextBox", "CaptureFocus", function() end)
method("TextBox", "ReleaseFocus", function() end)
method("TextBox", "IsFocused", function()
	return false
end)

---------------------------------------------------------------------------
-- world services
---------------------------------------------------------------------------
Engine.TerrainOps = 0
local function checkArgs(label: string, types: { string }, ...)
	local args = table.pack(...)
	for i, expected in types do
		local actual = typeofValue(args[i])
		if expected ~= actual and not (expected == "number" and type(args[i]) == "number") then
			error(("%s argument %d: %s expected, got %s"):format(label, i, expected, actual), 3)
		end
	end
end
method("Terrain", "Clear", function()
	Engine.TerrainOps += 1
end)
method("Terrain", "FillBlock", function(_, ...)
	Engine.TerrainOps += 1
	checkArgs("FillBlock", { "CFrame", "Vector3", "EnumItem" }, ...)
end)
method("Terrain", "FillBall", function(_, ...)
	Engine.TerrainOps += 1
	checkArgs("FillBall", { "Vector3", "number", "EnumItem" }, ...)
end)
method("Terrain", "FillCylinder", function(_, ...)
	Engine.TerrainOps += 1
	checkArgs("FillCylinder", { "CFrame", "number", "number", "EnumItem" }, ...)
end)
method("Terrain", "FillWedge", function(_, ...)
	Engine.TerrainOps += 1
	checkArgs("FillWedge", { "CFrame", "Vector3", "EnumItem" }, ...)
end)

method("Workspace", "GetServerTimeNow", function()
	return Engine.EpochBase + Engine.Now
end)

method("WorldRoot", "Raycast", function(_, origin, direction, params)
	checkArgs("Raycast", { "Vector3", "Vector3" }, origin, direction)
	if direction.Y >= 0 then
		return nil
	end
	local t = -origin.Y / direction.Y
	if t < 0 or t > 1 then
		return nil
	end
	local position = origin + direction * t
	return { Position = position, Normal = Vector3.new(0, 1, 0), Distance = (direction * t).Magnitude, Material = Enum.Material.Grass, Instance = dataModel and wrap(dataModel:GetService("Workspace").Terrain) }
end)

local closeCallbacks = {}
Engine.CloseCallbacks = closeCallbacks
method("DataModel", "BindToClose", function(_, fn)
	assert(type(fn) == "function", "BindToClose expects a function")
	table.insert(closeCallbacks, { Fn = fn, Ctx = Engine.Context })
end)
method("DataModel", "IsLoaded", function()
	return true
end)
prop("DataModel", "CreatorId", function()
	return Engine.CreatorId or 0
end)
prop("DataModel", "CreatorType", function()
	return Enum.CreatorType.User
end)
prop("DataModel", "PlaceId", function()
	return 1
end)
prop("DataModel", "JobId", function()
	return "sim-job"
end)

method("RunService", "IsStudio", function()
	return Engine.Studio
end)
method("RunService", "IsServer", function()
	return Engine.Context == "server"
end)
method("RunService", "IsClient", function()
	return Engine.Context == "client"
end)
method("RunService", "IsRunning", function()
	return true
end)
method("RunService", "IsRunMode", function()
	return false
end)
local renderBindings = {}
method("RunService", "BindToRenderStep", function(_, name: string, priority: number, fn)
	assert(type(name) == "string" and type(priority) == "number" and type(fn) == "function", "BindToRenderStep(string, number, function)")
	renderBindings[name] = { Fn = fn, Priority = priority, Ctx = Engine.Context }
end)
method("RunService", "UnbindFromRenderStep", function(_, name: string)
	renderBindings[name] = nil
end)

---------------------------------------------------------------------------
-- players
---------------------------------------------------------------------------
local function playerList()
	local list = {}
	for _, child in dataModel:GetService("Players"):GetChildren() do
		if child:IsA("Player") then
			table.insert(list, wrap(child))
		end
	end
	return list
end

prop("Players", "LocalPlayer", function()
	if Engine.Context == "client" then
		return Engine.LocalPlayer
	end
	return nil
end)
method("Players", "GetPlayers", function()
	return playerList()
end)
method("Players", "GetPlayerByUserId", function(_, userId)
	for _, p in playerList() do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end)
method("Players", "GetPlayerFromCharacter", function(_, character)
	if character == nil then
		return nil
	end
	for _, p in playerList() do
		if p.Character == character then
			return p
		end
	end
	return nil
end)
method("Players", "GetNameFromUserIdAsync", function(self, userId)
	assert(type(userId) == "number", "GetNameFromUserIdAsync expects a number")
	local p = self:GetPlayerByUserId(userId)
	return p and p.Name or ("User" .. userId)
end)
local knownUsers: { [string]: number } = {} -- every player that ever joined
method("Players", "GetUserIdFromNameAsync", function(_, name)
	assert(type(name) == "string", "GetUserIdFromNameAsync expects a string")
	if knownUsers[name:lower()] then
		return knownUsers[name:lower()]
	end
	if name:lower():find("nobody") then
		error("HTTP 400 (Bad Request)")
	end
	return 900000 + #name
end)
method("Players", "BanAsync", function() end)

method("Player", "Kick", function(self, message)
	table.insert(Engine.Kicks, { Player = self.Name, Message = tostring(message) })
	taskLib.defer(function()
		Engine.RemovePlayer(self)
	end)
end)
method("Player", "LoadCharacter", function(self)
	Engine.SpawnCharacter(self)
end)
method("Player", "RequestStreamAroundAsync", function(_, position, timeout)
	assert(nativeTypeof(position) == "Vector3", "RequestStreamAroundAsync expects a Vector3")
end)
method("Player", "GetRankInGroup", function(_, groupId)
	assert(type(groupId) == "number", "GetRankInGroup expects a number")
	return 0
end)
method("Player", "IsInGroup", function()
	return false
end)
-- friendships for tests: Engine.Friends[userId] = { [otherUserId] = true }
Engine.Friends = {}
method("Player", "IsFriendsWith", function(self, userId)
	assert(type(userId) == "number", "IsFriendsWith expects a number")
	local mine = Engine.Friends[self.UserId]
	local theirs = Engine.Friends[userId]
	return (mine ~= nil and mine[userId] == true) or (theirs ~= nil and theirs[self.UserId] == true)
end)
local memberships: { [string]: any } = {}
prop("Player", "MembershipType", function(_, native)
	return memberships[native:GetDebugId()] or Enum.MembershipType.None
end, function(_, native, value)
	assert(nativeTypeof(value) == "EnumItem", "MembershipType must be an EnumItem")
	memberships[native:GetDebugId()] = value
end)

---------------------------------------------------------------------------
-- remotes
---------------------------------------------------------------------------
local function assertPlayer(value, label)
	if not (isInstance(value) and unwrap(value):IsA("Player")) then
		error(label .. ": argument 1 must be a Player (got " .. typeofValue(value) .. ")", 3)
	end
end

-- a remote's event signal (queues events while nobody listens, like Roblox)
local function remoteSignal(remote, name: string)
	local sig = signalFor(remote, name)
	if not sig.Queued then
		sig.Queued = {}
	end
	return sig
end

-- everything the server sent to each player (for checks)
Engine.Outbox = {} :: { [string]: { { Remote: string, Args: any } } }
local function postToOutbox(player, remoteName: string, args)
	local list = Engine.Outbox[player.Name]
	if not list then
		list = {}
		Engine.Outbox[player.Name] = list
	end
	table.insert(list, { Remote = remoteName, Args = args, Time = Engine.Now })
	if #list > 400 then
		table.remove(list, 1)
	end
end

-- remote arguments must be serializable like in Roblox (no functions, no
-- mixed/sparse tables, no metatables) or they silently arrive broken
local function checkRemoteArgs(label: string, args)
	local function check(value, path: string, depth: number)
		local kind = typeofValue(value)
		if kind == "function" or kind == "thread" then
			error(("%s: can't send a %s over a remote (%s)"):format(label, kind, path), 4)
		elseif kind == "table" then
			assert(depth < 30, label .. ": table nested too deep")
			if getmetatable(value) ~= nil then
				error(("%s: tables with metatables lose them over a remote (%s)"):format(label, path), 4)
			end
			local hasString, numeric = false, 0
			for k in value do
				if type(k) == "string" then
					hasString = true
				elseif type(k) == "number" then
					numeric += 1
				else
					error(("%s: table keys must be strings or numbers (%s)"):format(label, path), 4)
				end
			end
			if hasString and numeric > 0 then
				error(("%s: mixed array/dictionary table at %s (the array part is dropped)"):format(label, path), 4)
			end
			if numeric > 0 and numeric ~= #value then
				error(("%s: sparse array at %s (values after the first nil are dropped)"):format(label, path), 4)
			end
			for k, v in value do
				check(v, path .. "." .. tostring(k), depth + 1)
			end
		end
	end
	for i = 1, args.n do
		check(args[i], "arg " .. i, 0)
	end
end

local function fireServerAs(remote, player, ...)
	Engine.Stats.FireServer += 1
	local args = packCopy(...)
	checkRemoteArgs("FireServer(" .. remote.Name .. ")", args)
	remoteSignal(remote, "OnServerEvent"):Fire(player, table.unpack(args, 1, args.n))
end

local function invokeServerAs(remote, player, ...)
	Engine.Stats.Invokes += 1
	local cb = callbacks[idOf(remote) .. ".OnServerInvoke"]
	if not cb then
		error("RemoteFunction " .. remote.Name .. " has no OnServerInvoke (the call would yield forever)")
	end
	local caller = coroutine.running()
	assert(isSimThread(caller), "InvokeServer called outside a simulated thread")
	local results, done, callerWaiting = nil, false, false
	local args = packCopy(...)
	checkRemoteArgs("InvokeServer(" .. remote.Name .. ")", args)
	spawnIn("server", function()
		results = table.pack(xpcall(cb, debug.traceback, player, table.unpack(args, 1, args.n)))
		done = true
		if callerWaiting then
			resume(caller)
		end
	end)
	if not done then
		callerWaiting = true
		coroutine.yield()
	end
	if not results[1] then
		record("error", "server", "OnServerInvoke(" .. remote.Name .. ") errored: " .. tostring(results[2]))
		error(results[2], 0)
	end
	local out = table.pack(table.unpack(results, 2, results.n))
	checkRemoteArgs("OnServerInvoke(" .. remote.Name .. ") result", out)
	for i = 1, out.n do
		out[i] = deepCopy(out[i])
	end
	return table.unpack(out, 1, out.n)
end
Engine.FireServerAs = function(player, remote, ...)
	return fireServerAs(remote, player, ...)
end
Engine.InvokeServerAs = function(player, remote, ...)
	return invokeServerAs(remote, player, ...)
end

method("RemoteEvent", "FireServer", function(self, ...)
	assert(Engine.Context == "client", "FireServer can only be called from the client")
	fireServerAs(self, Engine.LocalPlayer, ...)
end)
method("RemoteEvent", "FireClient", function(self, player, ...)
	assert(Engine.Context == "server", "FireClient can only be called from the server")
	assertPlayer(player, "FireClient")
	Engine.Stats.FireClient += 1
	local args = packCopy(...)
	checkRemoteArgs("FireClient(" .. self.Name .. ")", args)
	postToOutbox(player, self.Name, args)
	if player == Engine.LocalPlayer then
		remoteSignal(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
	end
end)
method("RemoteEvent", "FireAllClients", function(self, ...)
	assert(Engine.Context == "server", "FireAllClients can only be called from the server")
	Engine.Stats.FireClient += 1
	local args = packCopy(...)
	checkRemoteArgs("FireAllClients(" .. self.Name .. ")", args)
	for _, player in playerList() do
		postToOutbox(player, self.Name, args)
		if player == Engine.LocalPlayer then
			remoteSignal(self, "OnClientEvent"):Fire(table.unpack(args, 1, args.n))
		end
	end
end)
method("RemoteFunction", "InvokeServer", function(self, ...)
	assert(Engine.Context == "client", "InvokeServer can only be called from the client")
	return invokeServerAs(self, Engine.LocalPlayer, ...)
end)

---------------------------------------------------------------------------
-- tweens
---------------------------------------------------------------------------
local Tween = {}
Tween.__index = Tween
function Tween:Play()
	if self.Playing then
		return
	end
	self.Playing = true
	self.PlaybackState = Enum.PlaybackState.Playing
	local info = self.Info
	if info.RepeatCount < 0 then
		return -- infinite tweens never complete
	end
	local total = (info.Time * (info.Reverses and 2 or 1)) * (info.RepeatCount + 1) + info.DelayTime
	taskLib.delay(total, function()
		if self.Cancelled then
			return
		end
		if not destroyed[idOf(self.Instance)] and not info.Reverses then
			for property, value in self.Goals do
				self.Instance[property] = value
			end
		end
		self.PlaybackState = Enum.PlaybackState.Completed
		self.Completed:Fire(Enum.PlaybackState.Completed)
	end)
end
function Tween:Cancel()
	self.Cancelled = true
	self.PlaybackState = Enum.PlaybackState.Cancelled
end
function Tween:Pause()
	self.Cancelled = true
end
function Tween:Destroy()
	self.Cancelled = true
end

local TWEENABLE = { number = true, Vector3 = true, Vector2 = true, CFrame = true, Color3 = true, UDim = true, UDim2 = true, Rect = true }
method("TweenService", "Create", function(_, inst, info, goals)
	assert(isInstance(inst), "TweenService:Create argument 1 must be an Instance")
	assert(type(info) == "table" and info.IsTweenInfo, "TweenService:Create argument 2 must be a TweenInfo")
	assert(type(goals) == "table", "TweenService:Create argument 3 must be a table")
	for property, value in goals do
		local current = inst[property] -- errors for invalid properties
		local kind = typeofValue(value)
		if not TWEENABLE[kind] then
			error(("TweenService:Create property %s of type %s can't be tweened"):format(property, kind))
		end
		if typeofValue(current) ~= kind then
			error(("TweenService:Create property %s is a %s, got %s"):format(property, typeofValue(current), kind))
		end
	end
	Engine.Stats.Tweens += 1
	return setmetatable({ Instance = inst, Info = info, Goals = goals, Completed = Signal.new("TweenCompleted"), PlaybackState = Enum.PlaybackState.Begin }, Tween)
end)

---------------------------------------------------------------------------
-- data stores, marketplace and other platform services
---------------------------------------------------------------------------
Engine.DataStores = {}
Engine.OrderedStores = {}
local function storeGuard()
	if Engine.DataStoreFail then
		error("502: API Services rejected request with error. HTTP 403 (Forbidden) - StudioAccessToApisNotAllowed")
	end
end
local function checkStorable(value, path: string)
	local kind = typeofValue(value)
	if kind == "table" then
		for k, v in value do
			if type(k) ~= "string" and type(k) ~= "number" then
				error("DataStore: invalid key type at " .. path)
			end
			checkStorable(v, path .. "." .. tostring(k))
		end
	elseif kind ~= "string" and kind ~= "number" and kind ~= "boolean" and kind ~= "nil" then
		error("DataStore: can't store " .. kind .. " at " .. path)
	end
	if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then
		error("DataStore: can't store NaN/inf at " .. path)
	end
end
Engine.CheckStorable = checkStorable

local function makeStore(name: string)
	local data = Engine.DataStores[name] or {}
	Engine.DataStores[name] = data
	local store = {}
	function store:GetAsync(key)
		storeGuard()
		assert(type(key) == "string", "DataStore key must be a string")
		return deepCopy(data[key])
	end
	function store:SetAsync(key, value)
		storeGuard()
		assert(type(key) == "string", "DataStore key must be a string")
		checkStorable(value, key)
		data[key] = deepCopy(value)
	end
	function store:UpdateAsync(key, fn)
		storeGuard()
		local new = fn(deepCopy(data[key]))
		if new ~= nil then
			checkStorable(new, key)
			data[key] = deepCopy(new)
		end
		return deepCopy(new)
	end
	function store:RemoveAsync(key)
		storeGuard()
		local old = data[key]
		data[key] = nil
		return old
	end
	function store:IncrementAsync(key, delta)
		storeGuard()
		data[key] = (data[key] or 0) + (delta or 1)
		return data[key]
	end
	return store
end
method("DataStoreService", "GetDataStore", function(_, name: string)
	assert(type(name) == "string", "GetDataStore expects a string")
	storeGuard()
	return makeStore(name)
end)
method("DataStoreService", "GetOrderedDataStore", function(_, name: string)
	assert(type(name) == "string", "GetOrderedDataStore expects a string")
	storeGuard()
	local data = Engine.OrderedStores[name] or {}
	Engine.OrderedStores[name] = data
	local store = {}
	function store:SetAsync(key, value)
		storeGuard()
		assert(type(key) == "string", "OrderedDataStore key must be a string")
		assert(type(value) == "number" and value == math.floor(value), "OrderedDataStore values must be integers (got " .. tostring(value) .. ")")
		assert(math.abs(value) < 2 ^ 63, "OrderedDataStore value too large")
		data[key] = value
	end
	function store:GetAsync(key)
		storeGuard()
		return data[key]
	end
	function store:GetSortedAsync(ascending: boolean, pageSize: number)
		storeGuard()
		assert(type(pageSize) == "number" and pageSize <= 100, "pageSize must be <= 100")
		local rows = {}
		for key, value in data do
			table.insert(rows, { key = key, value = value })
		end
		table.sort(rows, function(a, b)
			if ascending then
				return a.value < b.value
			end
			return a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(pageSize, #rows) do
			page[i] = rows[i]
		end
		return {
			IsFinished = true,
			GetCurrentPage = function()
				return page
			end,
			AdvanceToNextPageAsync = function() end,
		}
	end
	return store
end)

Engine.OwnedPasses = {}
Engine.Prompts = {}
Engine.Receipts = {}
method("MarketplaceService", "UserOwnsGamePassAsync", function(_, userId, passId)
	assert(type(userId) == "number" and type(passId) == "number", "UserOwnsGamePassAsync(number, number)")
	return Engine.OwnedPasses[userId] ~= nil and Engine.OwnedPasses[userId][passId] == true
end)
method("MarketplaceService", "GetProductInfo", function(_, id, infoType)
	assert(type(id) == "number", "GetProductInfo expects a number")
	return { Name = "Product " .. id, PriceInRobux = 99, IsForSale = true }
end)
method("MarketplaceService", "PromptGamePassPurchase", function(self, player, passId)
	assertPlayer(player, "PromptGamePassPurchase")
	assert(type(passId) == "number" and passId > 0, "PromptGamePassPurchase: invalid pass id")
	table.insert(Engine.Prompts, { Kind = "Pass", Player = player.Name, Id = passId })
	if Engine.AutoBuy then
		Engine.OwnedPasses[player.UserId] = Engine.OwnedPasses[player.UserId] or {}
		Engine.OwnedPasses[player.UserId][passId] = true
		signalFor(self, "PromptGamePassPurchaseFinished"):Fire(player, passId, true)
	end
end)
method("MarketplaceService", "PromptProductPurchase", function(self, player, productId)
	assertPlayer(player, "PromptProductPurchase")
	assert(type(productId) == "number" and productId > 0, "PromptProductPurchase: invalid product id")
	table.insert(Engine.Prompts, { Kind = "Product", Player = player.Name, Id = productId })
	if Engine.AutoBuy then
		local cb = callbacks[idOf(self) .. ".ProcessReceipt"]
		if cb then
			local receipt = { PlayerId = player.UserId, ProductId = productId, PurchaseId = "receipt-" .. (#Engine.Receipts + 1), CurrencySpent = 99, PlaceIdWherePurchased = 1 }
			spawnIn("server", function()
				local decision = cb(receipt)
				table.insert(Engine.Receipts, { Receipt = receipt, Decision = decision })
			end)
		end
	end
end)

method("BadgeService", "AwardBadge", function(_, userId, badgeId)
	assert(type(userId) == "number" and type(badgeId) == "number", "AwardBadge(number, number)")
	return true
end)
method("BadgeService", "UserHasBadgeAsync", function()
	return false
end)

method("TextService", "FilterStringAsync", function(_, text, userId)
	assert(type(text) == "string" and type(userId) == "number", "FilterStringAsync(string, number)")
	return {
		GetNonChatStringForBroadcastAsync = function()
			return text
		end,
		GetNonChatStringForUserAsync = function()
			return text
		end,
		GetChatForUserAsync = function()
			return text
		end,
	}
end)

method("PhysicsService", "RegisterCollisionGroup", function(_, name)
	assert(type(name) == "string", "RegisterCollisionGroup expects a string")
end)
method("PhysicsService", "CollisionGroupSetCollidable", function(_, a, b, c)
	assert(type(a) == "string" and type(b) == "string" and type(c) == "boolean", "CollisionGroupSetCollidable(string, string, boolean)")
end)

method("Debris", "AddItem", function(_, inst, lifetime)
	assert(isInstance(inst), "Debris:AddItem expects an Instance")
	taskLib.delay(lifetime or 10, function()
		simDestroy(inst)
	end)
end)

method("SoundService", "PlayLocalSound", function(_, sound)
	assert(isInstance(sound) and unwrap(sound):IsA("Sound"), "PlayLocalSound expects a Sound")
end)
method("ContentProvider", "PreloadAsync", function(_, list)
	assert(type(list) == "table", "PreloadAsync expects a table")
end)
method("StarterGui", "SetCoreGuiEnabled", function(_, coreType, enabled)
	assert(nativeTypeof(coreType) == "EnumItem" and type(enabled) == "boolean", "SetCoreGuiEnabled(CoreGuiType, boolean)")
end)
method("StarterGui", "SetCore", function() end)
method("ReplicatedFirst", "RemoveDefaultLoadingScreen", function() end)
method("UserInputService", "IsKeyDown", function(_, key)
	assert(nativeTypeof(key) == "EnumItem", "IsKeyDown expects a KeyCode")
	return false
end)
method("UserInputService", "GetFocusedTextBox", function()
	return nil
end)
for _, name in { "TouchEnabled", "KeyboardEnabled", "MouseEnabled", "GamepadEnabled" } do
	prop("UserInputService", name, function()
		return name == "KeyboardEnabled" or name == "MouseEnabled"
	end)
end

---------------------------------------------------------------------------
-- datatypes Lune doesn't have
---------------------------------------------------------------------------
local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	assert(time == nil or type(time) == "number", "TweenInfo.new: time must be a number")
	return {
		IsTweenInfo = true,
		Time = time or 1,
		EasingStyle = style or Enum.EasingStyle.Quad,
		EasingDirection = direction or Enum.EasingDirection.Out,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}
end

local RandomClass = {}
RandomClass.__index = RandomClass
local randomSeed = 12345
function RandomClass.new(seed)
	if seed == nil then
		randomSeed += 7919
		seed = randomSeed
	end
	local s = math.floor(tonumber(seed) :: number) % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return setmetatable({ State = s }, RandomClass)
end
function RandomClass:_next(): number
	self.State = (self.State * 48271) % 2147483647
	return self.State / 2147483647
end
function RandomClass:NextNumber(min, max)
	min, max = min or 0, max or 1
	return min + (max - min) * self:_next()
end
function RandomClass:NextInteger(min, max)
	assert(type(min) == "number" and type(max) == "number", "NextInteger(number, number)")
	if max < min then
		error("NextInteger: max must be >= min")
	end
	return math.floor(min + (max - min + 1) * self:_next())
end
function RandomClass:NextUnitVector()
	return Vector3.new(self:NextNumber(-1, 1), self:NextNumber(-1, 1), self:NextNumber(-1, 1)).Unit
end
function RandomClass:Clone()
	return setmetatable({ State = self.State }, RandomClass)
end

local RaycastParams = {}
function RaycastParams.new()
	return { FilterType = Enum.RaycastFilterType.Exclude, FilterDescendantsInstances = {}, IgnoreWater = false, CollisionGroup = "Default" }
end

-- Lune 0.8.9's CFrame.lookAt points the wrong way along -Z; this one is correct
local function lookAt(at, target, up)
	up = up or Vector3.new(0, 1, 0)
	local look = target - at
	if look.Magnitude < 1e-6 then
		return CFrame.new(at)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.new(0, 0, 1))
		if right.Magnitude < 1e-6 then
			right = Vector3.new(1, 0, 0)
		end
	end
	right = right.Unit
	local up2 = right:Cross(look).Unit
	local back = -look
	return CFrame.new(at.X, at.Y, at.Z, right.X, up2.X, back.X, right.Y, up2.Y, back.Y, right.Z, up2.Z, back.Z)
end
local CFrameLib = setmetatable({ lookAt = lookAt }, { __index = CFrame })
Engine.CFrame = CFrameLib

local InstanceLib = {}
local clientCreated = setmetatable({}, { __mode = "k" })
function InstanceLib.new(className: string, parent)
	assert(type(className) == "string", "Instance.new expects a class name")
	local native = RInstance.new(className)
	Engine.Stats.Instances += 1
	local proxy = wrap(native)
	if Engine.Context == "client" then
		clientCreated[proxy] = true
	end
	if className == "Humanoid" then
		native.MaxHealth = 100
		native.WalkSpeed = 16
		native.JumpPower = 50
		native.UseJumpPower = true
		native.PlatformStand = false
	end
	if parent ~= nil then
		proxy.Parent = parent
	end
	return proxy
end
Engine.Instance = InstanceLib

---------------------------------------------------------------------------
-- loading game scripts
---------------------------------------------------------------------------
local moduleCache = { server = {}, client = {} }
local LOADING = {}
local baseEnv

local function makeEnv(scriptProxy)
	-- Lune copies the environment's raw fields (metatables are ignored)
	local env = {}
	for k, v in baseEnv do
		env[k] = v
	end
	env.script = scriptProxy
	env.require = function(target)
		return Engine.Require(target)
	end
	return env
end

local function loadChunk(scriptProxy)
	local native = unwrap(scriptProxy)
	return luau.load(native.Source, { debugName = native:GetFullName(), environment = makeEnv(scriptProxy) })
end

local loadingThread: { [string]: thread } = {}
function Engine.Require(target)
	if not isInstance(target) or not unwrap(target):IsA("ModuleScript") then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local ctx = Engine.Context
	local cache = moduleCache[ctx]
	local id = idOf(target)
	local key = ctx .. ":" .. id
	local cached = cache[id]
	if cached == LOADING then
		if loadingThread[key] == coroutine.running() then
			error("Requested module was required recursively: " .. unwrap(target):GetFullName())
		end
		-- another thread is still running this module: wait for it, like Roblox
		while cache[id] == LOADING do
			taskLib.wait(0)
		end
		if cache[id] == nil then
			error("Requested module experienced an error while loading: " .. unwrap(target):GetFullName())
		end
		return cache[id]
	elseif cached ~= nil then
		return cached
	end
	cache[id] = LOADING
	loadingThread[key] = coroutine.running()
	local fn = loadChunk(target)
	local results = table.pack(pcall(fn))
	loadingThread[key] = nil
	if not results[1] then
		cache[id] = nil
		error(results[2], 0)
	end
	if results.n ~= 2 or results[2] == nil then
		cache[id] = nil
		error("Module code did not return exactly one value: " .. unwrap(target):GetFullName())
	end
	cache[id] = results[2]
	return results[2]
end

function Engine.RunScript(scriptProxy, ctx: string)
	local fn = loadChunk(scriptProxy)
	return spawnIn(ctx, fn)
end

local function vclock()
	return Engine.Now
end
-- a client's os.time() is its device clock: tests can make it wrong
Engine.ClientClockSkew = 0
local function vtime()
	local skew = Engine.Context == "client" and Engine.ClientClockSkew or 0
	return math.floor(Engine.EpochBase + Engine.Now + skew)
end

local function joinArgs(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

local function makeBaseEnv()
	local workspaceProxy = wrap(dataModel:GetService("Workspace"))
	local osLib = {
		clock = vclock,
		time = function(t)
			if t then
				return os.time(t)
			end
			return vtime()
		end,
		date = os.date,
		difftime = os.difftime,
	}
	local env = {}
	-- Luau standard library + Lune globals
	for _, name in { "math", "string", "table", "coroutine", "utf8", "bit32", "buffer", "debug", "pcall", "xpcall", "error", "assert", "type", "tostring", "tonumber", "pairs", "ipairs", "next", "select", "rawget", "rawset", "rawequal", "rawlen", "setmetatable", "getmetatable", "unpack", "newproxy", "gcinfo", "collectgarbage", "_VERSION" } do
		env[name] = (_G :: any)[name]
	end
	env.pcall = pcall
	env.xpcall = xpcall
	env.error = error
	env.assert = assert
	-- Instances are userdata in Roblox (our proxies are tables)
	env.type = function(value)
		if isInstance(value) then
			return "userdata"
		end
		return type(value)
	end
	env.tostring = tostring
	env.tonumber = tonumber
	env.pairs = pairs
	env.ipairs = ipairs
	env.next = next
	env.select = select
	env.rawget = rawget
	env.rawset = rawset
	env.rawequal = rawequal
	env.setmetatable = setmetatable
	env.getmetatable = getmetatable
	env.math = math
	env.string = string
	env.table = table
	env.coroutine = coroutine
	env.utf8 = utf8
	env.debug = debug
	env.bit32 = bit32
	env.typeof = typeofValue
	env.game = wrap(dataModel)
	env.workspace = workspaceProxy
	env.Workspace = workspaceProxy
	env.task = taskLib
	env.wait = taskLib.wait
	env.delay = taskLib.delay
	env.spawn = taskLib.spawn
	env.tick = function()
		return Engine.EpochBase + Engine.Now
	end
	env.time = vclock
	env.os = osLib
	env.Instance = InstanceLib
	env.Enum = Enum
	env.Vector3 = Vector3
	env.Vector2 = Vector2
	env.CFrame = CFrameLib
	env.Color3 = roblox.Color3
	env.UDim = roblox.UDim
	env.UDim2 = roblox.UDim2
	env.Rect = roblox.Rect
	env.NumberRange = roblox.NumberRange
	env.NumberSequence = roblox.NumberSequence
	env.NumberSequenceKeypoint = roblox.NumberSequenceKeypoint
	env.ColorSequence = roblox.ColorSequence
	env.ColorSequenceKeypoint = roblox.ColorSequenceKeypoint
	env.BrickColor = roblox.BrickColor
	env.Font = roblox.Font
	env.Ray = roblox.Ray
	env.Region3 = roblox.Region3
	env.PhysicalProperties = roblox.PhysicalProperties
	env.TweenInfo = TweenInfo
	env.Random = RandomClass
	env.RaycastParams = RaycastParams
	env.print = function(...)
		table.insert(Engine.Logs, { Context = Engine.Context, Message = joinArgs(...), Time = Engine.Now })
		if Engine.Verbose then
			print("[" .. Engine.Context .. "] " .. joinArgs(...))
		end
	end
	env.warn = function(...)
		record("warning", Engine.Context, joinArgs(...))
	end
	env.shared = {}
	env._G = {}
	return env
end

---------------------------------------------------------------------------
-- players & characters
---------------------------------------------------------------------------
local nextUserId = 1000

function Engine.SpawnCharacter(player)
	local old = player.Character
	if old then
		fireIfExists(player, "CharacterRemoving", old)
		simDestroy(old)
		-- like Roblox: on respawn, PlayerGui loses every ScreenGui/BillboardGui
		-- that still has ResetOnSpawn = true (the default!)
		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			for _, gui in unwrap(playerGui):GetChildren() do
				if gui:IsA("LayerCollector") and gui.ResetOnSpawn then
					record("warning", "client", "ResetOnSpawn: " .. gui.Name .. " was destroyed on respawn (set ResetOnSpawn = false)")
					simDestroy(gui)
				end
			end
		end
	end
	local model = InstanceLib.new("Model")
	model.Name = player.Name
	local root = InstanceLib.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.CFrame = CFrame.new(0, 3, 0)
	root.Parent = model
	for _, data in { { "Head", Vector3.new(2, 1, 1), 1.5 }, { "Torso", Vector3.new(2, 2, 1), 0 }, { "Left Leg", Vector3.new(1, 2, 1), -2 } } do
		local part = InstanceLib.new("Part")
		part.Name = data[1]
		part.Size = data[2]
		part.CFrame = CFrame.new(0, 3 + data[3], 0)
		part.Parent = model
	end
	local humanoid = InstanceLib.new("Humanoid")
	humanoid.Parent = model
	model.PrimaryPart = root
	model.Parent = wrap(dataModel:GetService("Workspace"))
	player.Character = model
	fireIfExists(player, "CharacterAdded", model)
	return model
end

function Engine.OnHumanoidDied(humanoid)
	local character = humanoid.Parent
	if not character then
		return
	end
	for _, player in playerList() do
		if player.Character == character then
			taskLib.delay(5, function()
				if player.Parent and player.Character == character then
					Engine.SpawnCharacter(player)
				end
			end)
		end
	end
end

function Engine.AddPlayer(name: string, opts)
	opts = opts or {}
	nextUserId += 1
	local player = InstanceLib.new("Player")
	player.Name = name
	player.DisplayName = opts.DisplayName or name
	player.UserId = opts.UserId or nextUserId
	knownUsers[name:lower()] = player.UserId
	local gui = InstanceLib.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = player
	if opts.Local then
		Engine.LocalPlayer = player
	end
	player.Parent = wrap(dataModel:GetService("Players"))
	signalFor(dataModel:GetService("Players"), "PlayerAdded"):Fire(player)
	if opts.Character ~= false then
		taskLib.delay(0.1, function()
			if player.Parent then
				Engine.SpawnCharacter(player)
			end
		end)
	end
	return player
end

function Engine.RemovePlayer(player)
	if not player.Parent then
		return
	end
	signalFor(dataModel:GetService("Players"), "PlayerRemoving"):Fire(player)
	if player.Character then
		simDestroy(player.Character)
	end
	player.Parent = nil
	if player == Engine.LocalPlayer then
		Engine.LocalPlayer = nil
	end
end

-- The local player's client shuts down (they left): every client connection,
-- thread, render binding, module and client-made instance goes away, like
-- closing the Roblox app. A new local player can then start a fresh client.
function Engine.ResetClient()
	local function dropClientConnections(sig)
		for _, conn in table.clone(sig.Connections) do
			if conn.Ctx == "client" then
				conn:Disconnect()
			end
		end
		local keep = {}
		for _, thread in sig.Waiting do
			if threadCtx[thread] ~= "client" then
				table.insert(keep, thread)
			end
		end
		sig.Waiting = keep
	end
	for _, bucket in instanceSignals do
		for _, sig in bucket do
			dropClientConnections(sig)
		end
	end
	for _, sig in tagAdded do
		dropClientConnections(sig)
	end
	for _, sig in tagRemoved do
		dropClientConnections(sig)
	end
	local function serverOnly(list)
		local keep = {}
		for _, entry in list do
			local thread = entry.Thread
			if threadCtx[thread] == "client" then
				cancelled[thread] = true
			else
				table.insert(keep, entry)
			end
		end
		return keep
	end
	sleeping = serverOnly(sleeping)
	deferred = serverOnly(deferred)
	waiters = serverOnly(waiters)
	for name, binding in renderBindings do
		if binding.Ctx == "client" then
			renderBindings[name] = nil
		end
	end
	for proxy in clientCreated do
		local native = natives[proxy]
		local parent = native and native.Parent
		if parent and not clientCreated[wrap(parent)] then
			simDestroy(proxy)
		end
	end
	table.clear(clientCreated)
	moduleCache.client = {}
	Engine.LocalPlayer = nil
end

---------------------------------------------------------------------------
-- interaction helpers for tests
---------------------------------------------------------------------------
-- the player walks onto `part` (their character moves there, then touches it)
function Engine.Touch(part, player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	assert(root, "player has no character to touch with")
	character:PivotTo(CFrame.new(part.Position + Vector3.new(0, 3, 0)))
	fireIfExists(part, "Touched", root)
end

-- an exploit-style touch: fired from wherever the character is
function Engine.RemoteTouch(part, player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	assert(root, "player has no character to touch with")
	fireIfExists(part, "Touched", root)
end

function Engine.TouchWith(part, hitPart)
	fireIfExists(part, "Touched", hitPart)
end

function Engine.Click(button)
	assert(button:IsA("GuiButton"), "Click expects a GuiButton")
	fireIfExists(button, "MouseButton1Down")
	fireIfExists(button, "MouseButton1Up")
	fireIfExists(button, "Activated")
	fireIfExists(button, "MouseButton1Click")
end

-- a key press on the local client (InputBegan / InputEnded with a fake InputObject)
function Engine.Input(keyCode, processed: boolean?)
	local uis = dataModel:GetService("UserInputService")
	local input = { KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard, UserInputState = Enum.UserInputState.Begin, Position = Vector3.new(0, 0, 0) }
	fireIfExists(uis, "InputBegan", input, processed == true)
	input.UserInputState = Enum.UserInputState.End
	fireIfExists(uis, "InputEnded", input, processed == true)
end

function Engine.TriggerPrompt(prompt, player)
	fireIfExists(prompt, "Triggered", player)
end

function Engine.Chat(player, message: string)
	fireIfExists(player, "Chatted", message)
end

function Engine.Close()
	for _, entry in closeCallbacks do
		spawnIn(entry.Ctx, entry.Fn)
	end
end

---------------------------------------------------------------------------
-- main loop
---------------------------------------------------------------------------
local function wakeSleepers()
	if #sleeping == 0 then
		return
	end
	local due, keep = {}, {}
	for _, entry in sleeping do
		if entry.Wake <= Engine.Now + 1e-9 then
			table.insert(due, entry)
		else
			table.insert(keep, entry)
		end
	end
	sleeping = keep
	table.sort(due, function(a, b)
		return a.Wake < b.Wake
	end)
	for _, entry in due do
		resume(entry.Thread, table.unpack(entry.Args, 1, entry.Args.n))
	end
end

local function runDeferred()
	local guard = 0
	while #deferred > 0 and guard < 1000 do
		guard += 1
		local list = deferred
		deferred = {}
		for _, entry in list do
			resume(entry.Thread, table.unpack(entry.Args, 1, entry.Args.n))
		end
	end
end

local function pollWaiters()
	if #waiters == 0 then
		return
	end
	local current = waiters
	waiters = {}
	for _, w in current do
		local child = w.Instance:FindFirstChild(w.Name)
		if child then
			resume(w.Thread, wrap(child))
		elseif w.Deadline and Engine.Now >= w.Deadline then
			resume(w.Thread, nil)
		else
			if not w.Deadline and not w.Warned and Engine.Now - w.Start > 10 then
				w.Warned = true
				record("warning", threadCtx[w.Thread] or "?", "Infinite yield possible on " .. w.Instance:GetFullName() .. ':WaitForChild("' .. w.Name .. '")')
			end
			table.insert(waiters, w)
		end
	end
end

local runService
function Engine.Step(dt: number)
	dt = dt or 1 / 30
	Engine.Now += dt
	Engine.Stats.Steps += 1
	signalFor(runService, "Stepped"):Fire(Engine.Now, dt)
	signalFor(runService, "Heartbeat"):Fire(dt)
	if Engine.LocalPlayer then
		local bindings = {}
		for _, binding in renderBindings do
			table.insert(bindings, binding)
		end
		table.sort(bindings, function(a, b)
			return a.Priority < b.Priority
		end)
		for _, binding in bindings do
			spawnIn(binding.Ctx, binding.Fn, dt)
		end
		signalFor(runService, "RenderStepped"):Fire(dt)
	end
	wakeSleepers()
	runDeferred()
	pollWaiters()
	if Engine.Stats.Steps % 3 == 0 then
		sweepTags()
	end
end

local prepared: { [string]: any } = {}
-- must run on the main thread (Lune file reads + deserializing are async)
function Engine.Prepare(placePath: string)
	prepared[placePath] = roblox.deserializePlace(fs.readFile(placePath))
end

function Engine.Load(placePath: string)
	dataModel = prepared[placePath]
	assert(dataModel, "call Engine.Prepare(path) on the main thread first")
	runService = dataModel:GetService("RunService")
	baseEnv = makeBaseEnv()
	local workspaceNative = dataModel:GetService("Workspace")
	local camera = workspaceNative.CurrentCamera or RInstance.new("Camera")
	camera.ViewportSize = Vector2.new(1280, 720)
	camera.FieldOfView = 70
	camera.CFrame = CFrame.new(0, 20, 30)
	camera.Parent = workspaceNative
	workspaceNative.CurrentCamera = camera
	Engine.Game = wrap(dataModel)
	return Engine.Game
end

function Engine.Service(name: string)
	return wrap(dataModel:GetService(name))
end

return Engine
