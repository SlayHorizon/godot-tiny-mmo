# Item Progression Slice - first step

Status: 2026-10-07, branch `codex/item-progression-slice`. A small loop on the
existing instance model: kill a dog -> see its ground weapon -> pick up -> compare
-> equip -> deal new weapon damage -> retain it after relog.

## Gameplay behavior

Loot remains an iron sword with a server-rolled +1...+9 attack bonus. Ground labels
and pickup notices show that weapon's attack, 11...19. Pickup adds it to the bag
without automatically equipping it.

The I panel shows character attack and the current weapon. The equipped instance
comes first, then the latest pickup marked as new, then remaining items sorted by
attack. This is presentation order; bag placement, snapshot and SQLite state are
unchanged. The name tooltip contains the UID.

Each bag weapon shows **character attack after equipping** and the difference
from the current weapon. Green means higher attack, red lower, gray unchanged.
Preview subtracts the equipped instance's attack and adds the compared instance:

| Situation | Current character attack | Found weapon attack | After equipping |
| --- | --- | --- | --- |
| Starter with +3 bonus | 23 | 19 | 29 (+6) |
| Starter with +7 bonus | 27 | 19 | 29 (+2) |
| Starter with +7 bonus | 27 | 13 | 23 (-4) |
| No weapon | 10 | 13 | 23 (+13) |

The difference concerns attack, not overall item quality. Combo hit three still
uses a 1.5 multiplier; other rules are in [Combat Feel Pass](combat-feel.md).

## Server and persistence

Preview uses server-calculated instance stats and is not sent as a command.
Equip still accepts action, UID and revision; the server checks ownership and
atomically persists the swap. After commit it also refreshes runtime equipment/
stats. Combat reads RAM attack at swing start. The same first hit can therefore
deal 23 damage with the starter and 29 with a picked-up +9 sword.

UID, bonus, placement and revision survive relog. New-item marking and pickup
notices are session presentation, not new durable data. Reservation, full bags,
double pickup and durable claims follow the [first PvE slice](pve-ground-loot.md).

This stage changed no combat parameters, bonus rolls, two-sword starter set or
schema v11. It introduces progression through choosing a better instance, without
XP, levels, upgrades, rarities, crafting or new weapon types. Further progression
requires a separate scope decision.

The user subsequently selected [character XP and levels](character-xp.md).
That stage added schema v12 reward receipts while retaining the item model.
The later schema v13 refactor removes those XP receipts; current behavior is in
[persistence policy](persistence-policy.md).

## Verification

```powershell
# Isolated database, server and two clients; normal servers not required.
& .\tests\run-progression.ps1

# Full login, comparisons and relog; requires gateway/master/world.
& .\tests\run-items.ps1 -WithSession

# Run sequentially with progression; these share port 18098.
& .\tests\run-pve.ps1
& .\tests\run-combat.ps1
```

Progression tests use production combat/pickup/equip RPCs. The fixture sets the
killed dog's drop bonus to +9 to remove RNG; production rolls remain unchanged.
It checks no pre-pickup grant, ground weapon description, exact UID, 29 (+6)
preview, no UI snapshot mutation, other-player inventory privacy, actual 23 -> 29
damage and identical persistence after SQLite reopen/initialization.
Markers: `PROGRESSION_SERVER_OK` and two `PROGRESSION_CLIENT_OK`.

Full inventory sessions verify better/weaker/equal weapon previews and a preview
without an equipped weapon. `tests/pve_session.tscn` additionally runs normal
gateway/master/world: dog kill, random instance pickup, comparison, equip and
relog with an identical snapshot.

`item-progression-preview.png` in `.godot/verification` was generated and inspected;
the new-sword comparison and equip button are visible without scrolling. Full
sessions also generate `pve-item-comparison-preview.png` and
`pve-item-equipped-preview.png`. All 873 source scripts/scenes/resources loaded
without parse errors. Earlier certificate-store and exit-resource diagnostics remain.

The retired native inventory renderer and its screenshot checks are removed.
The progression runner is headless; item state, RPCs and persistence checks remain.
