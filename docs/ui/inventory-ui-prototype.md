# Production CEF Inventory

The first real Inventory window follows [UI Contract v1](ui-contract.md).
The actual Metin screenshot guides density and proportions; the Mandate concept
is a future art-direction reference. Production Inventory and weapon Equipment
now compose the internal [Core UI](core-ui.md). Shop, the character sheet and
the rest of the HUD remain outside this screen.

## Layout and interaction

The window is 266 logical pixels wide, right-anchored by default, with a draggable
title, close button, I–IV tabs and Yang footer. Each page is 5×9 at 40 px per
slot. The slot size is a CSS variable. Items occupy 1×1, 1×2 or 1×3, without
rotation. The real Iron Sword occupies two vertical cells; the local
preview includes all three sizes without adding mock item definitions to gameplay.

Drag with pointer capture, or click once to carry and click to place. Green/red
previews are advisory. A drag may submit an invalid placement and get rejected;
an invalid click-to-place retains the held item. Escape first cancels carrying,
then closes. Click-carried items can move between page tabs. Wallet updates do
not cancel carrying. Authoritative inventory updates, close, resize, scale changes,
blur and pointer cancellation release transient capture/ghost state. Compact
hover tooltips flip and clamp to the viewport.

Opening is **not globally modal**. The window reports its physical rectangle.
A click-carried item temporarily reports a full-screen pointer region, then
releases it on placement/cancel. Normal button drags retain native host capture.
Inventory is a pointer-only screen: clicking buttons, tabs, items or the title
bar does not take gameplay keyboard ownership. Movement/combat hotkeys continue
to reach Godot. Other text/modal compositions may explicitly take web focus.
Godot handles I; Escape is sent as a fixed `ui.shortcut` presentation event so
web can cancel carrying first, then request close. Closing clears Inventory's
regions without hiding the global browser.

Window measurements are deferred while hidden. Opening, viewport snapshots and
browser resize clamp the measured window back into the visible viewport. Drag
updates are coalesced with requestAnimationFrame and use translate3d rather than
repeated left/top layout changes; pointer capture still lasts through release.
CEF is currently capped at 60 FPS by `godot_cef/performance/max_frame_rate`. This
is a configured maximum, not a measured input-to-photon or native frame-rate claim.

## Authority and persistence

`CoreUiController` maps private server state; the view has no CEF APIs.
It renders `ui.snapshot` and `inventory.updated`; `wallet.updated` and
`hud.updated` refresh information/layout without replacing item state.
`ui.ready` after reload/recreation receives the current full snapshot. Commands
reuse request correlation and await the actual World Server operation reply.

```json
{"type":"inventory.move_item","payload":{"id":"<uid>","revision":3,"x":2,"y":4,"page":1}}
```

The protocol wrapper adds `v: 1` and a correlated request ID. Other screen commands are `inventory.close`, `equipment.close`,
`equipment.equip` and `equipment.unequip`. Neither exposes arbitrary method calls.

World Server validates coordinates, ownership, revision, bag placement,
page boundaries and every occupied cell. Placement and revision commit in one
immediate SQLite transaction. Rejections republish authoritative state; JS never
commits a local item move. Native equip/unequip and runtime combat-stat refresh
retain their existing atomic flow.

Schema **v15** expands bag anchor positions to 0–179 (four 45-cell pages).
An atomic migration retains UID, owner, stats, affixes and sockets. Old anchors
are kept when valid; collisions are repacked into the first available footprint,
with a revision increment. A failed migration rolls back placement/schema/version
changes. No items are deleted. Pickup/free-slot search and equipment swaps now
respect footprints. This is a small explicit grid model, not a stat or crafting
framework. XP and wallet checkpoint policy is unchanged.

## Local skin

`tools/dev_assets/stage_ui_skin.py` copies selected individual PNGs from ignored
`dev_assets/legacy/ui_cache` into ignored
`source/client/ui_web/web/inventory/legacy_skin`. It verifies byte-identical
SHA-256 hashes; there is no resampling. Semantic names include corners, edges,
fill, title, close states, slot and Yang. Separate exports hold item content
icons and global UI icon groups. `skins/legacy.js` adapts these optional files
to the semantic Core UI skin boundary. Edges tile; icon rasters keep native dimensions. Text is real
font rendering. No CSS atlas coordinates, CDN, internet asset loading or frontend
framework is involved. A checkout without local skin uses CSS/text fallbacks; the browser test also
checks a deliberately unavailable skin module.

Stage the existing extracted cache:

```powershell
python tools/dev_assets/stage_ui_skin.py
```

The gameplay launcher also stages the skin automatically. If item icon exports
are missing, the exact PNG exporter can generate them from the local reference:

```powershell
python tools/dev_assets/export_ui.py --source-root 'N:/Mandate local/metin2/bin/pack/icon/icon' item/00010.tga item/00020.tga item/27001.tga
```

Legacy skin remains visibly limited at large scales. Replace it with Mandate
assets meeting the 2×/150% quality target later; do not enhance legacy graphics.

## Launch and scale

Keep gateway/master/world running headless from the root project, then:

```powershell
& ./tools/cef_client/run.ps1
# Prepare/import without opening a game window:
& ./tools/cef_client/run.ps1 -SetupOnly
```

This installs pinned CEF into `addons/godot_cef` and runs the actual root project.
Native payloads, profiles, reference PNGs and runtime stores remain ignored.
The project defaults to a 1280×720 window with a 1920×1080 design baseline and
**disabled canvas stretch**. The browser tracks actual window pixels. Local
headless runs create no browser; server exports exclude CEF entirely. Unsupported
clients show a technical UI-unavailable message without a second inventory renderer. See [CEF addon integration](cef-addon-integration.md).

