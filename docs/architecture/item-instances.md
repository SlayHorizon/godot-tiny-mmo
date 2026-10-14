# Item instances - 3D spike

Initial slice: 2026-10-07; inventory grid updated 2026-10-09. The new model works in Spike 3D through existing
gateway/master/world login. **I** opens the panel; I, Esc or its button closes it.
The CEF Inventory uses region-based input ownership; the old native panel has
been removed. Browser startup failures show a technical message; see [Inventory UI](inventory-ui-prototype.md).

## Model and implemented scope

`ItemDefinition` is a shared Resource with definition ID, name, slot, stack limit,
base stats, inventory height (1–3) and upgrade-level growth. It stores neither owner nor rolled bonuses.

`ItemInstance` describes one instance: UID, definition ID, persistent character
ID, quantity, upgrade level, affixes, sockets, version and bag/equipment placement.
UID is 16 random Crypto bytes encoded as 32 hex characters. Existing UIDs are read
from SQLite, not regenerated at login.

The character's first Spike entry grants a one-time technical starter set:

| Instance | Definition | Attack bonus | Weapon attack | Character attack when equipped |
| --- | --- | --- | --- | --- |
| First sword | `iron_sword` | +3 | 13 | 23 |
| Second sword | `iron_sword` | +7 | 17 | 27 |

Base character attack is 10. Starter bonuses are fixed for repeatable instance
separation tests. The bag has four 5×9 pages (180 cells); the Iron Sword occupies 1×3.
Equipment has one `weapon` slot. Schema v15 migrates old one-cell anchors
atomically; see [UI Contract v1](ui-contract.md).
Equipping another weapon uses the vacated position when its footprint fits,
otherwise the first free footprint. Unequip requires a free footprint. The panel abbreviates UIDs but sends the full
UID. The model persists +0...+9 upgrade levels and sockets; upgrading, socketing
and reroll actions are not implemented yet.

## Authoritative persistence and synchronization

WorldSchema **v10** adds three tables while preserving older data:

- `item_instances`: UID, owner, definition, quantity, upgrade, bonus/socket JSON
  and version.
- `item_placements`: UID, owner and exact position. Unique indexes protect each
  character's bag positions and equipment slots.
- `item_initializations`: durable starter-grant marker. An empty bag does not
  trigger another grant at login.

The old PlayerResource serializer does not write these tables. Legacy inventory
JSON and equipped weapons are not automatically imported. Tables have no foreign
key to `players` because legacy persistence uses `INSERT OR REPLACE`.
Initialization checks character existence; operations filter owner in both tables.
Future character deletion must explicitly clean up instances, placements and the
initialization marker.

The client sends only action, UID and expected version. The server obtains the
character ID from the authenticated RPC sender session, checks ownership/version/
slot and limits commands to one per 100 ms. `BEGIN IMMEDIATE` commits both weapon
placements and versions together; errors roll back the entire change. The snapshot
returns after the transaction; stats are server-calculated from stored instances.
At this initial stage there was no separate cache requiring a logout flush; the
later runtime equipment/stat cache follows [persistence policy](persistence-policy.md).

Only the owner receives full inventory. Other players get the equipped weapon's
definition ID and see a simple sword model attached to the capsule. New players
also receive existing players' weapon state. Attack is used by
[server-side 3D mob combat](pve-ground-loot.md).

The [first Item Progression Slice](item-progression.md) adds equipped-weapon
comparison, post-swap attack preview and new-loot marking. A found instance can
be equipped and retained with its stats after relog.

## Verification

```powershell
# Separate SQLite database; no running servers required.
& .\tests\run-items.ps1

# Requires normal gateway/master/world; creates two local guest accounts
# and test characters in their normal stores.
& .\tests\run-items.ps1 -WithSession

# Network/physics regression with a separate port and fixture sessions.
& .\tests\run-spike3d.ps1
```

All tests passed on the project's Godot 4.7.2:

- SQLite: distinct UIDs/bonuses, exact equip/swap, ownership, stale-version rejection,
  unequip, preserved legacy profile, isolation from old saves, identical state
  after reopening and no repeated starter grant.
- Injected SQL failure during weapon swap: both placements/versions revert;
  the next valid transaction succeeds.
- Two full-login clients: stats 23/27, specific UID selection, stale-version RPC
  rejection, visible weapons and identical UID/bonus/equipment/version after relog.
- Network/physics checks still pass for the server and two clients.
- All 871 source scripts/scenes/resources loaded without parse errors; the OpenGL
  panel/weapon preview was generated and inspected.

Logs/previews live in ignored `.godot/verification`. SQLite tests intentionally
trigger one SQL rollback error. Earlier Windows certificate-store and exit-resource
engine diagnostics remain.

## Next step

PvE mobs, server damage and new-instance pickup are described in the
[PvE slice](pve-ground-loot.md). Trade, upgrade and reroll should later reuse this
model and atomic instance operations.
