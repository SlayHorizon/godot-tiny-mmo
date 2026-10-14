# Inherited TinyMMO gameplay — deferred scope

The production First Region runtime lives in `common/gameplay/world3d/` and the
Mandate domains beside it. `client/gameplay/` contains client-only combat control.
The old TinyMMO native HUD/menu replacement was removed after graduation; see
earlier cleanup audit (recoverable in Git history).

The following code/content is retained for later work, without a folder-wide
rewrite or a blanket move into a legacy directory:

- `common/gameplay/combat/ability/` and the old 2D ability/status/VFX stack: inherited
  behavior/content; assess at the first real skill replacement.
- `common/gameplay/characters/`: inherited 2D Character/Player/NPC behaviors and
  sprite content. PlayerResource is still active auth/persistence state, so the
  directory is not entirely obsolete.
- `common/gameplay/items/`: inherited Item/Inventory/weapon resources beside the
  active ItemDefinition/ItemInstance/grid contracts. Retain until specific replacements.
- `common/gameplay/combat/`: also holds active basic-attack, trace and hit-reaction
  definitions/resolvers used by world3d. They remain production code.
- TinyMMO gateway/master/world, RPC/session/auth and persistence infrastructure
  remain the network foundation. Their inherited 2D paths are not a reason to
  restore the removed native UI mount.

References/content are evaluated individually. New First Region features should
use the graduated runtime and CEF UI; old definitions/VFX may be reused when a
concrete gameplay need establishes their contract. Skills, graphics and later
replacement work determine subsequent removals.
