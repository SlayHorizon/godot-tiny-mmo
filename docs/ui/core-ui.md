# Internal Core UI

Accepted 2026-10-09. This is Mandate's small CEF presentation layer, extracted
from the production Inventory and Equipment. It is an internal composition tool,
with no frontend framework or public SDK contract.

The production browser logic is maintained in TypeScript and emitted to the
static ES modules under `web/`. The production entry remains
`web/inventory/game.html` and `inventory/game.js`. See [build and test instructions](../source/client/ui_web/README.md).

## Ownership

- `source/client/ui_web/ts/core/`: domain-agnostic window shell, geometry,
  chrome primitives (`core/primitives/`), semantic assets (`core/assets/`)
  and window behavior (`core/window/`).
- `game-ui/`: item grid (`game-ui/items/`), item tooltip/icon/slot and equipment slot presentation.
  These components accept data and dimensions; they make no gameplay decisions.
- `screens/inventory/` and `screens/equipment/`: composition, page/pending state and item interaction policies,
  equipment layout, advisory placement and injected domain actions.
- `content/item-icons.ts`: resolver for item content identity.
- `skins/legacy.ts`: adapter for the optional, exact legacy PNG manifest.
  It is the only runtime module that knows its concrete staging paths.
- `inventory/game.ts`: application composition; it chooses the skin, supplies
  resolvers/actions, owns one manager and binds the existing Web bridge.

Ownership, revisions, equip eligibility, free-bag selection, transactions and
combat stats stay in their existing Godot/server domain. CEF emits intentions.
The definition's `icon_id` travels through the private snapshot; it is content
metadata, with no item-instance schema change.

## Window contract

Create a `UiWindow` with an application-owned `WindowManager`, a stable
`id`, title and callbacks. Append screen content to `contentRoot`. It owns
the section/chrome/titlebar,
close binding, shared lifecycle and region refresh hooks. A composed
`WindowDragController` owns pointer capture and coalesced dragging. It adds global
move/up listeners only during a drag and removes them on every termination.
`templates/ui-window.html` is compiled to a local static module by the build;
window construction performs no runtime fetch. The content wrapper uses
`display: contents` to preserve existing logical geometry. It composes
`UiTitlebar`/`UiButton`; it does not own screen state.
`canDrag` lets Inventory suppress window dragging while carrying an item.
`onCancel` clears screen transients on blur, pointer cancellation, hiding,
resize, scale changes and disposal. `onActivate` is a presentation callback;
activation does not request native keyboard ownership.

`WindowManager` registers IDs, tracks `activeWindowId` and bounded z-order,
owns viewport/scale and browser resize, and invalidates layout. Its window map,
viewport, scale, active ID and order are private. Getters expose read-only state;
`viewport` is also frozen at runtime. Use `has(id)` and `registeredCount` for
queries, and handles for normal screen operations. Registration
returns a `WindowHandle` with activate/place/move/resetPosition/dispose methods
and layout/activation hooks; it takes no renderer callbacks.
`WindowLayout` owns measurement, placement, clamping and manual positions.
Placement is either a viewport corner with an offset, or a relative target with
explicit side, alignment, gap and offset. An optional viewport fallback preserves
standalone placement before a relative target has ever been measured.
`setViewport(physicalViewport, scale)` handles snapshot/viewport changes;
`setScale(scale)` updates every registered root and re-clamps. Pointer-down
or focus inside a window raises its root; hidden windows cannot activate.
Application composition also explicitly activates a hidden-to-visible window.
Registration itself does not activate it.
Registration rejects duplicate/empty IDs. Relative placement uses measured
geometry and detects cycles. Manual positions survive domain updates. Hidden
neighbors retain their last measured size; never-measured neighbors use the
ordinary anchor fallback. Small viewports allow vertical scrolling without
changing slot size or item footprints.

Inventory supplies its right anchor and offset. Equipment supplies its relation
to the Inventory ID and the gap. The manager has no knowledge of their meanings.
Escape retains production policy: cancel carry first, then request Inventory
close while open, then Equipment close. Z-order does not change shortcut policy.