Godot's `CoreUiController.set_ui_scale()` accepts the contract's scale list.
For development set project setting `mandate/ui_scale` or launch the root
client with `--ui-scale=125`. Scale is selected once and stays independent of
subsequent window resolution. No settings screen is included in this slice.

Local fixture preview:

```powershell
python -m http.server 18741 --bind 127.0.0.1
```

Open [inventory preview](http://127.0.0.1:18741/tools/inventory_preview/).
`?scale=0.9` changes preview scale. Its mock host is never used by the game.

## Verification — 2026-10-09

```powershell
& ./tests/run-smoke.ps1
# Optional when changing inventory RPC/session behavior:
& ./tests/run-web-inventory.ps1
```

Default smoke protects item transactions/identity, grid placement/migration,
pickup, progression/wallet checkpoints and the Web bridge. The client and server
share `ItemInstance.valid_uid()` for wire format only; ownership/revision and
all placement validation remain server-authoritative. The exported client must
not depend on `ItemStoreSqlite` for local command validation.

Use the optional two-client headless Inventory regression after RPC changes.
`run-cef-export.ps1` checks bundled client resources and client-side UID validation
without SQLite, plus CEF-free server packs. The [UI contract matrix](ui-contract.md)
is a manual layout milestone check, not exact-DOM CI.

Initial browser/native results are preserved in
historical validation (available in Git history). Physical
input/DPI/IME, full release packaging and long-session soak remain release gates;
headless checks do not prove those behaviors.

Item placement preserves the cursor grab offset and snaps the whole footprint to
its nearest grid origin. Grabbing the bottom of a tall item does not make the
cursor cell its top slot. Preview and move command use the same snapped origin;
bounds and overlap remain server-authoritative.

The client starts CEF and loads the bundled Inventory page during world setup,
after bridge/commands and initial domains are wired. Inventory remains hidden
(`inventory_open=false`), reports no interactive regions and leaves input with
gameplay. UI_READY receives the latest snapshot even if inventory/wallet data
arrives during browser startup. Opening/closing only updates presentation state;
it does not create a browser. Startup failure releases input and shows a technical UI-unavailable message.
This moves the cold-start cost to entering the world; it does not eliminate CEF's
startup time or guarantee readiness if the player opens Inventory immediately.

UI scale is available in Options → Graphics → Display, in the existing native
Settings menu (also accessible from login). The game status panel has an Options
button. Values are Auto and 80/90/100/110/125/140/150 percent. Selection saves
[interface]/ui_scale_percent in client_settings.cfg and immediately updates Web UI
through the settings signal and hud.updated; no Web settings command is exposed.
Options closes Inventory and owns gameplay input until Close/Escape. The setting
scales Web UI only; the native options/login layout is unchanged. Startup priority
is --ui-scale, saved preference, project setting, then viewport default. Auto uses
the startup defaults again. The CLI override is reapplied at the next launch.

## Equipment window

I opens/closes Inventory and Equipment together. Their close buttons work
independently; Escape cancels carrying first, then closes the remaining windows.
Equipment has independent pointer-captured dragging, viewport clamping and the
same logical UI scale. It reuses Inventory's window chrome. The optional
`equipment-base` skin is copied exactly from the local legacy cache (156×188),
with a simple CSS fallback in clean checkouts. No screenshot/concept art is baked
into the UI and no legacy image is regenerated or resampled.

Right-click a bag item to send `equipment.equip`; click an equipped weapon to send
`equipment.unequip`. Both payloads contain only id/revision, use existing request
correlation and the authenticated equipment RPC. Server commits ownership,
revision, slot/swap and free-bag placement, updates runtime stats and sends the
current authoritative inventory/equipment. Rejections keep that state. Unequip
uses the first free fitting bag position; cross-window item dragging is not part
of this slice. The weapon slot is functional. Other visible slots are disabled
layout placeholders; no armor/accessory systems were added. The eleven hover
regions use the original equipment panel's slot layout including its (3,3)
inset: weapon, helmet, armor, shoes, bracelet, necklace, earrings, shield,
arrows and two special slots. Empty artwork outside these regions has no
placeholder tooltip. Layout stays in the screen, not in the skin. Equipment and stats
recover through ui.ready snapshots. The local preview demonstrates both windows
and mock equip/unequip without touching game persistence.

One-handed Iron Swords now occupy 1×2 bag cells, driven by ItemDefinition on the
server. The grid still supports 1×3 for future taller items. Existing placements
keep their anchors and UIDs: shrinking the footprint releases cells and requires
no database migration. Equipped icons have no extra CSS frame or hover fill;
the unmodified legacy background still supplies its painted slot edges.

## Window and request boundaries

Inventory and Equipment compose `UiWindow` and share `WindowManager`
([Core UI contract](core-ui.md)). Drag/capture/titlebar/close/resize logic belongs
to the shared shell/manager, and both screens use the same tooltip positioning. Each window registers its ID,
preferred anchor and logical default offset. Initial Equipment placement uses the
measured Inventory rectangle. Manual positions survive state updates, and both
windows clamp on viewport/scale changes and reopening. Layout never reads a
neighbor's CSS width variable. Hidden windows retain their last measured geometry;
unmeasured neighbors fall back to the preferred anchor until visible.

The controller tracks independent RPC results by generated command ID with a
per-controller epoch. Replies may arrive out of order. Each request has its own
2.5-second timeout; reload, disconnect and teardown cancel unresolved waiters.
Server rate limits, revisions and transactional validation still apply; removing
single-flight transport does not authorize conflicting economic operations.

`InventoryEndpoint3D` retains networking, snapshots, public weapon replication and
the existing sword comparison helper. Its native panel/buttons are removed.
A general item presenter is deferred until the first additional item type.
