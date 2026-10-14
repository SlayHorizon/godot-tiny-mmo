# Web UI foundation

CEF provides DOM layout, CSS styling and browser text/pointer handling over
Godot's 3D viewport. The goal is a reusable screen-space UI boundary while Godot
retains client state and the server retains gameplay/economy authority.

The client has a small Web UI boundary. The first integrated screen is the
[3D Inventory](inventory-ui-prototype.md), available in the root
Vulkan Forward+ gameplay client. Other gameplay screens retain native Godot UI. The production source contains no mock inventory or diagnostic
commands. The addon is installed locally in `addons/godot_cef`. Exported servers omit it.
Local headless runs load the extension but never instantiate a browser.

The original CEF spike has been retired; its investigation is available in Git history. This document
specifies **protocol v1** and the current foundation. Its tests replace the old
unversioned bridge tests; the standalone spike is retired.

Browser source is TypeScript under `source/client/ui_web/ts`; the static emitted
JS stays at the existing `web/` paths. See [the build/test contract](../../source/client/ui_web/README.md)
for setup and generated asset ownership. Native IPC remains runtime validated.

## Official renderer target

Decision accepted 2026-10-12: **CEF Web UI officially targets Vulkan Forward+**
after the [Visual V0 native feasibility pass](../world/visuals/visual-upgrade-v0.md). Mobile also
passed the same fixture and remains an explicit launcher comparison option.
Compatibility/OpenGL is **unsupported / best-effort**. Its failed drag test stays
as historical evidence, but Compatibility parity is not a production adoption
gate. Do not add input/rendering workarounds just to support that renderer.

The root project and CEF client launcher default to Forward+ with Vulkan. The
host requires Vulkan, a non-headless display and the installed addon; it no
longer gates browser composition on the Mobile rendering method.

## Architecture and application wiring

- `source/client/ui_web/web_ui_host.gd`: the only production CEF adapter. It
  creates a transparent, anchored CefTexture dynamically, sends/receives IPC,
  handles browser lifecycle, navigation and native input ownership.
- `web_ui_bridge.gd`: bounded JSON framing, protocol validation, readiness and
  explicit command whitelist. It emits `command_received(type, id, payload)`;
  it owns no inventory, progression, controller or persistent state.
- `ui_command_dispatcher.gd`: client application boundary. Explicitly registered
  validators/handlers consume commands; it retains the latest small domain
  sections for snapshots. No reflection, NodePath dispatch or game-wide bus.
- `ts/protocol.ts`, `bridge.ts`, `store.ts`: typed, dependency-free browser framing,
  correlated requests and disposable domain state. `web/index.html` is a blank
  transparent shell, not a new gameplay screen.
- `source/client/ui_web/test/web_bridge.test.mts` and `tests/web_ui_bridge.gd`: small headless
  transport/application contracts. The standalone mock and diagnostic host are
  retired; no browser layout fixture is part of the default suite.

A client composition root creates host/bridge/dispatcher nodes and connects:

```gdscript
host.message_received.connect(bridge.receive)
host.navigation_started.connect(bridge.reset_transport)
bridge.outgoing.connect(host.send)
bridge.interactive_regions_received.connect(host.update_interactive_regions)
dispatcher.attach(bridge)
# Register only implemented commands, with exact payload validation.
dispatcher.register_command("inventory.move_item", validate_move, handle_move)
dispatcher.set_domain("inventory", current_inventory)
host.open()
```

Set host anchors to full rect under the client CanvasLayer. Configure a bundled
`res://...html` entry before opening; no user-provided URL is accepted. Register
handlers and seed domain sections before opening so first readiness gets complete
current state. Application controllers receive server-authoritative state and
update the dispatcher. The client copy is authoritative for web presentation;
this does not transfer gameplay/economy authority from World Server to the client.
The mock validates locally only to test the UI boundary.

A handler returns `{ok: bool, error?: String}` and independently publishes a
committed/reconciled domain state. No empty future controllers are supplied.
Only implemented commands are allowed. Actual production inventory commands
still require their existing server validation; the fixture is not that system.

## Protocol v1

Every message is a JSON object with exactly these fields:

```json
{"v":1,"type":"inventory.move_item","id":"req-123","payload":{"id":"potion","x":1,"y":1,"revision":1}}
```

