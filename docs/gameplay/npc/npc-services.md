# Neutral NPC interaction and service foundation

Implemented 2026-10-10. Neutral NPCs expose declarative services. They do not own
Shop, Upgrade, Storage or Quest execution. The foundation adds no database schema;
the separate [NPC Shop](npc-shop.md) domain now owns purchases and the Shop view.

## Static content

- `source/common/gameplay/npcs/domain/`: `NpcDefinition`, `NpcServiceDefinition`,
  the registry and `blacksmith.tres`.
- `source/common/gameplay/shops/domain/`: `ShopDefinition`, `ShopOfferDefinition`,
  the registry and `blacksmith_weapon_shop.tres`. These are separate from legacy
  upstream shop resources and use current ItemDefinitions.
- Service kinds are serialized explicitly: SHOP=0, UPGRADE=1, STORAGE=2, QUEST=3.
  Never derive kinds from UI text or reorder those values.

The Blacksmith exposes `upgrade` → `basic_upgrade` and `weapon_shop` →
`blacksmith_weapon_shop`. The shop contains one infinite-stock Iron Sword offer
(quantity 1, price 1000 Yang). Edit prices, offers and assignments in `.tres`.
The shop also sells Upgrade Ore (one material for 100 Yang). Both are registered
production item definitions.

Loaded definition resources are treated as immutable shared content. Validation
rejects malformed IDs, duplicate service/offer IDs, missing item/shop references,
invalid quantities/prices, unknown currencies/kinds and invalid interaction radii.
`basic_upgrade` resolves a validated UpgradeDefinition and its atomic
[+0 → +1 flow](npc-upgrade-ui.md). `account_storage` remains an explicit entry point. No Quest content exists yet, so an
unresolved QUEST reference is rejected until that domain authors its content.

## World and authority

`NeutralNpc3D` separates `definition_id=blacksmith` from the map-scoped
`instance_id=spike-blacksmith-01`. A shared development scene is composed on client
and server at (-7, 0, 6), with a capsule placeholder visual and name label. The
`visual_id` is content metadata; a final model resolver is deferred. This fixture
is static content; dynamic NPC spawn/transform replication is not implemented.
NPCs use collision layer 8 for picking, outside the combat mob layer.

Click the Blacksmith to approach along the arena navmesh and interact on arrival,
or press **N** within 3 m. Client steering sends ordinary bounded movement inputs;
server physics and the existing range checks still authorize the interaction.
Arrival uses the latest server position and a small range margin, then stops and
sends one request. WASD, attack/autoattack, selecting a mob, Escape, options,
loss of focus, death or an unavailable NPC cancel the approach. A new NPC click
replaces the route. An unreachable path never falls back to walking through a
wall; the approach expires after 15 seconds. Existing E item pickup and B global
account Storage remain unchanged.

`NpcInteraction3D` lives under the authenticated map RPC path. It resolves the
stable instance ID against its own actor registry and validates the server's
player, map parent, interactable flag, content and current distance. It stores a
private runtime `NpcInteractionContext` per peer, with instance/definition IDs
and the currently selected service. Nothing is persisted for this context.

Service domains call:

```gdscript
var authorization = world.npc_endpoint.resolve_npc_service(
    peer_id, npc_instance_id, service_id, NpcServiceDefinition.Kind.SHOP)
if not authorization.ok:
    return authorization
var shop = ShopDefinitions.get_definition(authorization.content_ref)
# Domain-owned transaction follows; service selection is not an authorization receipt.
```

The resolver checks the active interaction, current map/range, instance/definition,
service presence/kind and availability, and returns the authoritative Resource and
content_ref. Revalidate on every economically significant operation. Currency,
receiving capacity and mutations belong in the eventual atomic domain transaction.
There is no generic service executor or client-supplied content_ref.

Explicit close, peer removal, NPC teardown and world teardown clear context.
A 0.25-second runtime check invalidates out-of-range contexts and publishes changed
availability only; operations still check range immediately. `disabled_services`
on the actor provides a minimal runtime availability hook. It is not quest logic.

## CEF composition

`npc.interact`, `npc.select_service`, `npc.clear_service` and `npc.close` use explicit validators and
the existing per-request correlation. World → Godot controller → WebUiBridge →
DomainStore delivers the `npc` domain. `ui.ready` reloads its current snapshot.
No NodePath, domain Resource or content_ref is accepted from Web UI.

Snapshots contain active, NPC identity/name, ordered service ID/kind/label/iconId/
enabled fields and selectedServiceId. Priority then service ID determines stable
ordering. Icons are optional semantic metadata; this initial menu renders labels.
Services use compact label rows; Shop uses its separate item slot grid. Both
respect the common frame inset/bottom padding, clear of the legacy chrome.
The browser validates the entire domain before replacing last known valid state.

`screens/npc/npc-service-menu.ts` composes UiWindow and UiButton and exposes a typed
selection callback. `npc-interaction.ts` owns routing based on enabled services:
0 → no window, 1 → select directly, 2+ → menu. Selection hides the menu and routes
SHOP and UPGRADE to their feature windows. [Upgrade](npc-upgrade-ui.md) currently
provides the atomic +0 → +1 material/Yang flow. SHOP opens through its own revalidating `shop.open` command.
A failed feature open exposes the menu/status for retry. Close/Escape on a selected
service clears selection and returns to the menu for multi-service NPCs; another
close ends interaction. Single-service NPCs close directly. Reload restores current
selection and the published Shop snapshot.

`openService(service, context?)` accepts an optional preselected item intent and
shares the same callback as the menu. It is presentation data, not permission to
mutate that item. The Upgrade view selects Inventory items without relocating them. Dropping a
sword onto the Blacksmith approaches and selects through the same service flow.
`npc.clear_service` clears selection while retaining valid interaction context.

## Verification

```powershell
& ./tests/run-smoke.ps1
# Optional production RPC check; uses isolated SQLite and port 18098:
& ./tests/run-npc.ps1
```

The smoke adds one headless content/context fixture and four focused browser
contract tests: IDs/references, validation, instance identity, map/range checks,
close/teardown, service authorization, enabled-service routing, order/callback,
optional intent and atomic snapshot replacement. The optional two-client fixture
checks real RPCs, private snapshots, selection, close and stale range. Neither
requires opening a game window or writes to actual player stores.
