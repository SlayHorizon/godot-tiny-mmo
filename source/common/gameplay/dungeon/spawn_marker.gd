class_name SpawnMarker
extends Marker2D
## A hand-placed mob spawn inside a dungeon RoomNode. Pick the enemy in the
## inspector and position the marker where it should appear; the room spawns this
## enemy at this spot when the encounter activates. Multiple markers (with
## different enemy types) = a mixed pack — author the whole encounter by hand.

@export var enemy_type: EnemyTypeResource
## Optional OVERRIDE to force any enemy type to behave as the room's boss (gets a
## BossController, keeps its loot). Usually leave false — a boss-type enemy
## (EnemyTypeResource.is_boss, e.g. dungeon_boss) is already treated as a boss.
## Trash drops nothing; the reward is completing the dungeon, not farming.
@export var boss: bool = false
## Wave this marker spawns in (0 = first). The room spawns wave 0, and only once it's cleared does
## wave 1 appear, etc. Leave everything at 0 for a classic single-pack room; bump later markers
## (e.g. put the boss on the highest wave) to stage an escalating encounter.
@export var wave: int = 0
