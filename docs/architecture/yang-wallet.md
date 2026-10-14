# Yang wallet - first slice

A dying dog drops an item and a separate 30 Yang. The amount is a placeholder.
GroundCurrency has only a local entity ID, amount, position, highest contributor's
loot rights, a 15-second reservation and a 120-second lifetime. It is not persisted
as ItemInstance or a SQLite ground claim. Duplicate death callbacks do not create
another reward.

Server-side auto-pickup runs every 0.2 seconds within 1.25 m. G picks up the nearest
Yang within 2.5 m. Both check player life, distance, line of sight, reservation and
expiry; the client supplies neither amount nor ownership. Public stacks can be
picked up only once. Full inventory does not block the wallet. There is no pet or
auto-pickup configuration yet.

WorldDatabase keeps `runtime_wallets` by persistent character ID:
`wallet_balance`, `pending_currency_delta` and a separate `dirty_wallet` set.
Income synchronously changes RAM and removes the ground stack without SQL.
The HUD receives only its owner's balance and public stack state, never other wallets.

Every 30 seconds, all dirty deltas are persisted in one transaction to `wallets`
(schema v14). UPDATE adds the delta to the existing balance. Commit clears pending
and dirty state; rollback retains them for retry. Clean intervals do not open a
transaction. Saving does not touch PlayerResource, inventory or progression.
Logout/disconnect, map departure, instance transfer and graceful save/shutdown
force a save. Failed offline state is retained and reused on reentry.
New characters start with 0 Yang; legacy gold is not transferred.

## Test critical spend

The HUD's test button spends a fixed, server-defined 50 Yang. This temporary
operation verifies persistence and gives no reward. RPC accepts only a sequence;
it validates session, life, replay and rate limit. Affordability uses RAM.
One store transaction applies pending income and subtracts the cost with a
nonnegative-balance condition. Runtime changes only after commit; rollback leaves
balance and pending income unchanged.

SQLite tests verify `40000 DB + 30000 pending - 50000 spend = 20000` and force an
error in the second UPDATE after applying pending income: the entire operation
rolls back. Future upgrades must include material consumption and item mutation
in that same commit. This slice adds no callbacks or generic transaction framework.

A crash may lose unsaved income since the last successful checkpoint (normally
about 30 seconds) and runtime ground currency. Committed spending and immediate
item transactions remain durable.

## Verification

`& .\tests\run-yang.ps1`: real SQLite and two RPC clients, autoloot, rights,
range/obstruction, expiry/death, pickup races, private balance/HUD, critical
spend/replay, delta checkpoints, batch rollback and real disconnect.
`-Preview` writes `.godot/verification/yang-preview.png`.

`tests/pve_session.tscn` through normal gateway/master/world verifies combat,
item pickup/equip, XP/level, Yang autoloot and exact balance after logout/relog.
Yang network tests share port 18098 with PvE/combat/progression/XP; run sequentially.
All state categories: [Persistence policy](persistence-policy.md).
