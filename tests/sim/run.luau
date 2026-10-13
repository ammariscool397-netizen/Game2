--[[
	Runs the Mega Tycoon simulation tests.
	  lune run tests/sim/run.luau [place.rbxlx] [scenario] [--verbose]
	Without a scenario name, every scenario runs in its own process
	(slow ones like the 8-hour soak only with SIM_SLOW=1).
]]
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local args = process.args
local placePath = "MegaTycoon.rbxlx"
local only = nil
local verbose = false
for _, arg in args do
	if arg == "--verbose" then
		verbose = true
	elseif arg:match("%.rbxlx?$") then
		placePath = arg
	else
		only = arg
	end
end

local Scenarios = require("./Scenarios")

if not only then
	-- run each scenario in a fresh process so they can't affect each other
	local failed = 0
	local names = {}
	local includeSlow = process.env.SIM_SLOW == "1"
	for _, scenario in Scenarios do
		-- slow scenarios (e.g. the 8-hour soak) only run when asked for
		if not scenario.Slow or includeSlow then
			table.insert(names, scenario.Name)
		end
	end
	for _, name in names do
		-- this file's own path (Lune names chunks [string "path/without/ext"])
		local self = debug.info(1, "s"):match('^%[string "(.-)"%]$') or "tests/sim/run"
		local runArgs = { "run", self .. ".luau", "--", placePath, name }
		if verbose then
			table.insert(runArgs, "--verbose")
		end
		local result = process.spawn(process.args and "lune" or "lune", runArgs, { stdio = "inherit" })
		if not result.ok then
			failed += 1
		end
	end
	print(("\n%d/%d scenarios passed"):format(#names - failed, #names))
	process.exit(failed == 0 and 0 or 1)
end

local Harness = require("./Harness")
local Engine = Harness.Engine
Engine.Verbose = verbose
Engine.SignalOrder = process.env.SIM_SIGNAL_ORDER or "forward"
-- reproducible runs: the game's math.random shares this generator
local seed = tonumber(process.env.SIM_SEED) or 20261013
math.randomseed(seed)

local scenario
for _, s in Scenarios do
	if s.Name == only then
		scenario = s
	end
end
assert(scenario, "unknown scenario " .. tostring(only))

Engine.Prepare(placePath)
print("▶ " .. scenario.Name .. (seed ~= 20261013 and (" (seed " .. seed .. ")") or ""))
local startClock = os.clock()
local finished = false
local thread = coroutine.create(function()
	scenario.Run(Harness, placePath)
	finished = true
end)
Engine.SpawnIn("server", thread)
local limit = scenario.MaxSeconds or 600
while not finished and coroutine.status(thread) ~= "dead" and Engine.Now < limit and Engine.Game do
	Engine.Step(Harness.Dt)
end
if not finished then
	Harness.Check(false, "scenario did not finish (virtual time " .. math.floor(Engine.Now) .. "s)")
end

-- unexpected warnings count as failures too
local allowedWarnings = scenario.AllowedWarnings or {}
local badWarnings = {}
for _, w in Engine.Warnings do
	local allowed = false
	for _, pattern in allowedWarnings do
		if w.Message:find(pattern) then
			allowed = true
		end
	end
	if not allowed then
		table.insert(badWarnings, w)
	end
end

local errors = #Engine.Errors
for _, e in Engine.Errors do
	print(("    ✗ [%s t=%.1f] %s"):format(e.Context, e.Time, e.Message))
	if e.Trace then
		print("      " .. e.Trace:gsub("\n", "\n      "))
	end
end
for _, w in badWarnings do
	print(("    ⚠ [%s t=%.1f] %s"):format(w.Context, w.Time, w.Message))
end
local ok = errors == 0 and #Harness.Failures == 0 and #badWarnings == 0
print(("  %s %s — %d checks, %d failed, %d errors, %d warnings, %.0fs simulated in %.1fs"):format(
	ok and "✓" or "✗",
	scenario.Name,
	Harness.Checks,
	#Harness.Failures,
	errors,
	#badWarnings,
	Engine.Now,
	os.clock() - startClock
))
process.exit(ok and 0 or 1)
