# Project direction — current technical and gameplay focus

**Updated 2026-10-14.** This is the short, current orientation document referenced by `AGENTS.md`. It is **not** a ledger of completed spike branches, a balance specification or permission to build a distributed service immediately.

## Current running prototype

- Godot 4.7.2; Gateway/Master/one World Process; SQLite persistence. **One process today** is not the same as the future multi-process topology.
- Server-authoritative 3D movement, hit/target resolution, mobs and respawns. Warrior basic combos have authored timing and combat geometry; combat uses RAM equipment-derived values and does not query SQL on every hit.
- Unique ItemInstances, item ownership/revisions, transactional pickup/inventory/equip and critical spend. XP/soft progress checkpoints and farming Yang batches remain covered by the [runtime persistence policy](../architecture/persistence-policy.md).
- First Region graybox with Metins, mixed mob packs and the Blacksmith NPC. [Gameplay index](../gameplay/README.md), [combat details](../gameplay/combat/README.md), [NPC](../gameplay/npc/README.md).
- TypeScript/CEF Inventory, Storage, NPC Shop/Upgrade and Core UI presentation. Godot remains the authority; the browser sends intentions. [UI index](../ui/README.md).
- Terrain3D V4 compatibility/adoption foundation exists, but authored maps and final visual polish are **not** completed. [World and visuals](../world/README.md).

The **Marketplace/Auction/Exchange** vertical slice exists on the open `shop` branch, not on the integrated `main` baseline at the time of this revision. It includes async SOCI Auction reads; do not claim its native/Linux gate is complete. See [implementation index](../implemented/README.md) and [remaining Shop product differences](marketplace-v2-gaps.md).

## Accepted direction; not all implemented

- One logical realm with **dynamic player-visible public channels per busy map**, optional invisible overflow, public/private dungeon MapInstances, and eventual multi-World placement on different machines. [World architecture ADR](../architecture/world-instance-architecture.md). This **supersedes** the older “hidden layers only, no selectable CH” draft.
- Season and Classic are independent realm economies; characters/accounts/Yang are realm-scoped. One active character per account per realm is the preferred model. [Economy C1–C5](../architecture/economy/README.md) defines future ownership, commands, transactions, snapshots and server-driven cancellable handoff. SQLite + one World remains the development runtime.
- Dense readable combat, viable solo classes, rewarding small parties, Metin-like upgrades and less repetitive consumable/lure friction. These are design directions, **not finalized numbers**. [Gameplay direction](gameplay-direction.md).
- Preserve physical ground loot and familiar trading. Selected valuable dungeon rewards may use manifest-backed protection and a limited 12-hour fallback stash; ordinary ground drops remain transient. C3 controls economic invariants; detailed contribution/loot balance is separate.
- Shop UI target: item can remain listed without a fixed buy-now price; withdrawing requires regular Inventory space; sales credit account-level `claimable_yang`. Built-in bidder/negotiation escrow is deferred. Current `shop` differs; see [delta](marketplace-v2-gaps.md).

## Immediate engineering priorities

1. Integrate the open `shop` / Auction PR with latest `main`, preserving tests and reviewed commits.
2. Harden Gateway pending request/session lifecycle and World RPC peer/instance admission.
3. Separate current World/Economy application boundary and transaction ownership **inside the existing runtime**; update Shop semantics in focused PRs with migration and regression proof.
4. Measure economic-write tick tails under dense combat and improve what evidence shows is slow; do not add threads or replace databases reflexively.
5. Prepare server-controlled CH transition rules/epoch handling internally; postpone cross-host Economy extraction until it is actually needed.

[Ordered technical hardening plan](../plans/architecture-hardening.md) and [testing policy](../development/testing.md) control these milestones. Keep changes reviewable, preserve legacy data or explicitly migrate it, and do not infer production readiness from a Windows-only fixture.

## Gameplay and visuals next

Once core economic integration and immediate trust-boundary fixes are stable, return to manual combat-density feel, authored Terrain3D First Region, vegetation, atmosphere, water/shore refinements and the first public dungeon loop. Do not treat historical V0–V4 plans as new work tickets. [Visual V4 evidence](../world/visuals/visual-upgrade-v4-terrain3d.md) records current plugin compatibility and editor limitations.

**Canonical precedence:** current code + persistence/testing docs describe the running baseline; newer Economy and World contracts define intended architecture. Earlier spike plans and superseded docs exist only in Git history.
