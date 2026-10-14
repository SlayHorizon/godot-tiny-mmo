# Persistence policy - explicit state categories

Accepted following the user's review. The database is the persistence layer;
an active character's authoritative state lives in World Server memory. Do not
build a generic stats/event framework or autosave the entire profile for each change.

| State / operation | Runtime | Persistence |
| --- | --- | --- |
| XP, level, unspent attribute points | PlayerResource + separate dirty set | Approximately 60-second checkpoint, dirty characters only, one transaction |
| Equipment and combat stats | Minimal server cache restored on entry | Immediate item transaction; refresh cache after commit |
| Account Storage deposit/withdrawal | Account placement; receiving character on withdrawal | Immediate atomic item/placement/ownership/revision transaction |
| ItemInstance: pickup, equip/unequip, ownership, placement | Server validates intent | Immediate atomic persistence |
| Yang grinding income | Balance + pending delta + wallet dirty | Delta checkpoint around 30 seconds |
| Economically significant Yang spending | Check affordability against RAM | Immediate transaction including pending income, spending and economic mutation |
| Trade, upgrade, socket, reroll, crafting | Server-side result | Immediate transaction for all changed durable data |
| Materials/currencies acting as inventory items or stacks | Item/stack | Immediate transaction, including split/merge and creation/destruction |

## Current runtime and checkpoints

`WorldServer.runtime_equipment` stores active characters' equipment UIDs and
resulting stats by persistent ID. Application operations explicitly call
`InventoryEndpoint3D.refresh_authoritative_state()` on entry/repair or after a
committed item mutation. This prepares the private snapshot, equipment cache and
server weapon state before any notification/publication. `_send_state()` consumes
the prepared snapshot; publication never refreshes the authoritative combat cache.

Shop and Upgrade retain their existing application operation owners: the database
operation commits items/Yang and accepts wallet RAM, then the caller invokes
Inventory `accept_committed_change(peer_id)` (refresh/cache → its own fact), then
Currency `accept_committed_change(peer_id)` (its own fact after the already-accepted
wallet RAM). External callers never emit endpoint signals. Subscribers publish
already-prepared state; their registration order is not part of transaction correctness. Account Storage
prepares all affected on-map characters before the first notification.

Combat reads `attack` from runtime without querying on a swing. Failed equipment
changes affect neither placement nor attack; a missing valid snapshot invalidates
the cache so combat cannot use stale stats after a read error. Explicit
`resynchronize()` repairs entry/rejected/stale requests without emitting a
committed-change fact.

Mob death is a runtime event. DEAD state prevents repeated processing within the
current encounter. Contribution resolution and XP run in RAM; level-up and client
notification are immediate. There is no persistent KillEvent or kill ID for XP.
The ground item's UID still serves its economy-critical claim independently of progression.

`WorldDatabase.dirty_progression` is a separate set of character references.
Every 60 seconds, one transaction checkpoints only `level`, `experience` and
`available_attributes_points` for dirty characters. Success clears their dirty
flags; failure rolls back the batch and retains RAM/dirty state for retry.
No dirty characters means no transaction. Reentry reads the dirty resource to
avoid reverting unsaved progression.

Forced checkpoints run before session end, on disconnect and 3D map departure,
before existing instance transfer and during world save/shutdown/restart.
Graceful shutdown through the master is cancelled if a checkpoint fails.
Dirty references remain available for retry after disconnect. 3D process transfer
is not implemented; future handoff must wait for a successful checkpoint before
transferring ownership.

The older full-profile serializer still handles independent legacy data, normal
session saving and backups. XP ticks/kills do not invoke it. Its existing schedule
does not replace the progression checkpoint.

Schema v13 removes unused `kill_xp_rewards`, retaining XP fields and items.
A crash may lose soft progression since the last successful checkpoint: normally
about one minute, or back to the last successful save if the DB is unavailable.
Kills are not recovered from durable history. Item pickup/placement retain
immediate transactions and their own double-pickup protection.

## Yang: runtime wallet and ground currency

Spike 3D has a separate Yang wallet and runtime GroundCurrency. Dogs drop 30 Yang
with the same loot rights as their items. Auto-pickup works within 1.25 m; G picks
up within 2.5 m. There is no pet, persistent stack UID or per-drop DB record.
Legacy gold remains separate upstream state and is not migrated into the wallet.

Wallet fields are explicit: `wallet_balance`, `pending_currency_delta` and a
separate dirty set. Income changes RAM balance, accumulates a positive delta and
marks the wallet dirty. Every 30 seconds, checkpoints add the delta rather than
overwriting an older snapshot:

