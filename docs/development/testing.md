# Prototype testing policy

Accepted 2026-10-09: keep a small set of stable regression contracts during rapid
prototyping. A tiny UI/style or balance change should not require repairing a
browser screenshot, a specific DOM tree or a combat animation timeline.

## Contracts before implementation

Accepted 2026-10-12: test contracts and observable behavior. Inspect internals only
for a concrete bug or a critical invariant that cannot reasonably be checked
from outside.

Prefer, in order:

1. Existing behavior suites and their scenarios.
2. New integration coverage when the affected contract is not already covered.
3. Focused implementation unit tests when they are needed to isolate the risk.

Add or extend a test only when there is a new contract, a concrete bug, a critical
invariant, or a risk the current suites do not cover. Name that risk and explain
the coverage gap in the test/comment or change description. A new class or an
extraction alone does not justify new tests. Do not duplicate integration coverage
with assertions that mirror method calls, private maps or class layout.

For economy changes, prefer results: new item/stats and wallet balance after a
commit, the private Inventory received by the client, subsequent damage using the
equipped stats, and unchanged state after rollback. Do not encode the order of
refresh_authoritative_state versus a signal subscriber as the acceptance test.
A public change fact is a contract; its subscriber registration order is not.

For Package B, protect PlayerCombatRuntime and the service/actor extractions
primarily with existing ACTION, FEEL2, combat and network suites. Extend those
scenarios if a risk is uncovered. New focused unit cases may be justified for
buffered intent, cancel, hitch-safe impact, or cleanup after remove/death, but
should not repeat coverage merely because ownership moved to another class.

During extraction, use existing suites first. Add a test only when the extraction
exposes a concrete behavioral contract not actually covered today. Full line/path
coverage for PlayerCombatRuntime or each extracted class is not a goal.

Existing tests are regression evidence, not immutable API. During extraction,
preserve behavioral contracts, but freely rewrite or remove tests that assert
obsolete private state, implementation order, or ownership. Do not preserve old
internals solely to keep a test green. Controlled fixture setup may change with
the owner; a removed assertion still needs a reason grounded in the contract,
rather than removing a genuine behavior regression to make the suite pass.

Test setup may seed SQLite or configure a controlled actor. That does not make
private state or the setup mechanism the expected production behavior. Internal
probes need a specific justification; for example, the known Inventory publication
coupling regression checks that publication cannot refresh combat cache, and the
RAM-only swing invariant checks that an attack does not read SQLite Inventory.
Keep such exceptions narrow and separate from ordinary success/rejection checks.

## Default

```powershell
git diff --check
& ./tests/run-smoke.ps1
```

Godot 4.7.2 and Node 20.19+ are required. Run `npm ci --ignore-scripts` in
`source/client/ui_web` once for the pinned compiler and test dependencies.
Smoke compiles TypeScript and tests the emitted static browser JS. `-NodeExecutable` can select a bundled Node.
No running server, browser, GUI, network port or production accounts are required.
The smoke suite does not install/download CEF. Installing CEF is optional; installed CEF loads in headless without
creating a browser. The suite has six small SQLite scenarios, one NPC content/context fixture and one bridge contract group:

- Item identity, ownership, revisions, atomic equip/move and rollback/reopen.
- Inventory footprints, page bounds, overlap and atomic legacy migration.
- Pickup identity, full bag, double pickup and partial-write rollback.
- XP/level RAM updates and dirty checkpoints, including forced save and crash window.
- Wallet deltas, immediate critical spend, rollback/checkpoint and relog.
- NPC Shop offer/stack invariants, exact/first-fit purchase, capacity-before-charge,
  pending Yang, rollback and durable item identity.
- Neutral NPC definitions, service references, map/range/context authority and teardown.
- Bridge framing, explicit command boundary, readiness, request correlation and
  full snapshot recovery; small Core UI lifecycle, skin and icon contracts.
  No browser rendering or network fixture is involved in default smoke.

Successful runs delete their disposable databases and overwrite a small fixed
set of logs under `.godot/verification`. Failed runs retain diagnostic state.
These tests intentionally protect persistence and authority, not prototype visuals.

## Optional integration

The existing headless gameplay/network runners remain available on demand:
`run-spike3d`, `run-pve`, `run-combat`, `run-progression`, `run-xp`, `run-yang`,
`run-web-inventory`, `run-npc`, `run-shop`. Choose the affected flow for movement/combat/XP/wallet/RPC
changes; do not run all of them after CSS edits. They share port 18098: run
sequentially. `run-items.ps1 -WithSession` requires normal gateway/master/world
roles and writes guest fixture accounts; use it for actual session/login changes.

