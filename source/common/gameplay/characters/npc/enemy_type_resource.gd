class_name EnemyTypeResource
extends Resource
## Data-driven enemy definition. Drop one of these into a HostileNpc node's
## `enemy_data` slot and the NPC reads its stats / loot / AI knobs from this
## resource instead of inspector-tuned per-instance @exports. Mirrors how
## ShopResource powers ShopInteractable and CraftingStationResource powers
## CraftingStation — the pattern is "one .tres = one enemy archetype, drop
## it into many instances."
##
## Why: balancing a tier of enemies means editing one file, not N nodes. New
## enemy types are pure data — no scene authoring beyond placing the generic
## hostile_npc.tscn somewhere on the map.
##
## Fields the NPC node still owns: position, detection_area (needs a node
## reference), per-instance overrides via the inspector if you want a one-off.

## Identifier matched against quest KILL objectives (&"iron_golem", &"wolf",
## etc.). Enemies with the same enemy_type aggregate to the same objective —
## useful for "elite" variants that share progression.
@export var enemy_type: StringName

## Friendly name for UI / chat announcements (e.g. "Iron Golem").
@export var display_name: String

## Sprite the NPC renders with. Keep this on the resource so a re-skin is a
## one-file change.
@export var skin: SpriteFrames

@export_group("Combat")
@export var max_health: float = 50.0
@export var attack_damage: float = 8.0
## Seconds between auto-attacks while in range.
@export var attack_cooldown: float = 1.5
@export var armor: float = 0.0
## Optional weapon. Null = melee AoE attacker.
@export var weapon: WeaponItem

@export_group("AI & Movement")
@export var move_speed: int = 20
@export var distance_to_attack: int = 20
@export var max_distance_from_spawn: int = 100
@export var chase_on_area: bool = false

@export_group("Rewards")
@export var xp_reward: int = 25
## Seconds before respawn after death.
@export var respawn_delay: float = 5.0
@export var loot: Array[LootDrop]