```sql
UPDATE wallets SET yang = yang + ? WHERE character_id = ?;
```

Successful commit clears pending delta; failure retains it for retry.
WorldDatabase's separate `dirty_wallet` checkpoint is not part of full
PlayerResource autosave or dirty progression.

The test button spends a fixed, server-defined 50 Yang. Critical spending checks
runtime affordability and commits pending income with the cost. The current test
only consumes currency. A future upgrade/purchase/trade must mutate durable
economic state in the same transaction; separate spend and item commits are not
acceptable. Example: DB 40000 + pending 30000 - cost 50000 = 20000 in one COMMIT.
After commit, runtime balance is 20000 and pending delta is zero. Rollback does
not consume pending income or publish item changes. Transactions must also prevent
negative balances. Old DB state must not reject a purchase affordable after pending income.

Inventory receiving uses `ItemStoreSqlite.resolve_inventory_position` in the
caller's transaction: explicit targets are exact, absent targets use first fit.
NPC Shop begins one transaction, validates its authoritative offer/price,
resolves capacity, uses `WalletStoreSqlite.spend_in_transaction`, creates and
places the item, then commits. `inventory_full` precedes wallet writes. Rollback must
retain RAM balance and pending income; publish/reset them only after commit. The
SQLite wallet and Shop smoke fixtures prove capacity/no-charge and item-write
rollback with these helpers. `ShopStoreSqlite.purchase` implements this flow;
`WorldDatabase.accept_committed_wallet_balance` synchronizes RAM only after commit.
The authenticated Shop RPC revalidates the selected NPC service on every purchase.
See [NPC Shop](../gameplay/npc/npc-shop.md).

GroundCurrency is a runtime entity: amount, loot rights/owner, position, expiry.
Pickup adds to the wallet and removes the entity. It creates no persistent
ItemInstance, durable UID or DB row for each small Yang stack. A tradable inventory
currency remains an item/stack with immediate persistence.

Wallet and progression have separate dirty sets and independent checkpoints.
Position dirty state is future work. Wallet loads on entry; logout/disconnect/
handoff/save/shutdown force both checkpoints. Failed wallet saving retains RAM
and pending delta even offline. Schema v14 adds `wallets`; PlayerResource's
serializer does not overwrite it. A crash may lose unsaved income and ground
currency, normally from a roughly 30-second window. Committed critical spending is durable.

## Tests

`run-progression` verifies runtime attack after equip, rollback without cache
mutation, zero inventory reads in both tested swings and stat restoration from
persistent equipment on entry. `run-xp` verifies multiple kills in RAM, no receipt
table, checkpointing, real disconnect, batch rollback, UPDATE of only three columns,
no clean-character writes and the accepted crash window. Full gateway/master/world
still tests logout/relog, level-up and the exact weapon UID.

`run-yang.ps1` checks delta checkpoints, no XP/profile writes for Yang, spend/batch
rollback, private HUD, rights/autoloot/pickup races, expiry, obstacles, RPC replay
and real disconnect. Full `pve_session` verifies combat/autoloot income and exact
balance after logout/relog.

## Package A reward boundary (2026-10-12)

Combat's death guard emits mob_died once. KillRewardResolver selects the existing
contribution winner and reward policy. It resolves the current PlayerResource via
MandateWorldServices before WorldDatabase.award_experience updates RAM/dirty
progression and emits the XP fact. The adapter uses pending_progression_player()
rather than accessing the dirty set; the combat endpoint only publishes its existing
XP RPC. Full progression runtime extraction remains P2.

GroundLootSystem owns live item drops, rights, expiry and pickup. Its application
operation prepares an ItemInstance from the authoritative drop and passes it to
ItemStoreSqlite.claim_ground_item(owner_id, drop_uid, item). SQL validates identity
and owner and commits receipt/item/placement together. It no longer generates a
sword or attack roll. Cache refresh and notification follow commit and ground
erase. The current live drop model still encodes a weapon attack roll (1..9),
weapon_attack presentation and an attack affix on pickup. It is not a generic item
payload yet; the first real non-weapon ground drop will drive that cleanup. The
prepared SQL claim can already accept non-weapons. No schema, checkpoint intervals
or per-kill durability were added.

## Visual world calendar

[Visual V2](../world/visuals/visual-upgrade-v2.md) derives the shared presentation calendar from a
fixed UTC/game epoch and advances it from monotonic server ticks. Restart recovers
the ongoing calendar without SQL or dirty checkpoints. Client synchronization
does not change combat/respawn/loot timers, progression checkpoint policy, or
immediate atomic item/economy transactions.