`v`, `type`, and object `payload` are required. `id` is required on commands and
results, absent on lifecycle/state messages. IDs are nonempty strings up to 80
characters; browser IDs combine a per-document UUID/epoch and increasing counter.
Both sides reject malformed JSON, unknown versions, non-object payloads,
unexpected envelope fields, malformed IDs and messages over **16,384 UTF-8 bytes**.
There is no method name, node path, code string or system access command.

The bridge rejects unknown commands and commands before readiness without
executing a handler. A registered command with invalid payload receives a
correlated `{ok:false,error:"payload"}` result. Its validator checks the command's
exact fields/types; the mock requires precisely item ID, integer x/y and revision.
Bounds, overlap, stale revisions and item existence are application validation.
Unsupported framing/versions cannot be answered safely and are dropped with a
local `rejected` signal. There is no protocol negotiation or v0 compatibility.

Results acknowledge a request; they never carry replacement game state:

```json
{"v":1,"type":"command.result","id":"req-123","payload":{"ok":true}}
{"v":1,"type":"inventory.updated","payload":{"columns":6,"rows":7,"revision":2,"items":[]}}
```

The fixture publishes authoritative inventory even on placement rejection so an
optimistic drag is restored. State and result are independent; screens must not
infer equipment/wallet/inventory from the result. Unknown, duplicate or late
result IDs are ignored. Invalid result payloads cannot resolve a request. Timeout
is three seconds by default and clears pending state; it does **not** cancel a
command that Godot/server may already have processed. There are no automatic
command retries. Reconciliation comes from authoritative state/snapshot.

## Lifecycle and domain state

Listener installation precedes `ui.ready`:

```json
{"v":1,"type":"ui.ready","payload":{}}
{"v":1,"type":"ui.snapshot","payload":{"inventory":{"revision":2,"items":[]},"hud":{"ticks":15}}}
```

The dispatcher sends its complete current set of implemented domain sections on
every readiness event. Domains are `inventory`, `equipment`, `wallet`, `player`,
`hud`; absent domains are unimplemented, not fabricated empty controllers.
`inventory.updated`, `equipment.updated`, `wallet.updated`, `player.updated` and
`hud.updated` replace one complete small section. No patches or event replay.
Snapshot replaces the complete disposable JS store; domain sections must be
objects. Each real screen defines its own section schema before integration.

Reload and navigation reset bridge readiness and clear input regions/focus.
Reload/recreation creates a new document/bridge; old JS promises disappear.
Calling `ready()` in a live document explicitly rejects all its pending requests
with `reload` before requesting a full snapshot. Late results cannot restore
old state. Browser destruction/free and recreation keep dispatcher state in
Godot; hide/show keeps the same browser and layout, while releasing input.

This supports browser/document recreation, **not a proven in-process CEF crash
restart**. Upstream process-wide CEF initialization is not designed for repeated
shutdown/initialize cycles. There is no runtime restart hack. An application
restart recreates state from the normal client/server flow; dispatcher RAM is not
persistence. Native helper crash recovery and long-duration soak remain untested.

## Input ownership

HTML reports rectangles in CSS pixels, with viewport dimensions:

```json
{"v":1,"type":"ui.interactive_regions","payload":{"width":1280,"height":884,"regions":[{"id":"inventory-panel","x":870,"y":18,"w":390,"h":740}]}}
```

Region IDs must be unique, rectangles finite/nonnegative and within the reported
viewport; at most 64 rectangles, viewport at most 32768 per axis. Godot scales
these into browser-local coordinates. Host has no inventory coordinates and never
samples alpha pixels. `reportInteractiveRegions()` uses ResizeObserver, window
resize/scroll and requestAnimationFrame; dynamic screens must call its `refresh()`
after moving/hiding elements when size did not change, and `dispose()` on teardown.

In gameplay mode the host itself ignores mouse input. Before Godot GUI dispatch,
it sets the browser's `mouse_filter` to STOP inside reported interactive regions
and IGNORE outside. CefTexture's native `_gui_input` does the actual forwarding;
there is no synthetic CEF API forwarding in production. Pointer capture is latched
from an owned button press through release so dragging beyond a panel still reaches
Chromium. Wheel events never latch capture. Resize clears old rectangles until a
fresh layout report; an active drag retains capture through its release.

