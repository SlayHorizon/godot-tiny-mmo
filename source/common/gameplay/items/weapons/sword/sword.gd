extends Weapon
## Thin holder for sword-flavoured tuning. Actual swing behaviour lives in
## the assigned MeleeSwingAbility (combat/ability/ability_collection/
## melee_swing/), and the sword's animation library is registered by the base
## Weapon._ready (one loader for every weapon). Future swords (rapier,
## claymore) inherit nothing extra — they just point at different
## MeleeSwingAbility .tres files with different ratios / animation names.
