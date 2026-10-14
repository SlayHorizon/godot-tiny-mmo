# PvE vertical slice - one mob and ground loot

This document records the first, historical PvE stage. Current combat has four
Wild Dogs, directional combos and attack RPCs without target IDs. Cooldowns and
attack behavior below were superseded by [Combat Feel Pass](combat-feel.md).
Reservation, transactional pickup and persistent UID rules still apply.

Status: 2026-10-07; minimal slice on `codex/pve-ground-loot`:

`Player -> Mob -> Combat -> Death -> Ground Loot -> Pickup -> Persistent Item`

## Gameplay and authority

**WASD**: movement; **I**: inventory; **Space**: attack the guard; **E**: nearest
loot. Approach to about 2 m. The mob is a red capsule with name/HP; loot is a gold
ground object with name/reservation.

At this historical stage, the server calculated damage from current SQLite
equipment: 10 unarmed, 23/27 with starter swords. Clients sent sequence and the
sole known mob's ID, never damage, position or their own identity. Required: living
player, distance <=2.4 m, unobstructed world-layer line of sight and **600 ms**
cooldown. Monotonic int32 sequences rejected replay; spam did not increase damage frequency.

## Mob and AI

One guard: 120 HP, speed 2.8 m/s, home `(-4, 0, 0)`.
AI runs in server physics at 60 Hz:

| State | Behavior |
| --- | --- |
| IDLE | Select nearest living player within 6 m with line of sight. |
| CHASE | Approach using CharacterBody3D collisions. |
| ATTACK | Deal 4 damage each second within 1.8 m. |
| RETURN | On target loss or exceeding a 10 m leash, return home, restore HP and reset contributions. |
| DEAD | Create one drop, disappear and respawn after 6 seconds. |

RETURN is immune to attacks. Death is a one-time transition; later commands cannot
create more loot. Players have 100 HP. At zero HP, movement/attack/pickup stop;
after two seconds the player returns to spawn with full HP. HP/position remain
runtime state. This initial stage lacked obstacle navigation (chase could stop
at a wall), attack animations, combos, PvP, multiple targets and facing validation.

## Ground loot and ownership

Death creates one runtime drop: unique UID, position, `iron_sword` and a server-
selected +1...+9 attack bonus. For **15 seconds**, the highest damage contributor
has the reservation; ties use the lower persistent character ID. Reservation
belongs to the character, so relog/peer-ID changes do not alter it. Loot becomes
public afterward and expires unclaimed after **120 seconds**.

Clients send only the UID. The server checks living player, existing/unexpired
drop, ownership, range <=2.5 m, line of sight and bag space. It accepts no client-
provided definition, bonus or recipient.

SQLite **schema v11** adds `ground_item_claims` with unique drop UID. One transaction
writes the receipt, same-UID ItemInstance and bag placement. Only after COMMIT does
the server remove the drop and update the private inventory snapshot. A full bag
or SQL error leaves loot on the ground; rollback also removes the receipt.
Two RPCs for one drop have one winner. Durable receipts prevent duplicate UID
grants after DB reopen.

Unclaimed loot is not persisted; world restart removes runtime drops. Committed
pickup is durable. Mob/HP/drop state is replicated every 100 ms to the small
instance; clients interpolate mob movement. AOI/local prediction come later.

## Tests

```powershell
# Isolated SQLite and WebSocket 18098, separate from normal accounts/world DB.
& .\tests\run-pve.ps1

# Item and network-physics regressions.
& .\tests\run-items.ps1
& .\tests\run-spike3d.ps1
```

Passed on the project's Godot 4.7.2:

- IDLE -> CHASE -> ATTACK -> RETURN -> IDLE, mob damage and HP reset.
- Range, obstruction, replay/unknown mob and cooldown under two-client spam.
- Both players attack one mob; one death produces one drop, with no pre-pickup grant.
- Reservation, full bag, distant pickup, competing public pickups, one winner and
  no duplicate on retry.
- Forced placement failure after partial writes rolls back; UID, bonus, placement
  and receipt survive SQLite reopen.
- Both clients see HP/death/ground loot; only the winner receives the item.

`tests/pve_session.tscn` separately verified real gateway/master/world:
equip, kill, loot, pickup and relog with an identical item snapshot. It creates a
local guest account/character and needs a quiet normal Spike instance:

```powershell
& .\.godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --mode=client res://tests/pve_session.tscn
```

An OpenGL real-session render was generated and inspected. Logs/images are in
ignored `.godot/verification`. The user manually confirmed general slice operation
on 2026-10-07, not every pickup edge case. Technical player respawn lacked a
separate integration test at this stage. Earlier certificate/exit-resource
diagnostics remain.

Editor import and all 872 source scripts/scenes/resources loaded without parse
errors. Full two-client equip/relog through gateway/master/world also passed after
combat was added.