`run-first-region.ps1` loads the production graybox scene headlessly and checks
connected navigation to NPC/pack/Metin sites, safe hub spawns, authored composition
and the shore boundary. It opens no window and does not assert exact
layout or balance. See [region notes](../world/first-region-graybox.md).

Default smoke also covers mixed mob packs, shared aggro, anchor leash, unique
replacement IDs, Metin pack expiry, a short 50-actor AI tick, compact mob wire
round trips and serialized payload measurements for 50/100 actors. See [mob packs](../gameplay/mob-packs-v1.md).

`run-metin.ps1` covers the small stone lifecycle contracts.
`run-metin-network.ps1` is the optional two-client production encounter/ground
reward/cleanup/respawn flow with disposable SQLite on port 18098; run sequentially
with other PvE network suites. Neither opens a native window.

`run-cef-export.ps1` is an optional packaging-boundary check after addon/export
changes: client Web assets and CEF registration, CEF-free server packs and
client/server pack headless boot (including real client UID validation without
SQLite). It requires the local CEF installation and opens no windows.

`run-core-ui-browser.ps1` is an opt-in [Core UI milestone check](../ui/core-ui.md)
using the production page, controlled IPC and an installed headless browser.
It checks behavior and broad bounds, with no pixel/exact-tree assertions or downloads.
It does not replace native root-client CEF verification.

`run-shop-browser.ps1` is the analogous optional [NPC Shop view check](../gameplay/npc/npc-shop.md).
Pass the installed `-PlaywrightModule` and `-BrowserExecutable`, and optionally
`-ScreenshotDirectory`. It verifies rendered skin/fallback, broad frame bounds
and Shop/Inventory placement, mouse purchase gestures, tooltip, catalog pages
and close/Escape with controlled IPC; no game accounts or running servers. It also
checks [Upgrade](../gameplay/npc/npc-upgrade-ui.md): server-driven item selection/commit/rejection,
a +0 → +1 snapshot and an explicit execute command without optimistic mutation.
The separate developer page retains visual level controls.

Asset pipeline tests and visual fallback probes remain optional for pipeline
changes. The small default suite downloads no browser and does not install Pillow.

The old CEF spike, its mock/diagnostic adapter, its renderer/measurement runners
and the exact-layout browser matrix test were removed. The original adoption
results belong to the retired CEF spike (recoverable from Git history). The inventory
resolution matrix is a manual milestone checklist in [UI Contract v1](../ui/ui-contract.md),
not a pixel-sensitive CI assertion. Use the root client for CEF/input/
resize/transparency/shutdown checks; no parallel standalone UI mock.

## CI and cleanup

Push/PR CI installs the pinned Web UI development dependencies, compiles TypeScript,
checks that committed runtime assets match their source, imports a clean checkout,
checks whitespace and runs smoke.
Workflow dispatch can opt into extended gameplay/asset checks. Local execution
verifies the scripts; it does not prove the remote Actions run until published.

```powershell
& ./tools/clean-dev-artifacts.ps1 -WhatIf
& ./tools/clean-dev-artifacts.ps1
```

Cleanup removes `.godot/verification`, retired spike/copied-client caches and the named old
scratch files, within checked workspace paths. It preserves `.godot/imported`,
editor cache, engine binaries, the installed root CEF addon/plugin archive cache, reference
checkouts, local asset cache and normal player/account data. Temporary work should
live under `.godot/verification`, rather than accumulating at the .godot root.

`run-upgrade.ps1` is an opt-in two-client production Upgrade RPC suite on port
18098; run sequentially with the other PvE-derived suites. Smoke includes one
material/item/wallet rollback fixture and small UI/bridge contracts.

`run-camera.ps1` is the optional headless Camera v1 collision/picking fixture.
See [Camera v1](../gameplay/camera-v1.md) for the native input/framing acceptance checklist.

Hit reaction smoke covers profiles, flinch without locks, bounded knockdown/get-up,
independent displacement resistance, damped impulses and real scenery collision,
interrupt independence and snapshot recovery. `run-combat` exercises the same
authority with two clients, including the player-target pending-hit path. See
[Hit Reactions v1](../gameplay/combat/hit-reactions-v1.md).

