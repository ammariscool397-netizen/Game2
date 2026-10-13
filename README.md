# 💰 MEGA TYCOON — Roblox Tycoon Game

A complete, fully scripted Roblox tycoon. **Everything is built from code**:
the terrain, the map, the 8-floor towers, all 514 upgrades, the VFX and the UI
are generated at runtime, so the game works without any uploaded models or images.

## ▶️ Quick start (no tools needed)

1. Download **`MegaTycoon.rbxlx`** from this repo (or from the latest GitHub Actions run).
2. Open it in **Roblox Studio** (File → Open from File).
3. Press **Play**. The whole world builds itself.

> In Studio every player is an **Owner admin** and Robux purchases are
> **simulated for free**, so you can test everything. Try `;unlockfloor me 8`,
> `;nuke`, `;tornado`, `;ufo` and `;meteors`.
> To test duos: Studio → Test → Clients and Servers → 2 players.

## ✅ Before you publish

All settings live in `src/ReplicatedStorage/Shared/Config.luau`.

| What | Where in Config | Notes |
|---|---|---|
| **Server size** | Place settings | Set **Max Players = 8** (one tower per player; duos free up towers) |
| Game Pass IDs | `Config.GamePasses.*.Id` | Create passes on the Creator Dashboard (2x Cash, Auto Collect, Fast Droppers, VIP, Super Speed, Auto Builder). `0` = not configured |
| Developer Product IDs | `Config.Products.*.Id` | Cash packs, 2x boost, instant repair, launch nuke, meteor storm, cash rain |
| Admins | `Config.Admin.Admins` | `[UserId] = rank` (1 Mod, 2 Admin, 3 Head Admin, 4 Owner). The place creator is always Owner |
| Music | `Config.Music` | Replace the IDs with audio you're allowed to use. Broken IDs are skipped automatically |
| Siren | `Config.Sounds.Siren` | Optional air-raid siren audio id (empty = synthesized alarm) |
| Pace / economy | `Config.Tycoon`, `Config.Rebirth` | `PaceStartSeconds`/`PaceEndSeconds` rescale every price at once |
| Disasters | `Config.Disasters` | Frequency, weights, damage, wreck time |
| Secrets | `Config.Secrets` | Names, hints, optional `BadgeId` |
| Quests / gifts | `Config.Quests`, `Config.Gifts` | Quest types, targets and rewards; playtime gift times |
| Free bonuses | `Config.Bonuses` | Premium and friends-in-server income bonus |

Also: **Game Settings → Security → Enable Studio Access to API Services**
(needed for saving data / leaderboards in Studio).

## 🤖 Auto-publish to Roblox (GitHub → your game)

Every push to this repo runs `.github/workflows/publish-roblox.yml`: it builds the
place with Rojo and uploads it straight into your Roblox place with **Open Cloud**.

