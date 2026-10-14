# ItemDragRuntime v1

The production entrypoint composes one ItemDragRuntime with Inventory, Storage
and Equipment. The runtime in `ts/game-ui/drag/` owns gesture lifecycle only:
one session, pointer identity/capture, a logical 3px threshold, grab offset,
click carry, drag carry, ghost, hit testing, preview cleanup and cancellation.
It never reads item definitions, domain state or command names.

`ItemDragPayload.subject` is unknown. A source supplies its opaque subject and a
presentation callback using the existing item icon renderer. The generic target
registration retains its own typed preview data through a closure; runtime does
not inspect it or assert a target-data type. Preview visuals specify an element
and parent; runtime mounts and removes them. Actual geometry belongs to policies.
The default tests exercise a catalog-offer-shaped subject without implementing a
shop or changing the runtime to recognize offers.

## Current screen policies

- Inventory sources expose owned bag items. Right-click remains `item.activate`
  with only id/revision. Its grid policy submits exact `inventory.move_item`
  coordinates; an invalid selected cell never falls back to a free cell.
- Storage sources/target preserve exact deposit, withdrawal and internal moves
  through `storage.transfer`. Ctrl-click deposit/withdrawal uses `quick: true`
  outside drag gestures. Capacity and operation status remain separate.
- Equipment uses real slot elements, with a whole-slot green/red highlight.
  Only the currently implemented weapon slot accepts Inventory drops and sends
  `equipment.equip`. Definition/slot compatibility is checked by World; the
  preview is advisory. Direct Storage-to-Equipment is rejected.
- Equipped weapons can be dragged into Inventory through `equipment.unequip`.
  Drag supplies exact `x/y/page` and uses the normal footprint preview. The World
  validates that exact position inside the equipment transaction, with no free-cell
  fallback. Right-click/keyboard unequip omits coordinates and receives at the
  first fitting position. Short left-click latches the equipped item for carry.

Inventory's `receiveFromStorage(item, requestedPosition?)` API distinguishes
exact placement from automatic receiving. Target drops supply a position;
Ctrl-click withdrawal supplies none. Future subject handling belongs in target
policies, without feature routing inside the runtime or composition root.
`firstFittingPlacement` shares advisory footprint checks with the preview host;
it is not server authorization.

NPC Shop offers use `NpcShopOfferDragSubject` and their presentation footprint;
there is no owned item UID/revision until purchase commits. Inventory's deeper grid
is the exact target. The content surface outside the grid receives automatically
at first fit. Both paths send only NPC/service/offer IDs and optional coordinates;
invalid exact drops never become automatic buys. ItemDragRuntime is unchanged.

## Lifecycle and authority

All source, target and control registrations have disposable handles. Screens
unregister sources before repainting and registrations before disposing their
shells. A latched payload can survive page changes after releasing its DOM
source; the runtime retains no detached node or source callback. Unexpected
removed DOM is pruned on interaction. Headers cancel carry; tabs preserve a
latched carry while invalidating its old preview.

Escape/right-click cancel before screen actions. Blur, resize, pointer cancel,
lost capture and scale changes cancel too. Ghost and carry-surface use fixed
viewport geometry; logical grab offsets are converted using the current scale.
The carry-surface is included in interactive-region reporting for CEF input.
Disposal removes listeners/DOM, is idempotent and prevents queued drop dispatch.

Drop clears the gesture immediately and awaits the policy action. Command
results do not place items optimistically. Only validated domain snapshots
replace screen state. Relevant domain/HUD updates cancel stale carries; unrelated
wallet updates preserve the gesture. Native bridge validation accepts either
the two-field automatic unequip payload or all five fields for an exact placement; partial coordinates are rejected.
The same command correlation and server ownership/revision checks apply. Exact
unequip validates footprint/occupancy in the existing equipment transaction.

## Authoritative Inventory receiving reuse point

`ItemStoreSqlite.resolve_inventory_position(owner, height, requested_position = -1,
excluded = [])` shares transactional occupancy and `InventoryGrid.cells`/`fits`.
It resolves only: it does not reserve cells or start/commit a transaction. Call it
inside the operation's `BEGIN IMMEDIATE` on the same connection as its writes.

- Requested position: require that exact valid position; never silently relocate.
- No position (`-1`): find the first fitting position, or `inventory_full`.
- Invalid footprint: `request`; occupied exact target: `occupied`; read failure: `storage`.

Inventory moves exclude their own UID. Unequip and Storage withdrawal reuse this
helper; existing adapters preserve `bag_full` and Storage `full` wire errors.
Pickup and equipment swaps reuse it through `_free_bag_position`.
`receive_item_in_transaction` resolves and inserts a new instance/placement within
the caller's transaction; it never commits independently.

## Purchase invariant

NPC Shop now validates Inventory capacity inside the same
authoritative transaction that charges the buyer. Failure to place must return
`inventory_full` and must not charge the player.

An NPC purchase must atomically validate/commit offer, quantity, currency,
Inventory capacity, item creation and placement. Current NPC Shop stock is infinite;
finite stock would also belong in that transaction.
A Player Shop purchase must atomically validate/commit the live listing, buyer
currency, Inventory capacity, ownership transfer, buyer placement, seller payment
and listing removal/reduction. Existing Storage errors/wire format are preserved;
NPC Shop offers/RPC and the CEF view are implemented; see [NPC Shop](npc-shop.md).
`WalletStoreSqlite.spend_in_transaction`
applies pending income and spends without committing. The purchase caller begins
one transaction, validates the authoritative offer/price, resolves capacity, spends,
creates/transfers and places the item, then commits. Every failed result rolls back.
Only after commit may World publish the item and update RAM wallet/pending delta.
Never use standalone `spend()` followed by an item transaction. The default SQLite
wallet and Shop suites compose these production helpers and verify `inventory_full` without
charge, exact rejection, insufficient funds, write-failure rollback and reopen.

## Verification

Default smoke includes `item_drag.test.mts` against generated production JS:
opaque subjects/data, single session, pending drop, capture/scale, cancellation,
registration cleanup, page repaint, all current policy routes and rejection.
A lightweight source guard excludes feature routing and server command knowledge
from ItemDragRuntime. Optional real-browser checks cover actual hit testing,
slot targets, exact coordinates, pages, scaled dragging, Ctrl-click, activation,
preview teardown and server rejection with both legacy skin and CSS fallback.
Native CEF embedding/focus handoff remains a separate manual integration check.