`refresh()` measures visible windows. Application composition refreshes only
windows whose visibility changed; scale/viewport changes invalidate all windows
through the manager. Inventory and Equipment updates render their own screen,
wallet updates only update currency, and player updates do no screen/layout work.
A full snapshot updates all relevant consumers. `inventory/domain-updates.ts`
owns this dispatch after the existing store/protocol validation. `onRegionsChanged` connects the shell to the existing
interactive-region reporter. Dispose screens/components before disposing their
manager/reporter. `UiWindow.dispose()` cancels capture/frames, removes its event
listeners, unregisters and removes its owned markup; a reporter cancels queued
reports on disposal. `WindowManager.dispose()` is terminal and idempotent;
subsequent mutations and live handle operations throw `Disposed WindowManager`.
Queries and repeated disposal remain safe. Manager disposal cancels transients
and removes every registration even if a cancellation listener throws; screens
can still dispose their owned markup afterwards.

The type contracts are grouped in `protocol/contracts.ts` (wire/snapshots/native
Window declarations), `core/window/window-types.ts` (geometry/registration),
`core/assets/types.ts` plus `skin-keys.ts` (semantic identifiers), and
`game-ui/item-types.ts` (item presentation). Runtime IPC validation remains in
`protocol.ts`; TypeScript types never replace those checks.

## Minimal primitives

`UiTitlebar`, `UiButton`, `UiTab`, `UiSlot`, `UiTooltip` and `UiCurrency` are small
composed primitives. `UiTooltip` accepts arbitrary DOM through `contentRoot`
and a logical anchor
through `showAt(point)`. It flips/clamps using the manager's physical viewport
and scale. `game-ui/items/item-tooltip.ts` supplies the item name/description
adapter. The shared [item tooltip](item-tooltips.md) renders presentation sections,
rarity colours and held-Alt affix metadata across Inventory, Equipment, Storage and Shop.
Currency takes its label and semantic
icon ID; its value and domain actions stay in the screen. Buttons/tabs/currency
subscriptions have explicit disposal. Shared base/chrome CSS is `core/core.css`.

`UiItemGrid`, `UiItemSlot` and `UiEquipmentSlot` live in `game-ui/` with
`components.css`. ItemGrid takes `{columns, rows, items}` and a factory for
positioned items
(`x`, `y`, `height`). It has no page, carry, transfer or domain-state contract;
Inventory filters its own page before rendering. ItemSlot accepts only
`id/name/icon_id/height/quantity`, without revision or inventory coordinates.
EquipmentSlot takes its rectangle and enabled state
from the screen. Equipment's silhouette and slot coordinates remain its own
composition. Missing item images fall back to the item label without losing
quantity. There are no hotbar/status widgets until a real screen needs them.

## Skin and icons

`skinKeys` and `uiIconDomains` are readonly literal catalogs; their TypeScript
identifier unions are derived from those arrays. There is no parallel type list.
A skin supplies only `assets` keyed by semantics: `window.frame`,
`window.frame.corner.tl` (tr/br/bl), `window.frame.edge.top` (bottom/left/right),
`window.title`, `button.close.normal/hover/pressed`, `slot.normal`,
`tab.normal/active`, `currency.yang`, and `equipment.background`.
The latter is a decoration, not the Equipment slot layout. Components use
semantic CSS variables. No component/view contains legacy asset paths or atlas
coordinates. `applySkin(document.documentElement, skin, {baseUrl})` probes images,
uses CSS fallback on missing/broken files and clears stale assets during replacement.
Missing close hover/pressed assets fall back to the normal image; a missing normal
image retains the text close button. Geometry keys are ignored.

`uiIcons` is the global `UiIconRegistry`. It resolves IDs such as
`currencies.yang`, `skills.<id>`, `actions.<id>`, `buffs.<id>`, `debuffs.<id>`,
`status.<id>`, `quests.<id>` and `glyphs.<id>`. Only these namespaces are accepted.
`uiIcons.replace({currencies: {yang: 'coin.png'}, skills: {}}, baseUrl)` replaces
presentation assets; subscribers such as Currency refresh without view changes.
The current implementation registers the real Yang icon. Other namespaces are
available for real content, without invented placeholder libraries.

`ItemIconResolver` separately resolves `ItemDefinition.icon_id`. Pass
`resolveItemIcon` to item screens/components. Item icons never enter the global
UI registry. At startup the legacy adapter supplies three separate values:
skin assets, UI icon groups and item icon content. New staging manifests export
`skin`, `uiIcons` and `itemIcons`; the adapter also supports existing ignored
manifests. Exact legacy PNGs remain ignored and byte-identical when staged.