1. Publish the place once from Studio (**File → Publish to Roblox**) so the game exists.
2. **Creator Dashboard → Open Cloud → API Keys → Create API Key**
   - Access permissions: **universe-places** → **Write** → select your experience
   - IP restrictions: add `0.0.0.0/0` (GitHub's servers use changing IPs)
3. In this GitHub repo: **Settings → Secrets and variables → Actions**
   - *Secret* `ROBLOX_API_KEY` = the key (never paste it into a chat)
   - *Variable* `ROBLOX_UNIVERSE_ID` = your Universe ID (Creator Dashboard → your experience → ⋯ → Copy Universe ID)
   - *Variable* `ROBLOX_PLACE_ID` = the number in your place's URL

Every push first runs the **type checker** and the **gameplay simulation tests**
(see below); nothing is uploaded unless they all pass.
Pushes upload a **Saved** version (not live yet: open the place in Studio to see it).
Run the workflow manually (**Actions → Build & publish to Roblox → Run workflow → Published**)
to make it live for players. Until the secret is set, the workflow just builds the file.

**Want Claude to edit Studio directly?** Run Claude Code on your own computer (Claude
desktop app, or `claude remote-control` in this folder) and turn on Studio's built-in
MCP server (Studio → Assistant → ⋯ → MCP Servers → Quick connect → Claude Code).

### Working on the code with Rojo (optional)
```bash
aftman install          # or: rokit install  (installs Rojo 7.4.4 + Lune 0.8.9)
rojo serve              # then connect from the Rojo Studio plugin
rojo build -o MegaTycoon.rbxlx   # rebuild the place file
```

## 🎮 Features

**8-floor towers — 514 upgrades**
- 8 towers in a ring around the lobby, one per player (8-player servers)
- 8 themed floors: Starter Factory, Gold Mine, Jungle Greenhouse, Crystal Lab,
  Volcano Forge, Ice Palace, Cyber City, Galaxy Penthouse
- Each floor has **62 upgrades**: 10 droppers, 10 Mk II upgrades, 4 upgraders,
  8 generators, 2 conveyor upgrades, 3 floor boosters, 17 decorations, 6 wall sets,
  a floor special and a floor trophy. On top: 6 rooftop items (helipad, antenna,
  pool, mega billboard, fireworks launcher, golden crown). Plus 12 secret relics
- Prices are **auto-calibrated** so a full tower takes ~3 hours (less with rebirths/passes)
- Buy on the physical buttons **or** in the **🏗️ BUILD** menu (B key), with **⚡ BUY ALL**
- **Elevators** on every floor + **🛗 FLOORS** menu to jump between floors
- Vault pads on every floor (or skip them with Auto Collect), **offline earnings**
- Rebirths for a permanent multiplier, global leaderboard
- **Safe saving**: session-locked DataStore saves (hopping servers can't lose or
  duplicate progress), corrupted values are repaired, nothing invalid is ever saved

**🧭 Guide beam** — new players get a glowing beam to the cheapest button they can
afford (or to the vault when collecting would pay for it). Toggle in Settings.

**📜 Quests** — 3 quests at a time (buy upgrades, earn, collect, unlock the next floor,
find a secret, beat the obby, play a minigame, survive a disaster); rewards scale with
your income. Claim them from the tracker in the bottom-right corner. Saved.

**🎁 Playtime gifts** — 6 gifts unlock during your first hour in a server.

**⭐ Free bonuses** — +10% income for Roblox Premium, +10% per friend in the server.

**👥 Duo building** — invite anyone in the server; you build **one tower** together with
**one shared wallet** (saved to the owner). Game passes help the whole duo. Leave any
time and your own tower comes back exactly as you left it.

**💥 Disasters** (random every 5–8 min, or bought / admin-triggered)
- ☢️ **Nuke** — air-raid siren, 30 s countdown, a **green beam guides you to the nearest
  bunker**, missile, flash, mushroom cloud, shockwave, falling ash. Unsheltered players
  are vaporized and unshielded towers lose 25% of their upgrades for 3 minutes
- ☄️ **Meteor storm** — warning circles, fireballs, explosions; leaves **cash crystals**
- 🌪️ **Tornado** — sweeps across the map, flings players, wrecks what it touches
- 🛸 **UFO invasion** — tractor beams abduct players, UFOs drop **alien cash**
- 🛡️ **Nuke Shield Dome** (floor 2 special) protects your whole tower *and everyone inside it*.
  The public bunker and your own Panic Bunker (floor 1) keep you alive
- 🔧 Wrecked upgrades rebuild automatically (or instantly with the Instant Repair product)

**🕵️ 12 secrets** hidden around the big map (mountain summit, hidden cave, waterfall,
lake floor, island tree, giant tree house, cloud island via a secret launch pad,
graveyard, world's edge, obby ghost path, bunker stash, behind the leaderboard).
Each gives cash, **+5% income forever** and a glowing relic in your tower's front yard.

**🗺️ Big map** — terraced snowy mountain, lake with island & dock, east forest,
graveyard, waterfall cliff, ring road, day/night cycle, public nuke bunker.

**Robux shop (🛒 SHOP / G key)**
- Passes: 2x Cash, Auto Collect, Fast Droppers, VIP, Super Speed, **Auto Builder**
  (your tower buys its best affordable upgrade by itself)
- Products: 4 cash packs (paid in minutes of income), 2x Boost, Instant Repair,
  **Launch a Nuke**, **Meteor Storm**, Server Cash Rain
- Secure `ProcessReceipt` with purchase history (no double grants)

**Minigames** — Coin Rush, Falling Tiles, Meteor Dodge (every 2.5 min, press JOIN)
**Obby** — west road: jumps, kill bricks, spinners, trusses, checkpoints, finish reward
**Extras** — loading screen, music playlist, VFX everywhere, daily rewards, codes,
settings (music, SFX, low graphics), chat tags (`[Owner]` `[👑 VIP]` `[🕵️ Secret Master]` `[R5]`)

## 🛡️ Admin commands

Prefix is `;` — e.g. `;speed me 100`, `;givecash all 1m`, `;nuke`, `;unlockfloor me 8`.
Player selectors: `me`, `all`, `others`, `random`, `admins`, `nonadmins`,
partial names, or comma lists (`me,bob`). Amounts accept `10k`, `2.5m`, `1b`, `1t`.
Open the **Admin Panel** with the 🛡️ button or **F2**.

| Rank | Commands |
|---|---|
| **Mod (1)** | `cmds` `logs` `tp` `bring` `to` `home` `floor` `speed` `jump` `heal` `god` `ungod` `ff` `unff` `kill` `freeze` `thaw` `sparkles` `fire` `smoke` `unfx` `invisible` `visible` `respawn` `jail` `unjail` `fly` `unfly` `noclip` `clip` `view` `unview` `m` `h` |
| **Admin (2)** | `kick` `givecash` `takecash` `setcash` `giverebirth` `rebirth` `unlockall` `unlockfloor` `explode` `giant` `tiny` `normal` `confetti` `cashrain` `doublecash` `music` `stopmusic` `minigame` `time` `nuke` `meteors` `tornado` `ufo` `stopdisaster` `repair` `wreck` `givesecrets` `duo` `unduo` |
| **Head Admin (3)** | `ban` `unban` `resetdata` `resetsecrets` `givepass` `removepass` |
| **Owner (4)** | `admin` `unadmin` `shutdown` |

## 📁 Project structure

```
src/
  ReplicatedFirst/LoadingScreen.client.luau   loading screen
  ReplicatedStorage/Shared/
    Config.luau        ALL settings
    TycoonItems.luau   generates + prices all 514 upgrades, shared income math
    Remotes.luau       networking
    UIKit.luau         UI helper library
    Util.luau, Signal.luau
  ServerScriptService/
    Main.server.luau   boots every service
    Services/
      DataService          saving / loading / duo wallets / offline earnings
      TycoonService        towers, buttons, income, elevators, wreck + repair
      TycoonBuilder        procedural models for every item
      DuoService           duo invites
      QuestService         quests (3 at a time, saved)
      GiftService          playtime gifts
      DisasterService      nuke / meteors / tornado / UFO
      SecretService        12 map secrets
      MonetizationService  passes, products, receipts
      AdminService         admin commands + bans
      MinigameService      Coin Rush / Falling Tiles / Meteor Dodge
      ObbyService          obby + secret ghost path
      RewardService        daily rewards, codes, settings
      LeaderboardService   global leaderboard
      WorldBuilder         terrain, lobby, bunker, zones, secrets spots
      BuildKit             geometry helpers
  StarterPlayer/StarterPlayerScripts/
    Client.client.luau     boots every controller
    Controllers/           UI, HUD, Build, Shop, Panels, Duo, Disasters, Quests, Gifts,
                           Guide, DropVisuals, Admin, Minigame, Music, VFX, Animator,
                           Notifications, ChatTags
tests/sim/                 headless gameplay tests (Engine, Harness, Scenarios, run)
.github/workflows/publish-roblox.yml   type check + tests + build + auto-publish to Roblox
```

## 🧪 Automated tests (`tests/sim`)

The game is tested by **playing it headless**: `tests/sim` loads the built place file
and runs the real server *and* client scripts against a simulated Roblox engine on
[Lune](https://lune-org.github.io) (virtual clock, remotes, players and characters,
DataStores, purchases, tweens, CollectionService...). 30 scenarios cover a full
502-upgrade playthrough, every disaster, duos, secrets, every admin command and rank,
Studio + real Robux purchases (no double grants), saving/loading/offline earnings,
session locks, the obby, all minigames, quests, gifts, the guide beam, clicking every
UI button, every client effect, and an exploiter firing garbage at every remote.

```bash
rojo build -o MegaTycoon.rbxlx
lune run tests/sim/run.luau -- MegaTycoon.rbxlx            # all scenarios
lune run tests/sim/run.luau -- MegaTycoon.rbxlx nuke       # one scenario
SIM_SIGNAL_ORDER=reverse SIM_SEED=7 lune run tests/sim/run.luau -- MegaTycoon.rbxlx
```
Any script error, failed check or unexpected warning fails the run. CI also runs the
suite with event handlers in reverse order (Roblox doesn't promise an order) and the
`luau-lsp` type checker.

## 🛠️ How the economy works
`TycoonItems.luau` walks all items in order and prices each one at "N seconds of the
income you'd have at that point", while each dropper/generator adds a fixed share of
income. Change `PaceStartSeconds` / `PaceEndSeconds` and every price rescales. The same
file has `ComputeIncome`, used by both the server (real money) and the client (BUILD menu).
Drops you see on conveyors are client-side visuals, so 8 full towers stay smooth.
