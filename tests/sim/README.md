# Headless gameplay tests

These tests **play the real game**: the built place file is loaded and the actual
server and client scripts run against a simulated Roblox engine on
[Lune](https://lune-org.github.io), with a virtual clock (hours of play take seconds).

```bash
rojo build -o MegaTycoon.rbxlx
lune run tests/sim/run.luau -- MegaTycoon.rbxlx              # every scenario
lune run tests/sim/run.luau -- MegaTycoon.rbxlx quests       # one scenario
lune run tests/sim/run.luau -- MegaTycoon.rbxlx quests --verbose
SIM_SIGNAL_ORDER=reverse SIM_SEED=7 lune run tests/sim/run.luau -- MegaTycoon.rbxlx
```

A scenario fails on any script error (server or client), failed check, or warning
that isn't in its `AllowedWarnings`. Each scenario runs in its own process.

| File | What it is |
|---|---|
| `Engine.luau` | The simulated engine: Instance proxies (events, `Destroy`, attributes, `WaitForChild`...), the task scheduler, remotes between the server and one local client, players + characters, DataStores, MarketplaceService, tweens, CollectionService, and test helpers (`Touch`, `Click`, `Input`...) |
| `Harness.luau` | What scenarios use (`T`): `Boot`, `Wait`, `WaitFor`, `Check`, `Client`/`Server` (run code in that context), `Service`/`Controller`/`Shared` (the game's own module tables), `Admin`, `Sent`/`Notices` (what the server sent a player), `FindButton`, `StartClient`/`LeaveClient` (rejoin) |
| `Scenarios.luau` | The scenarios |
| `run.luau` | The runner |

## Writing a scenario

```lua
add({
	Name = "my_feature",
	Run = function(T, place)
		local game, me = T.Boot(place)          -- server + a local client player
		local other = T.AddPlayer("Friend")     -- more players (server side only)
		T.Wait(6)                               -- let everything load
		local data = T.Service("DataService"):Get(me)
		T.Client(function()                     -- as the client: fire remotes, click UI
			T.Remote("BuyAll"):FireServer()
		end)
		T.Wait(1)
		T.Check(data.Cash >= 0, "cash stays valid")
		T.Engine.Touch(somePart, me)            -- walk onto a part
		T.Engine.FireServerAs(other, T.Remote("DuoLeave"))
	end,
})
```

Tips: `T.SetDt(1)` speeds up long waits; `T.Boot(place, { Setup = function(T) ... end })`
runs before any game script (e.g. to change Config); `T.Engine.Studio = false`
simulates a live server (no free Studio purchases, real admin ranks).
