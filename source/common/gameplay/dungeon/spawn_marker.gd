class_name SpawnMarker
extends Marker2D
## A hand-placed mob spawn inside a dungeon RoomNode. Pick the enemy in the
## inspector and position the marker where it should appear; the room spawns this
## enemy at this spot when the encounter activates. Multiple markers (with
## different enemy types) = a mixed pack — author the whole encounter by hand.

@export var enemy_type: EnemyTypeResource
## Mark the room's BOSS here. A boss keeps its loot/XP (the kill payoff) and its
## enemy_data visual_scale (it reads big); trash drops nothing — the reward is
## completing the dungeon, not farming. Either way it won't respawn or leash.
@export var boss: bool = false
