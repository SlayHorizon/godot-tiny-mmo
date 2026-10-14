# Mandate of Three

A multiplayer 3D game inspired by Metin 2, built in Godot on
[Godot Tiny MMO](https://github.com/SlayHorizon/godot-tiny-mmo) infrastructure.
This repository contains a working technical vertical slice, not a game alpha.

## Current scope

- Gateway, master and world: login, sessions, character creation and instance entry.
- 3D spike: server-side movement and physics, collisions and remote-character interpolation.
- ItemDefinition and persistent ItemInstance: UID, owner, bonuses, equipping a specific
  instance and transactional SQLite persistence.
- Initial loot progression: weapon attack shown on the ground, comparison with the
  equipped instance, attack preview after swapping and persistent sword equipment.
- [First region graybox](docs/world/first-region-graybox.md): hub/Blacksmith, three combat areas,
  six mixed packs (104 mobs) of increasing difficulty, roads/shortcuts, landmarks,
  four Metin candidate sites and a visual water strip. [Pack AI](docs/gameplay/mob-packs-v1.md),
  shared aggro and server-side straight-line movement; directional melee hitting multiple
  targets, [Warrior 4/5/6-hit combo](docs/gameplay/combat/warrior-basic-combo-v2.md), hit reactions and final-hit knockdown/get-up with physical displacement.
- [Metin Encounter v1](docs/gameplay/metin-encounter-v1.md): one random active site, HP
  threshold waves, shared combat/contribution, one ground reward and timed respawn.
- Player and mob death/respawn, ground loot, reservation and persistent pickup.
  Two-client tests cover combat, death and competition for the same loot.
- XP for killing dogs, levels, progress bar and level-up; persistence across relog,
  dirty progression checkpoints approximately every 60 seconds and session-end saves.
- Yang wallet, ground currency with loot rights and auto-pickup; a separate dirty
  delta checkpoint every 30 seconds and an atomic test spend including pending income.
- Active-character combat stats in RAM; swings do not query SQLite inventory.
  Item pickup and equipment retain immediate DB transactions.
- An opt-in [Web UI foundation](docs/ui/web-ui.md): protocol v1, explicit commands,
  domain snapshots and region-based input routing. The root gameplay client uses the new Inventory screen,
  with real server-authoritative item commands. CEF is installed into `addons/godot_cef`;
  server export presets exclude it. CEF officially
  targets Vulkan Mobile; Compatibility is unsupported / best-effort.

Controls: **WASD** to move, **I** for inventory, **hold Space** for a combo in front
of the character, **E** to pick up nearby loot. **Left click** selects an optional
target; **F** toggles autoattack, interrupted by manual movement. Nearby Yang is
picked up automatically; **G** picks up the nearest stack. A HUD test button spends
50 Yang.

Mob AI uses direct chase/return and ignores props while retaining server floor physics.
The shared region navmesh guides NPC approach. Unclaimed loot, HP and position
are runtime state; items become persistent on pickup. AOI, local prediction and
final models/animations remain future work. Optional local development visuals
are described below. Upstream modules still present do not imply available 3D features.

The normal login map is the graybox region; the small arena remains an integration
test fixture. Metin Encounter v1 is playable; a pack density/combat feel playtest, then pacing and visual passes are next.

Camera v1 uses RMB orbit and wheel zoom, with independent view rotation and scenery
collision. Settings and verification notes: [Camera v1](docs/gameplay/camera-v1.md).

## Local setup

Verified engine: **Godot 4.7.2**, installed locally in `.godot/`.
Godot and godot-sqlite native binaries are not versioned; a fresh checkout needs
local installation. `.godot/` contains local cache, the engine and test results.

For clickable local commands in WebStorm, open the root `package.json` and click
Run beside a script, or select the shared `.run` configurations. Configure the
project Node interpreter if the IDE asks for one. `servers:start` starts all roles;
`servers:restart` restarts Master + World and lets the existing Gateway reconnect;
`world:restart` restarts World alone; `servers:stop` stops all three;
`servers:status` reports local processes/listeners. Roles run hidden with logs in
`.godot/runtime`. Stop/restart requests a final World checkpoint via the Master
dashboard and refuses to force-kill World if it cannot save/exit. For a protected
local dashboard, set `MANDATE_DASHBOARD_TOKEN` in your environment. These commands
use the default local ports/configuration and preserve runtime stores.

Equivalent direct PowerShell entry: `./tools/servers.ps1 -Action restart -Target game`.

Start the three roles in separate PowerShell terminals from the project directory:

```powershell
& .\.godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --mode=master-server
& .\.godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --mode=gateway-server
& .\.godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --mode=world-server
```

Then start a client, or two clients for multiplayer testing:

```powershell
& .\.godot\Godot_v4.7.2-stable_win64.exe --path . --mode=client
```

For the new Web Inventory screen (Windows, Vulkan Mobile), keep the
servers above and launch the client:

```powershell
& ./tools/cef_client/run.ps1
```

This installs pinned CEF into the root project and imports it; no game sources
are copied. Subsequent source edits run directly from this checkout. I opens inventory;
drag moves items, click picks up/places items and Escape cancels
carrying before closing. See [inventory UI](docs/ui/inventory-ui-prototype.md).
The real bag now has four 5×9 pages with authoritative item footprints. Schema
v15 migrates old placements atomically. See [UI Contract v1](docs/ui/ui-contract.md).

Alternatively, use Godot **Debug -> Customize Run Instances** with separate feature
tags `master-server`, `gateway-server`, `world-server` and `client`. Place `--mode`
before the `--` separator. Default configurations are in `data/config/`.
Accounts and world databases are local runtime data excluded from Git.

Gateway address is explicit: `network/api/base_url` in `project.godot`, defaulting
to `http://127.0.0.1:8088` in editor/debug/release. A release build does not select
upstream services. No Mandate website/Discord is configured yet. The inherited
`slayhorizon` user-data directory is intentionally preserved to retain accounts,
characters and client preferences. The Godot icon is a temporary placeholder.

Export presets: `Windows` (client), `ServerWindows` / `ServerUbuntu` (shared server
roles), `LinuxClientUnverified`, `LegacyWebUnsupported` and
`LegacyAndroidUnsupported`. The latter three are not verified release targets.
See [export setup](docs/ui/cef-addon-integration.md).

## Tests and workflow

```powershell
& .\tests\run-smoke.ps1
```

Default smoke protects persistence and the bridge without opening game windows.
Choose extended network/gameplay tests only for the affected flow. See
[testing policy](docs/development/testing.md). For addon/export changes, optionally run
`tests/run-cef-export.ps1`; it checks client resources, CEF-free server packs
and headless server-pack boot. See [CEF setup](docs/ui/cef-addon-integration.md).
Work on `codex/<topic>` branches, review and verify changes, then merge locally
with `--no-ff`. See [AGENTS.md](AGENTS.md).

## Documentation

**Start with the [documentation index](docs/README.md)**. Current references are grouped by ownership instead of milestone dates:

- [Architecture and Economy contracts](docs/architecture/README.md)
- [Gameplay, combat and NPC systems](docs/gameplay/README.md)
- [World, maps, visuals and Terrain3D](docs/world/README.md)
- [CEF and UI](docs/ui/README.md)
- [Development, testing and CI](docs/development/README.md)
- [Accepted decisions](docs/decisions/README.md) and [active plans](docs/plans/README.md)
- [Historical evidence](docs/evidence/README.md); obsolete milestone plans are recoverable from Git history

The running single-World + SQLite implementation is distinct from the accepted future Economy V2 and multi-World architecture.

## Upstream and credits

The fork retains Godot Tiny MMO infrastructure by **slayhorizon**:
[upstream repository](https://github.com/SlayHorizon/godot-tiny-mmo) and
[infrastructure documentation](https://slayhorizon.github.io/godot-tiny-mmo/).
Upstream maps were created by **higaslk**; some remaining assets are from
**Anokolisa / Dungeon Crawler Pixel Art Asset Pack**. Upstream acknowledgements
also include Jackiefrost, d-Cadrius and other contributors.

Open-MT2 is a behavioral reference for Metin, without importing its code, assets
or runtime. Upstream code uses the [MIT license](LICENSE), with its copyright notice retained.