By default a click in a web region sets keyboard owner `web`. Pointer-only
compositions set `capture_keyboard_on_click=false` (Inventory does), retaining
gameplay keys while CEF handles mouse events. A click outside releases
browser/descendant IME-proxy focus and sets `gameplay`. Application calls
`host.set_modal(true)` to own pointer/keyboard across the viewport. Web cannot
unilaterally set modal ownership. Closing via `set_modal(false)`, hiding, reload
or destruction returns keyboard ownership to gameplay. Application can also
explicitly call `set_keyboard_owner("gameplay")` on UI close/actions.

CEF routes keys using its native focus/IME implementation. The host preserves an
already-focused editable proxy rather than grabbing browser focus on every mouse
click. Application shortcuts and gameplay controllers should use unhandled input
and/or `keyboard_owner_changed`/`keyboard_owner` to gate polling. Godot's global
`Input.is_action_pressed()` is not suppressed by GUI handling. This change does
not modify existing gameplay input to integrate a UI that is not installed there.

Place gameplay/native controls below the web layer; deliberately higher native
debug/tool controls can override hit testing. Touch, gamepad, IME, physical mouse,
DPI and alt-tab require a subsequent client/manual pass. Current foundation targets
screen-space mouse and keyboard; it does not claim a general input framework.

## Native API, security and isolation

