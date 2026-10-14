# Gameplay direction — consolidated design notes

**Status:** Product direction / design proposals; not a balancing specification or assertion that these mechanics already exist. Consolidated from the 2026-10-14 draft formerly named `Mandate_of_Three_Design_Decisions.md`.

## Current direction

- Keep the recognizable Metin-like loop: social open-world grinding, mob packs, Metins and bosses, equipment upgrades +0 to +9, trading and accessible solo progression.
- Spawn-region variety and encounter pressure are **possible future mechanics** intended to reduce fixed-timer spawn-route farming; no event scheduler is implemented by this note.
- Bosses should survive long enough to exhibit readable combat patterns (simple cleaves/AoE/adds/phase or position mechanics), not demand complex raid choreography.
- Normal/entry-level dungeon routes should remain approachable; harder tiers may add keys/modifiers and emphasize efficiency without locking basic progression behind paid or rare entry fees.
- Solo gameplay should be viable for every class; small parties should feel rewarding, without mandatory healer/tank compositions or Shaman buff-alt dependency. Class skill/stance identities and buff duration remain **balance proposals**.
- Basic sustain and mob luring should avoid repetitive consumable taxes. Reusable potion and taunt/horn ideas are **not yet final mechanics**; numerical durations and cooldowns from earlier drafts were examples, not accepted tuning.
- Specialized consumables may exist where their scarcity creates meaningful choices, not as mandatory requirements for routine farming.

## Architecture precedence — important

**Do not reuse the old "no selectable channels, hidden layers only" rule.** The newer [World architecture ADR](../architecture/world-instance-architecture.md) prefers **dynamic player-visible channels per busy map** within one logical realm, with possible hidden overflow and dungeon MapInstances. It explicitly supersedes that part of the historical gameplay draft.

[Economy C1–C5](../architecture/economy/README.md) controls durability/account money/shop custody. [Current project direction](project-direction.md) and actual server code determine what is already built; the bullets above are gameplay goals, not implement-now tickets.

## Still undecided

Class/buff balance, boss contribution/loot allocation, dungeon key economy, potion duration, lure radius and whether/when to implement regional events. Keep these decisions separate from persistence and infrastructure contracts.
