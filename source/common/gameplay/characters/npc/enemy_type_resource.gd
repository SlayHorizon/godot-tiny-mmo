class_name EnemyTypeResource
extends Resource
## Data-driven enemy definition. Drop one of these into a HostileNpc node's
## `enemy_data` slot and the NPC reads its stats / loot / AI knobs from this
## resource instead of inspector-tuned per-instance @exports. Mirrors how
## ShopResource powers a shop NPC and CraftingStationResource powers
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
## Visual size multiplier — a boss reads BIGGER. Scales the SPRITE only, never the
## collision / attack reach (a scaled node can't close to melee range). 1.0 = normal.
@export var visual_scale: float = 1.0
## A BOSS type. A dungeon RoomNode gives any boss-type mob it spawns a BossController
## (phases, telegraphed slam, enrage) and keeps its loot — no per-marker flag needed.
@export var is_boss: bool = false

@export_group("Combat")
@export var max_health: float = 50.0
@export var attack_damage: float = 8.0
## Seconds between auto-attacks while in range.
@export var attack_cooldown: float = 1.5
@export var armor: float = 0.0
## Magic resistance — mitigates magic damage (wand bolts) the way armor mitigates
## physical. Default 0: mob toughness is tuned via HP; reserve MR for the rare
## "resists magic" archetype so the stat means something when it appears.
@export var mr: float = 0.0
## Optional weapon. Null = melee AoE attacker.
@export var weapon: WeaponItem

@export_group("Lunge")
## Telegraphed gap-closer. 0 = this enemy never lunges. When its target sits in
## the pounce window (between ~2× melee range and lunge_range), the mob winds
## up — a red circle marks the target's CURRENT spot — then dashes to that
## LOCKED spot and damages players still inside lunge_radius (attack_damage).
## Fully dodgeable by moving during the windup; punishes standing still.
@export var lunge_range: float = 0.0
@export var lunge_radius: float = 24.0
@export var lunge_windup_s: float = 0.55
@export var lunge_speed_multiplier: float = 5.0
@export var lunge_cooldown: float = 5.0

@export_group("AI & Movement")
@export var move_speed: int = 20
@export var distance_to_attack: int = 20
## Leash radius. The mob will chase / attack up to this far from its spawn
## point; cross it and the mob disengages and walks home (regenerates HP
## en route at the boosted return speed). Tune small for tight cave mobs,
## bigger for open-field mobs that need to allow comfortable ranged
## engagement. ~300 default = bow at full draw + a bit of breathing room.
@export var max_distance_from_spawn: int = 300
## Whether the mob leashes home past max_distance_from_spawn. False = it COMMITS
## and fights to the death — bosses (a world boss in the open field, or a dungeon
## boss) and trash in bounded dungeon rooms.
@export var leashes: bool = true

## Aggro radius. The mob "sees" any player inside this circle and engages
## (when chase_on_area is true) — or pack-mates that hear an ally's
## was_attacked signal use it to decide if they're close enough to help.
## Should be SMALLER than max_distance_from_spawn so the mob can reach
## anything it sees before the leash kicks in. ~150 default.
@export var detection_radius: int = 150
@export var chase_on_area: bool = false

@export_group("Rewards")
@export var xp_reward: int = 25
## Seconds before respawn after death.
@export var respawn_delay: float = 5.0
## Whether the mob respawns at all. False = SINGLE-LIFE — the body is removed
## instead of returning (dungeon mobs, one-off event bosses). A mob with no
## xp_reward AND no loot grants nothing on death (the natural "shadow" trash).
@export var respawns: bool = true
@export var loot: Array[LootDrop]


@export_group("Boss")
## Phase 2: enrage when HP drops to this fraction of max (speeds the body up,
## summons adds, slams faster). Only read for an is_boss type that a dungeon
## RoomNode has given a BossController.
@export var enrage_health_fraction: float = 0.5
## Telegraphed slam: danger-ring radius (px), the wind-up players get to step out
## of it, and the damage dealt to anyone still inside when it lands.
@export var slam_radius: float = 110.0
@export var slam_windup_s: float = 1.1
@export var slam_damage: float = 45.0
## Seconds between slams — phase 1, then the faster enraged cadence.
@export var slam_interval_s: float = 6.0
@export var enraged_slam_interval_s: float = 3.5
## On enrage: summon this many of this enemy slug, spread around the boss.
@export var add_enemy_slug: StringName = &"rat_base"
@export var add_count: int = 2
@export var add_spread_px: float = 48.0
## Move-speed multiplier applied to the body on enrage (it chases harder).
@export var enrage_speed_mult: float = 1.3