Skin replacement occurs in application composition: apply the new semantic skin,
replace UI icon groups and select item content as appropriate. Inventory and
Equipment require no edits. CSS fallback works in a clean checkout.

## Storage acceptance fixture

[storage.fixture.mts](../source/client/ui_web/test/storage.fixture.mts) is an
executable, typed example used by both headless contracts and the browser test.
It composes `UiWindow`, `UiItemGrid`, `UiItemSlot` and `ItemTooltip`. Its screen
function declares its window, creates the grid/tooltip and binds state/actions; it adds
no drag, capture, clamp, scale, z-order, tooltip-position or skin implementation.
The fixture has its own item model, without inventory pages or revisions.

The application owns the manager/resolvers and interactive-region reporter.
A caller binds domain state and actions:

```ts
const storage = mountStorageFixture(root, {
  manager, resolveItemIcon,
  onClose: closeStorage,
  onItemAction: selectStoredItem,
  onRegionsChanged: () => regions?.refresh()
});
regions = reportInteractiveRegions(bridge, storage.regions);
storage.setState({columns: 4, rows: 5, items: storageItems});
```

The default headless test exercises state replacement, injected actions,
tooltip content/cancellation, shared drag, activation, scale/clamp, region hooks,
hiding, close and disposal, including item-to-empty-cell tooltip movement. The opt-in browser test loads the same compiled
fixture alongside the production page and checks real DOM interactions,
region reporting, capture, resize/scale and cleanup with both skins.

Storage remains a test fixture, served only by the opt-in test server and
excluded from game exports. This work adds no Storage entrypoint, native command,
gameplay or backend. Future carry/transfer eligibility belongs to that screen.

## Verification

Each implementation step ran `git diff --check` and `tests/run-smoke.ps1` before
its local topic merge. Default smoke includes durable window lifecycle,
activation/registration, scale/resize, tooltip bounds, skin fallback/replacement,
icon namespace separation, item fallback and region-reporter disposal contracts.
It requires no browser, server, account, port or downloaded package.

`tests/run-web-inventory.ps1` also passed after icon metadata crossed the existing
snapshot boundary: real server and two clients exercised move/equip/unequip,
revision/ownership rejections, stats and persistence.

The opt-in `tests/run-core-ui-browser.ps1` takes `-PlaywrightModule` (an installed
module directory), `-BrowserExecutable` and optionally `-NodeExecutable`. It
uses a temporary loopback server and an installed headless Chromium browser,
without downloading dependencies or creating accounts. It loads the actual
production page with a controlled IPC fixture, checks legacy and unavailable-skin
fallback, command payloads, rejected-result behavior, click carry across pages,
tall-item drag/drop, capture/z-order, bounds across the UI Contract matrix,
skin replacement and a composed third window. It asserts no pixels, exact DOM
tree, animation timing or combat balance and is outside default smoke.

Headless Edge passed this milestone check. These results do not establish native
CEF transparency/input routing, Vulkan rendering or authenticated live-session
visual behavior; use the root client for that manual milestone check.

## Cleanup verification and formatting

The cleanup adds six focused runtime tests using emitted JS and real screen
composition: read-only/terminal manager state, disposal during captured drag,
selective domain dispatch, opening activation/z-order, malformed Inventory then
valid Wallet rendering, and Storage tooltip hiding over an empty cell. These run
with the existing Web UI suites in default smoke (40 tests total). The browser
fixture also checks item-to-empty-cell tooltip movement with both skins.

Pinned development-only Prettier formats Core UI TypeScript, screen/composition
modules and the cleanup/Storage fixtures. Run `npm run format` before rebuilding
static JS and `npm run format:check` to verify; CI enforces the latter. Generated
template source is excluded. Existing strict TypeScript checks remain the
correctness gate; this adds no bundler, runtime dependency or event framework.

## Daily browser development

Run `npm --prefix source/client/ui_web run dev` from the repository root and
open `http://127.0.0.1:4173/`. Production UI renders in an iframe with development
fixture IPC, the same Core UI, screen composition, assets and production CSP.
The surrounding development panel supplies fixture state, visibility, scale,
Wallet changes and command results/logs. TypeScript watches files; reload after
compilation. No Godot, browser automation package or live backend is required.