Warrior combo v2 reuses the durable `hit_reactions` smoke case for exact 4/5/6
sequence and runtime reset contracts. `run-combat.ps1` verifies four/six native
animation keys at both real clients, plus pending-toggle/interruption behavior.
The optional [combo review](../gameplay/combat/warrior-basic-combo-v2.md#verification-and-remaining-manual-review)
uses the existing Warrior compatibility scene; rendered images are disposable
verification artifacts, not snapshot assertions in smoke.

`run-combat-trace.ps1` is the optional geometry plus two-client 50/100-target
Warrior trace contract suite. It uses port 18098; run sequentially with PvE suites.
`run-combat.ps1 -LegacyMelee` covers the retained fallback. Bake/native comparison
commands and verification limits are in [Warrior Combat Trace v1](../gameplay/combat/warrior-combat-trace-v1.md).

`run-combat.ps1 -Scene combat_feel_v2 -MarkerPrefix FEEL2` is the opt-in two-client
Attack Speed/buffer/facing and pooled confirmed-feedback contract check. Native
AS 100/122/150 and four/five/six-hit preview commands and verification boundaries
are in [Warrior Combat Feel & Presentation v2](../gameplay/combat/warrior-combat-feel-v2.md).

`run-combat.ps1 -Scene warrior_action_polish -MarkerPrefix ACTION` covers late
scheduled impacts, full-motion movement locks, authoritative forward advance and
scenery collision, visual turn blending, local finisher impulses and reusable
trail resources. Preview controls and authoring sources are recorded in
[Warrior basic action polish](../gameplay/combat/warrior-action-polish.md).

The same ACTION suite also checks full-motion advance versus interrupted chaining,
asymmetric movement BODY blocking, existing-overlap escape and finisher knockback
freeing space. The actual-physics native volume preview and measurements are in
[Warrior BODY collision](../gameplay/combat/warrior-body-collision.md). These checks remain opt-in.

`run-visual-v0.ps1` is an optional native Windows/Vulkan/CEF feasibility pass for
Mobile and Forward+ on the production First Region scene. It reuses the isolated
PvE fixture (port 18098, run sequentially), real production Web UI and server RPCs.
It protects renderer migration against missing/black CEF output, broken native
synthetic input/drag/orbit, lifecycle recovery and NPC transactions; headless
bridge/Node suites cannot exercise the native accelerated texture or GPU path.
Logs, captures and a short timing sample remain ignored under `.godot/verification`.
No pixel snapshots or balance/timing assertions are added to smoke. Physical
mouse/keyboard, DPI/alt-tab, feel and release executable packaging remain separate.
See [Visual V0](../world/visuals/visual-upgrade-v0.md) for commands and current evidence.

The same runner's `-Scene visual_v1 -RenderingMethod forward_plus` reuses that
native pass and adds four before/after world views in a separate SubViewport.
It checks the new fixed-time contract across real rendered frames and confirms
that the actual server omits the Sky3D environment. There are no image assertions:
captures support manual review of the lighting milestone. See [Visual V1](../world/visuals/visual-upgrade-v1.md).

`run-combat.ps1 -Scene world_time_network -MarkerPrefix WORLD_TIME` reuses the
two-client fixture for shared authoritative calendar, late entry, epoch recovery,
extrapolation/resync, midnight and malformed/stale/delayed sample contracts.
Existing gameplay suites do not cover calendar synchronization. Run sequentially
with other port-18098 fixtures. `run-visual-v0.ps1 -Scene visual_v2
-RenderingMethod forward_plus` adds a full-day continuity review, nine hour views,
moon/stars and 91 native timelapse frames to the existing CEF/transaction pass.
There are no pixel baselines. See [Visual V2](../world/visuals/visual-upgrade-v2.md) for artifacts,
optional GIF encoding and verification boundaries.

`run-visual-v0.ps1 -Scene visual_v3 -RenderingMethod forward_plus` adds paired
water review views, day/sunset/night/moon lighting, close/distant/production-camera
motion captures and paired GPU samples to the existing CEF/transaction pass.
Shader compilation errors fail the native runner. No pixel baselines are added:
headless suites cannot establish screen/depth sampling or temporal appearance.
The existing `run-first-region.ps1` protects shore blocking/navigation. See
[Visual V3](../world/visuals/visual-upgrade-v3.md) for configuration, artifacts and limits.
