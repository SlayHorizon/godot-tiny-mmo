# Blacksmith Upgrade vertical slice

Implemented 2026-10-10. Production Upgrade supports exactly **Iron Sword +0 → +1**,
with 100% success and one immediate atomic material/item/wallet transaction.
There is no failure, downgrade, destruction, pity, scroll or equipped-item upgrade.

## Playable flow

1. Buy one **Upgrade Ore** from Blacksmith → Weapon Shop (100 Yang).
2. Open Blacksmith → Upgrade and drag an Inventory Iron Sword +0 into the slot.
3. Inspect the server-provided cost: **1000 Yang + 1 Upgrade Ore, 100% success**.
4. Upgrade → Confirm. The authoritative snapshot displays the same sword UID at +1.

The costs are prototype content values, not balance decisions. Change the recipe
in `source/common/gameplay/upgrades/domain/basic_upgrade.tres`; the material is a
normal ItemInstance stack defined by `items/domain/upgrade_ore.tres` (limit 200).
Shop purchases create normal persistent material items; no login grant or schema
migration is added. A small local SVG is a temporary material icon.

Inventory sword → Upgrade slot only selects. The item retains its Inventory
placement and revision until the actual upgrade commit. Selection is server-owned
runtime presentation state, restored by `ui.ready` along with the current recipe.

Inventory sword → Blacksmith in the world enters the same flow with a
`preselectedItem` UID/revision intent plus the exact service ID. Godot resolves each
enabled Upgrade service through its content reference and supplies projected NPC
hit regions with NPC/service IDs and recipe item/from-level metadata;
they are active only during item carry, below UI windows, and independent of UI
scale. Drop requests an approach. After arrival the controller performs the normal
NPC interaction, selection of the exact matching service and Upgrade item selection
commands. No item is placed in a fictional container. Manual movement/Escape and the existing approach
cancellation rules stop the approach before it opens a service.

## Authority and persistence

`UpgradeDefinition` supplies stable recipe/item/material IDs, from/to levels,
Yang/material costs and success rate. Validation currently accepts only +0 → +1
and 100%. NPC service content references resolve through `UpgradeDefinitions`.

`Upgrade3D` lives under the authenticated world instance. Selection and execution
both revalidate NPC instance, map, current range, enabled Upgrade service and the
selected service. Execution accepts only NPC/service IDs and item UID/revision.
Prices, materials, levels and success are never supplied by JavaScript.

`UpgradeStoreSqlite` uses one `BEGIN IMMEDIATE` connection to recheck both placement
and item ownership, revision, Inventory location, definition, quantity, current
level and valid footprint. Materials come only from this character's Inventory;
Account Storage does not qualify. Multiple material stacks are consumed in UID
order. A partial stack decrements amount and increments revision; an exhausted
stack deletes both placement and item atomically.

The same transaction applies pending wallet income, spends Yang, updates the
sword's upgrade level/revision and commits. Any validation or SQL failure rolls
back all three economic changes. Runtime wallet balance/pending delta/dirty state
change only after commit. Old UID/revision commands and attempts to upgrade +1
again are rejected. Affixes, sockets and the sword's UID/placement remain intact.
No capacity is needed for a new item: the existing sword stays in its valid cells.

Selection publishes only the Upgrade snapshot. A stale selection also refreshes
Inventory/Equipment to repair its revision. Execution sends current Inventory/Equipment,
wallet and Upgrade snapshots after success or rejection. Inventory refresh also
updates the existing server runtime equipment/stat cache. The UI does not optimistically increment a level and disables
confirmation without the server candidate, required material or sufficient wallet.
An external inventory revision/placement change refreshes or clears the candidate.
Closing/leaving the service clears selection; server context invalidation still
applies. Reload retains the server selection, not an unconfirmed local action.

## UI and development preview

The existing CEF window, shared UiWindow, logical scale, item drag runtime,
confirmation and tooltips are reused. Production selection uses explicit
`definition_id` and `upgrade_level` metadata from the small native item presenter;
material labels no longer inherit sword +0 or fake Attack text. Production prompts
use the recipe item's content name. New selection clears previous execution feedback;
carry transitions clear world-target hover feedback.

`web/dev/upgrade.html` remains a separate visual +0…+9 preview, explicitly opting
into `devPreview` and mounting no real bridge/economy. Its illustrative costs and
local level increment are never used by production Upgrade.

## Verification and limits

```powershell
& ./tests/run-smoke.ps1
# Optional real production RPCs, isolated DB and two clients on port 18098:
& ./tests/run-upgrade.ps1
```

The small transaction fixture covers ownership/revision/placement, missing
material/funds, partial and exhausted stacks, fault-induced rollback after
consumption/spending, pending Yang, replay and database reopen. Two UI contracts
cover server-driven level changes/rejection/reload and queued world drop lifecycle.
The network fixture exercises private state, selection without relocation,
upgrade/refresh, another client, stale replay and changed NPC range.
These checks are headless. Native in-game CEF hit alignment, visual feel and the
complete drag → approach interaction still require a manual check after restarting
the client and World; automated checks do not claim Vulkan visual verification.

New characters receive 1500 Yang once at creation. Existing wallet balances are unchanged.
While Upgrade is open, right-clicking an Inventory item selects it through the
server Upgrade command instead of activating/equipping it. Items remain in Inventory.

Upgrade execution sends the server request immediately while the slot plays a
short forging effect. The Upgrade window holds its pre-upgrade presentation until
both the response and effect complete, then reveals success/failure. Inventory
and wallet updates are never delayed. Context loss/reload cancels the effect;
the server transaction continues independently and the next snapshot restores it.