Pinned plugin is [godot-cef v2.0.0](https://github.com/dsh0416/godot-cef/releases/tag/v2.0.0),
source `f8027f610c60a9740ceb8a263f144962ff6d5f62`, tested Godot 4.7.2 Windows x64.
The source/API were inspected, including native input_routing/focus_state and
scheme registration. Host alone uses CefTexture, popup/permission/background
properties, IPC, load signals and `reload()`. The old diagnostic host and its
`eval()` helpers were removed with the spike. The client bootstrap pins and
verifies the archive checksum; the historical record retains performance evidence.

Local HTML/CSS/JS only; CSP denies connect/frame/object/form/base access, no CDN,
web server or frontend dependencies. Native popup policy is block, permission
policy deny. Entry must be an existing bundled HTML file. Unexpected navigation
resets transport immediately and destroys the browser. **This is an after-start
guard, not a network firewall**: v2.0.0 exposes no public synchronous navigation
veto. No insecure-content, certificate-ignore or web-security-disable switch is
added. There is no download/system/filesystem bridge.

Trusted bundled UI is the security boundary. Upstream disables CEF sandbox and
registers res/user schemes with `CSP_BYPASSING`, broad Godot resource/profile
access and Access-Control-Allow-Origin `*`. Thus CSP is useful against remote
fetch (tested), but must not be presented as confinement of local resources.
Do not load untrusted/mod/downloaded HTML into this runtime. Debug builds expose
local DevTools on 9229; a non-debug packaged client remains an adoption gate.

CEF is a standard GDExtension installed into `addons/godot_cef` by
`tools/cef_client/setup.py`, using the pinned v2.0.0 release and SHA-256 checksum.
The release payload stays ignored; the installer/version/hash are committed.
`.godot/cef-client/cache` stores the archive. The root project uses Vulkan Forward+,
a 1920×1080 design baseline, 1280×720 initial window and disabled canvas stretch.
No copied project or config is generated.

`ServerUbuntu` and `ServerWindows` exclude `addons/godot_cef/*` and bundled Web UI.
The same server preset serves gateway/master/world via `--mode`. Web/Android
also exclude CEF; this does not imply those legacy targets support the new UI.
The Windows client includes HTML/CSS/JS and original optional skin PNGs through
the existing export plugin (CEF cannot read Godot's imported `.ctex` textures).
Native CEF dependencies are declared in the upstream `.gdextension` manifest.

Export filters apply to exported packages only. Local `--headless --path .`
loads installed GDExtensions, including CEF's Vulkan hooks, but `WebUiHost`
rejects browser creation. Local smoke does not require installing CEF; it also
works when CEF is installed. No headless helper processes were observed.
See [addon setup and export checks](cef-addon-integration.md).

## Prototype validation

```powershell
& ./tests/run-smoke.ps1
# Bridge only, no CEF setup or browser:
& ./tests/run-web-ui.ps1
# Optional real two-client headless Inventory RPC regression:
& ./tests/run-web-inventory.ps1
```

Use the root client for milestone-level native UI checks. The default
suite asserts transport/application and persistence contracts, not exact DOM,
window dimensions, animation timing or screenshots. See [testing policy](../development/testing.md).

## Validation and limits

Current repeatable checks cover persistence and bridge contracts, optional
Inventory RPC integration and the client/server export boundary. See
[testing policy](../development/testing.md) and [addon integration](cef-addon-integration.md).
The renderer/input/lifecycle adoption evidence from the retired fixture is
preserved in historical validation records in Git history.

Recommendation remains **ADOPT WITH CAVEATS** for Windows Vulkan Forward+.
The [V0 pass](../world/visuals/visual-upgrade-v0.md) now covers native CEF lifecycle, synthetic
input/drag/camera orbit and real Shop/Upgrade/combat RPCs on First Region.
Full non-debug client packaging/launch, physical input/IME/DPI/alt-tab, helper
crash handling, long soak and target-device budgets remain release gates.
Non-Windows client runtime has not been validated. Resource-pack checks and
headless boot do not prove native rendering or a distributable executable.

Godot may send the fixed `ui.shortcut` event with `{key: "Escape"}` to the Web
presentation. It has no request ID and does not mutate domain state. Inventory
uses it to cancel carrying before requesting close while leaving gameplay keys
outside CEF. It is not an additional Web-to-Godot command.

## First gameplay screen

`CoreUiController` composes the host/bridge/dispatcher and domain adapters for
Spike 3D. `ItemUiAdapter` maps private UID/revision/placement/stat snapshots for
Inventory, Equipment and Storage, following [UI Contract v1](ui-contract.md).
Item intentions and close commands keep their existing wire format; NPC, Shop
and Upgrade have their own adapters. See [native composition ownership](core-ui.md#native-ui-composition-package-c).
Results await correlated World Server replies; results do not replace snapshots.
The dispatcher supports synchronous or awaited registered handlers.

I opens a right-anchored, draggable 5×9 inventory with four pages. A single
root `ui_scale` controls logical geometry independently of physical resolution.
The screen uses region-based ownership, with temporary full-screen pointer
ownership only while click-carrying. Closing releases focus and removes its
regions without hiding the global browser. Reload receives the current snapshot.
Client failures release input and show a technical UI-unavailable message.
Headless creates no browser or inventory panel; unsupported renderers show the
same technical message. Inventory has no native rendering fallback.

Use `tools/cef_client/run.ps1` to install/import and start the root game with CEF.
After setup, the same project can run directly from the editor or Godot CLI.
There is no staging refresh after source edits. The installer currently supplies
Windows x64 libraries; Linux/macOS client installation and full release packaging
remain separate verification gates.

CEF v2 queues IPC separately from load events and drains IPC first. The adapter
connects `ipc_message` with Godot's CONNECT_DEFERRED so navigation reset completes
before UI_READY is delivered, including when both arrive in one native batch.
This also keeps outbound snapshot IPC outside the native signal emission stack.
A headless contract fixture covers that event ordering. An isolated native Vulkan
Mobile probe confirmed eager startup, I-key opening, gameplay focus and a visible
Inventory DOM; it does not cover a full authenticated login or visual frame pacing.

Production inventory composition uses a pending-command map, not a shared active
command. Each RPC ID owns its result/timeout and unresolved requests are cancelled
on navigation, disconnect and teardown. The Web bridge keeps its existing request
correlation and UI_READY full-snapshot recovery.

Inventory and Equipment compose `UiWindow` and share `WindowManager` for
registration, active window/z-order, measured logical rectangles, viewport/uiScale,
initial/relative anchors and clamping. [Core UI](core-ui.md) owns shared drag,
capture, titlebar, close, lifecycle, tooltip geometry and semantic asset plumbing.
CEF and CSS presentation stay outside the authenticated inventory endpoint.

## Account Storage

B toggles Storage in the gameplay client and opens Inventory. Storage is shared
by characters of one account, with 15 columns, 9 rows and 2 pages. Access is free
and available via shortcut in this first stage; there is no NPC proximity rule.
HUD publishes `storage_open`; the `storage` domain/`storage.updated` carries the
same item presentation fields as Inventory with its own fixed grid validation.

`storage.transfer` has exact fields `id`, `revision`, `from`, `to`, `x`, `y`,
`page`, `quick`. Containers are `inventory` or `storage`; equipment cannot be
transferred directly. The client supplies an intention, never account identity.
The server derives account membership from the authenticated character. Quick
moves scan all destination pages for the first footprint that fits. Revisions,
foreign accounts, collisions and full containers are checked before committing.
`storage.close` takes an empty payload. State snapshots update views independently
of command acknowledgement, including rejection and stale revision recovery.

SQLite schema v16 adds `account_storage` placements, leaving existing bag and
equipment tables intact. Deposit removes the bag placement and adds account
placement atomically. While stored, the instance's character owner is provenance;
access belongs to the account placement. Withdrawal removes account placement,
assigns the receiving character and creates its bag placement in the same
revision transaction. Item identity, affixes, sockets, quantity and upgrades
remain unchanged. Active peers of the account in the same map get fresh snapshots;
other characters load the current shared state on entry. Foreign peers never
receive account contents.

Command input/results retain the existing 16 KiB boundary. Snapshot/domain
updates have a separate bounded 128 KiB output limit: the full 180 + 270 cell
presentation measured about 91 KiB with representative native display fields.
CEF still loads static local assets under the existing CSP; no preview controller
or fixture code is injected in Godot.

Inventory-only moves are excluded from Storage transfer commands/services and
retain the existing Inventory RPC/transaction. Storage is intentionally accessible
everywhere in this MVP. The client's `storage_opened` check is a UX guard, not
server authorization; future NPC/safe-zone/range restrictions must be enforced
at the World RPC. Opening Storage opens Inventory; closing Inventory closes both.

## Generic item activation

Inventory right-click sends `item.activate` with exactly `{id, revision}`.
The authenticated World RPC resolves ownership, current revision and the server
ItemDefinition's `primary_action`. Iron Sword declares EQUIP and delegates to
the existing atomic equipment transaction. NONE returns `no_action`; USE returns
`unsupported` until a real use action is implemented. Definitions default to NONE.
The action does not travel in UI snapshots and the Web controller only transports
the command. Explicit `equipment.equip` and `equipment.unequip` remain available.
Results, rate limiting and Inventory/Equipment snapshots use the existing command
path; a successful acknowledgement alone never changes browser domain state.

Shared production item gestures and screen drop policies are described in
[ItemDragRuntime v1](item-drag-runtime.md); the command wire format and server
authority remain unchanged.


`equipment.unequip` supports `{id, revision}` for automatic first-fitting receipt
and `{id, revision, x, y, page}` for exact Equipment-to-Inventory drops. All three
coordinates must be present together and pass bounded integer validation. World
checks the full footprint and occupancy inside the equipment transaction;
invalid/occupied exact targets are rejected without a first-free fallback.
Right-click Equipment uses automatic receipt; left click carries and drag/drop
selects an exact position. Inventory right-click remains `item.activate`.


## Neutral NPC services

The `npc` domain and explicit `npc.interact` / `npc.select_service` /
`npc.clear_service` / `npc.close` commands compose the Core UI service menu.
SHOP routes to the separate `shop` domain and `shop.open` / `shop.buy` commands;
Upgrade has an [atomic +0 → +1 flow](../gameplay/npc/npc-upgrade-ui.md) with server recipe/selection. Shop opens Inventory alongside it, with right-click
first-fit and exact/receive-area offer drops. See [NPC Shop](../gameplay/npc/npc-shop.md). World owns
content, interaction context, current range and service authorization. The browser
routes zero/one/many enabled services and restores current selection after reload.
See [NPC services](../gameplay/npc/npc-services.md) for content authoring, boundaries and tests.

## Upgrade slice

The dispatcher adds `upgrade` (authoritative recipe/candidate) and `npc_targets`
(client camera projection only) domains. Explicit commands are `upgrade.select`,
`upgrade.execute` and `npc.upgrade_item`; no client cost/stat/recipe mutation is
accepted. The world drop is an opening intent; selection/upgrade revalidate through
the same RPC path as the menu. `ui.ready` restores recipe/candidate state. See
[NPC Upgrade](../gameplay/npc/npc-upgrade-ui.md) for authority, transactions and scope.

## Native command lifecycle

`UiCommandSession` correlates native RPC request IDs, independently of browser
command IDs. Timeout is 2500 ms and does not undo a server commit or retry it.
Results never replace authoritative domain snapshots. Reload, disconnect, UI
failure and teardown cancel unresolved waits; the first terminal result wins.

`WebUiBridge` owns transport generation. Reset/navigation advances it; repeated
`ui.ready` only publishes the current snapshot. `UiCommandDispatcher` captures the
generation before awaiting a handler and suppresses its reply if navigation has
replaced the page. Thus a new page can reuse a browser command ID without receiving
an old page's result. The session has no browser generation dependency.