This checks presentation and composition. Native CEF embedding, focus/input
handoff, IPC transport, real settings/snapshots and server effects remain Godot
integration checks. See the [preview workflow](../source/client/ui_web/README.md#browser-development-without-godot).

## Storage integration

The production entrypoint mounts Inventory, Equipment and two-page 15×9 Storage.
Storage composes UiWindow, UiTab, UiItemGrid, UiItemSlot and ItemTooltip; it owns
its page selection and typed snapshot while actions and icons are injected.
Window geometry, scale, clamp, z-order and interactive regions stay shared.
On narrow viewports the Storage frame fits and the grid scrolls horizontally.

Inventory, Storage and Equipment use one [ItemDragRuntime](item-drag-runtime.md).
Screens own their sources and drop policies; the runtime owns only gestures,
ghost, hit testing and preview cleanup. The former Inventory-local carry and
Inventory/Storage transfer controller have been removed. Inventory-only moves
retain their original command; slot drops use explicit Equipment commands.

The fixture host supplies domain snapshots and handles the same bridge commands.
Its pure fixture transfer operation validates revisions and footprints; the
actual server validates account access and executes an immediate SQL transaction.
See [Storage contract](web-ui.md#account-storage) for persistence and access.
Default tests cover bounded Storage validation, last-valid state isolation, full
containers, same-account withdrawal, foreign access, revision rejection, rollback
and reopen. Extended Web Inventory tests exercise bridge/RPC/SQLite deposit and
withdrawal; browser tests exercise the shared production gestures.

Inventory-only moves use the existing `inventory.move_item` / `move_bag_item`
path even while Storage is open. Storage services reject inventory-to-inventory.
Storage operation status is exposed through `setStatus`, separate from capacity.
There is one StorageSnapshot contract in protocol/contracts.ts, with geometry
constants in screens/storage/storage-model.ts. `storage_open => inventory_open`
is enforced by the native composition and fixture host; invalid HUD snapshots
are rejected at the presentation boundary. Closing Inventory closes Storage.
See [the runtime contract](item-drag-runtime.md) for receiving semantics and future purchase invariants.

## Native UI composition (Package C)

Package C extracts Godot client responsibilities under `source/client/ui_web/`.
The TypeScript screens/Core UI and production DOM/gestures retain their owners.

- `CoreUiController` owns composition, open/close policy, I/B/Escape, scale/viewport,
  keyboard/pointer ownership, Alt/focus, camera capture and UI failure fallback.
  Its `interact_npc()` coordinates NPC interact → exact service → Upgrade select;
  reload/disconnect/failure/teardown prevents subsequent steps of a cancelled flow.
- `UiCommandSession` owns native IDs, pending endpoint replies, timeout/cancellation.
  It is RefCounted, receives SceneTree explicitly for a wait, and has no CEF/domain
  or browser generation knowledge. Closing it rejects further native requests.
- `NpcDropTargetProjector` projects explicit camera/viewport/NPC inputs and resolves
  Upgrade recipe metadata. The composition keeps the 100 ms cadence/cache and the
  server revalidates every intention. The projector has no tick or command state.
- `ItemUiAdapter` shares item/tooltip mapping and commands across Inventory,
  Equipment and Storage. `NpcUiAdapter`, `UpgradeUiAdapter`, `ShopUiAdapter` bind
  only their domains. They receive concrete endpoint/dispatcher/session/tree
  dependencies; they hold no second snapshot cache and no whole-world reference.
  Pure identity/service validators may be reused. No adapter calls another
  domain's command; Shop/NPC state is observed by composition for window policy.
- Wallet stays a direct domain publication. No adapter base/registry or per-window
  focus/shortcut/lifecycle manager was introduced.

Failure/teardown stops dispatch, closes pending requests, disconnects bindings to
endpoints/Client/settings/camera, releases input and destroys the browser.
The controller's Script UID and the existing `WebInventory` node path are retained;
RPC endpoint paths, authority/channels and browser messages are unchanged.

Verification: existing smoke (10 Godot + 74 Web UI), bridge generation regression,
architecture guard/contracts, two-client Web Inventory/NPC/Upgrade/Shop, real Edge
Core UI/preview and Shop/Upgrade browser suites with legacy skin and CSS fallback.
The existing Upgrade browser fixture now waits for the observable +1 presentation
instead of assuming forging ends in a single frame; production UI is unchanged.
Native Godot/CEF routing and Vulkan/manual interaction acceptance remain pending.
