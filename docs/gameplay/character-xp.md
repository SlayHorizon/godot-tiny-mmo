# Character XP and levels - 3D spike

Status: 2026-10-07, branch `codex/character-xp`. Server-side XP on Wild Dog death,
level-up, HUD and persistence across relog. Combat and item parameters are unchanged.

## Rewards and levels

A Wild Dog awards 20 XP. The full reward goes to the character with the highest
actual damage contribution, as with loot reservation. Overkill does not increase
contribution; ties use the lower persistent character ID. The last hit does not
automatically take the reward. XP is granted on mob death regardless of item
pickup; hits and pickup alone do not award experience.

Reuse `PlayerResource.add_experience()` and the curve `70 x current level`.
Excess XP carries into the next level. Four dogs from zero yield 80 XP: level 2
and 10/140 XP. These are prototype values for later balancing. Existing unspent
attribute-point storage retains +3 per level; allocation is not available in this
3D slice and does not change attack or HP.

The HUD shows level, XP to the next level, a progress bar and a reward/level-up
notice for five seconds. The capsule's name label includes level. Levels are
public; exact XP progress is owner-only. The client cannot request XP grants,
experience amounts or an expected level.

## Persistence and idempotency

XP and level change immediately in the authoritative PlayerResource in RAM.
WorldDatabase marks character progression dirty and checkpoints dirty characters
approximately every 60 seconds in one transaction updating only level, experience
and unspent attribute points. Disconnect/logout, transfer and graceful shutdown
force a save. Unclaimed loot remains runtime state; XP checkpoints do not depend
on claiming it.

WorldSchema v13 removes the earlier `kill_xp_rewards` table. No kill history or
persistent kill ID is created. A mob's DEAD state prevents duplicate processing
of that death in the single authoritative World Server. A crash may lose soft
progression since the last checkpoint. Details and separation of items, XP and
wallet state: [persistence policy](persistence-policy.md).

## Verification

```powershell
& .\tests\run-xp.ps1
& .\tests\run-xp.ps1 -Preview
```

A server and two clients use isolated SQLite and port 18098. Run sequentially
with PvE, combat and item progression tests. The fixture lowers dog HP to shorten
the test without changing production attack or XP code.

Verified: highest contribution rather than last hit, actual damage excluding
overkill, no XP before death, duplicate death callback, multiple kills without DB
XP writes, level 1 -> 2 with 10 excess XP, private progression, public level, HUD,
no pickup XP, checkpoint/reopen and real disconnect with dirty progression.
Checkpoint tests cover batching, rollback, narrow UPDATE, forced save and the
accepted crash window without receipts. Markers: `CHECKPOINT_OK`, `XP_SERVER_OK`
and two `XP_CLIENT_OK`.

Full gateway/master/world sessions in `tests/pve_session.tscn` verify identical XP
and level after relog along with the picked-up/equipped ItemInstance. The
`--xp-levelup` variant fights to level 2 and verifies the level survives relog.
Item, PvE, combat, progression and movement regressions also passed. The generated
`character-xp-preview.png` in `.godot/verification` was visually inspected.

The checkpoint test intentionally triggers an SQL error. Earlier engine
certificate/exit-resource diagnostics remain in logs. Manual user verification
of this stage is still pending.
