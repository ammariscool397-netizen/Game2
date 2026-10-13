# 💰 MEGA TYCOON — Roblox Tycoon Game

A complete, fully scripted Roblox tycoon. **Everything is built from code**:
the map, plots, droppers, VFX and UI are all generated at runtime, so the game
works without any uploaded models or images.

## ▶️ Quick start (no tools needed)

1. Download **`MegaTycoon.rbxlx`** from this repo.
2. Open it in **Roblox Studio** (File → Open from File).
3. Press **Play**. That's it — the whole world builds itself.

> In Studio every player is an **Owner admin** and Robux purchases are
> **simulated for free**, so you can test everything.

### Working on the code with Rojo (optional)
```bash
aftman install          # or: rokit install  (installs Rojo 7.4.4)
rojo serve              # then connect from the Rojo Studio plugin
rojo build -o MegaTycoon.rbxlx   # rebuild the place file
```

## ✅ Before you publish

All settings live in `src/ReplicatedStorage/Shared/Config.luau`.

| What | Where in Config | Notes |
|---|---|---|
| Game Pass IDs | `Config.GamePasses.*.Id` | Create passes on the Creator Dashboard. `0` = not configured |
| Developer Product IDs | `Config.Products.*.Id` | Cash packs, 2x boost, server cash rain |
| Admins | `Config.Admin.Admins` | `[UserId] = rank` (1 Mod, 2 Admin, 3 Head Admin, 4 Owner). The place creator is always Owner |
| Group ranks | `Config.Admin.GroupId` / `GroupRanks` | Optional |
| Music | `Config.Music` | Replace the IDs with audio you're allowed to use (Creator Store → Audio, tracks uploaded by *Roblox* are free). Broken IDs are skipped automatically |
| Codes | `Config.Codes` | e.g. `RELEASE`, `MEGATYCOON`, `BOOST`, `THANKYOU` |
| Economy | `Config.Rebirth`, `StartingCash`, `TycoonItems.luau` | Prices, drop values, multipliers |

Also: **Game Settings → Security → Enable Studio Access to API Services**
(needed for saving data / leaderboards in Studio).

## 🎮 Features

**Tycoon**
- 6 auto-assigned plots with owner signs, conveyor, collector and vault pad
- 21 purchasable items: 9 droppers (Basic → Galaxy), 3 upgraders (x1.5 / x2 / x3),
  walls, garden, fountain, rainbow neon sign, golden statue, cash tower with sky beam, speed pad
- Buttons unlock in order, turn green/red when you can/can't afford them
- Vault system (step on the pad to collect) — or skip it with the Auto Collect pass
- Rebirths: reset for a permanent +0.5x multiplier each, scaling cost
- DataStore saving (autosave, save on leave, save on shutdown, retry logic)
- Global "Top Earners" leaderboard in the lobby

**Robux shop (🛒 SHOP / G key)**
- Game passes: 2x Cash, Auto Collect, Fast Droppers, VIP (+50% cash, aura, chat tag, 2x daily), Super Speed
- Products: 4 cash packs (scale with rebirths), 15-min 2x Boost, Server Cash Rain
- Secure `ProcessReceipt` with purchase history (no double grants), live Robux prices

**Admin system (`;cmds`, 🛡️ button or F2)**
- 50+ commands with ranks, chat commands and a full **Admin Panel**
  (command bar, command list, player list with quick actions, server controls, logs)
- Permanent DataStore bans (works on offline users), filtered announcements

**Minigames** (every 2.5 min — press JOIN)
- 🪙 Coin Rush — grab the most coins
- 🟥 Falling Tiles — two layers of tiles that drop when touched, last one standing wins
- ☄️ Meteor Shower — dodge meteors with warning circles, explosions and knockback
- Countdown, live HUD, results screen, cash rewards, winner announcements

**Obby** — west of the lobby: jumps, kill bricks, spinners, trusses, beams,
zigzags, 6 checkpoints and a finish reward (10 min cooldown)

**Extras**
- Animated loading screen (asset preloading, progress bar, tips, music, skip button)
- Background music playlist with now-playing widget (skip / mute), minigame music, admin DJ
- Custom VFX: purchase bursts, build-in animations, floating cash popups, cash flying
  to your counter, shockwaves, confetti, cash rain, rebirth flash + camera shake, speed lines
- Daily rewards with 7-day streaks, codes, settings (music volume, SFX, low graphics)
- Chat tags: `[Owner]` `[Admin]` `[👑 VIP]` `[R5]`
- Lighting: atmosphere, bloom, sun rays, color correction

## 🛡️ Admin commands

Prefix is `;` — e.g. `;speed me 100`, `;givecash all 1m`, `;tp bob me`.
Player selectors: `me`, `all`, `others`, `random`, `admins`, `nonadmins`,
partial names, or comma lists (`me,bob`). Amounts accept `10k`, `2.5m`, `1b`.

| Rank | Commands |
|---|---|
| **Mod (1)** | `cmds` `logs` `tp` `bring` `to` `home` `speed` `jump` `heal` `god` `ungod` `ff` `unff` `kill` `freeze` `thaw` `sparkles` `fire` `smoke` `unfx` `invisible` `visible` `respawn` `jail` `unjail` `fly` `unfly` `noclip` `clip` `view` `unview` `m` (announce) `h` (hint) |
| **Admin (2)** | `kick` `givecash` `takecash` `setcash` `giverebirth` `rebirth` `unlockall` `explode` `giant` `tiny` `normal` `confetti` `cashrain` `doublecash <min> [mult]` `music <id>` `stopmusic` `minigame [name]` `time <0-24>` |
| **Head Admin (3)** | `ban` `unban` `resetdata` `givepass` `removepass` |
| **Owner (4)** | `admin <player> <rank>` `unadmin` `shutdown` |

## 📁 Project structure

```
src/
  ReplicatedFirst/LoadingScreen.client.luau   loading screen
  ReplicatedStorage/Shared/
    Config.luau        ALL settings
    TycoonItems.luau   buyable items (prices, positions, values)
    Remotes.luau       networking
    UIKit.luau         UI helper library
    Util.luau, Signal.luau
  ServerScriptService/
    Main.server.luau   boots every service
    Services/
      DataService          saving / loading / cash
      TycoonService        plots, buttons, droppers, rebirth
      TycoonBuilder        procedural item models
      MonetizationService  passes, products, receipts
      AdminService         admin commands + bans
      MinigameService      Coin Rush / Falling Tiles / Meteor Shower
      ObbyService          obby generation + checkpoints
      RewardService        daily rewards, codes, settings
      LeaderboardService   global leaderboard
      WorldBuilder         lobby, lighting, boards, trees
      BuildKit             geometry helpers
  StarterPlayer/StarterPlayerScripts/
    Client.client.luau     boots every controller
    Controllers/           UI, HUD, Shop, Panels, Admin, Minigame,
                           Music, VFX, Animator, Notifications, ChatTags
```

## ➕ Adding a new item
Add an entry to `TycoonItems.luau` (`Kind = "Dropper" | "Upgrader" | "Walls" | "Decor" | "SpeedPad"`).
Buttons are placed automatically. For a new decoration, add a builder to
`decor` in `TycoonBuilder.luau`.
