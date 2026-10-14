# C1 — authoritative ownership

**Status: Accepted (2026-10-14)**

This contract states the target authority boundaries for Economy V2. It does **not** claim that the current SQLite WorldDatabase has already been extracted into another process.

## Accepted ownership boundaries

| State / responsibility | Sole authority | World Process may keep |
| --- | --- | --- |
| Account Yang, balance and economic reserves | Realm Economy | Read-only/UI cache; local prototype pending-income behavior until C3 migration |
| Durable ItemInstance UID, ownership, inventory position/capacity, equipment, custody, revisions | Realm Economy | Versioned inventory/equipment view; derived combat stats |
| Shops, offers, Auction, Exchange, escrow, receipts and settled/pending shop revenue | Realm Economy | Request/UI views, never independently writable balances |
| Ordinary unclaimed ground item/ground Yang entities, loot rights, position, nearby eligibility, mob death | Hosting MapInstance/World Process | Authoritative local simulation and reservations until durable claim |
| Movement, combat, mob AI, health within instance | Hosting MapInstance/World Process | Authoritative runtime simulation |
| XP, character progression and quests | Character/progression domain (logical boundary; no dedicated service required yet) | Active authoritative RAM/dirty checkpoint state per current policy |
| Active player session, route, assigned instance and session epoch | Realm/session authority (logical boundary) | Verified local session identity and lease/epoch |

**Authority means the only domain allowed to make the final decision and commit its durable facts**. It does not imply a single Godot node, physical machine, SQL connection or worker thread.

- All characters of one account in the **same realm** use the same Yang wallet. Different realms, such as Season and Classic, have disjoint economic identities and balances.
- All channels, overflow layers, public dungeon copies and private party dungeons within a realm share that realm's economy. Instance/host identifiers must never select an independent wallet or shop ledger.
- Item ownership, placement, inventory capacity and equipment are one transactional domain with trade and Auction. A World simulation cannot create a spendable/tradable item merely by changing its cache.
- A normal world drop may be transient while unclaimed; only an authoritative, idempotently accepted Economy claim makes an item durable property of an account/character. Selected high-value dungeon rewards use the durable protected-manifest boundary defined in C3; ordinary drops remain transient.
- World verifies gameplay predicates (distance, loot rights, combat context, NPC proximity) for its own events. Economy verifies economic invariants (UID uniqueness, current custody/revisions, balances, placement/capacity, transaction/receipt uniqueness) and requires authenticated/authorized server provenance for grants. Client-supplied authority is never sufficient.
- World combat uses a **local snapshot** of equipment/derived stats; no SQL or Economy RPC on each hit. Successful equipment mutations update that cache only after the authoritative committed result. The snapshot cannot grant ownership.
- Unique items and critical economic mutations retain immediate durable, atomic commit semantics. Soft progression remains a separate checkpointed state category.

## Invariants and failure behavior

1. At most one authoritative owner/custody for a UID. A World crash, retry, handoff or duplicate pickup cannot create a second copy of a committed item.
2. No successful economic command is exposed as finalized before durable commit. A lost success response must be recoverable through stable operation identity, without double grant or double debit; details are C2/C3.
3. One account cannot spend the same Yang twice, including simultaneous characters/channels. A read/UI snapshot is never an authority for available balance.
4. A World cannot keep performing new authorized economic actions on behalf of a session after its ownership epoch has been revoked. Detailed session fencing is C5.
5. A temporary Economy outage may pause or reject durable actions while world simulation continues; it must not create uncommitted, usable items or money as a fallback.

## Current code and migration implications

- The prototype's godot-sqlite writer, WorldDatabase account-wallet RAM/pending delta, Market/Exchange transactions, UID custody and durable command receipts remain in place.
- Existing [persistence policy](../persistence-policy.md) is the **current runtime contract** until migration. In particular, its local pending Yang delta and world-side equipment cache are not retroactively invalidated by this future-state document.
- Future extraction should put the Economy API/domain boundary around working transaction semantics, not copy SQL calls or move SceneTree nodes into background threads. Both local SQLite and eventual PostgreSQL implementations must uphold the same externally visible invariants.
- Transition requires a plan for multi-World session authority, shared wallet ownership, migration of current pending-income behavior and versioned cache refresh, specified by C2–C5.

## Still open — not part of C1 approval

Exact command envelope/transport, batching protocol for soft Yang (not the accepted durability distinction), seller-claim overflow/limits (not the accepted collectable revenue model), handoff messages, snapshot revision granularity, PostgreSQL concurrency strategy and deployment topology belong to C2–C5 and implementation design.
