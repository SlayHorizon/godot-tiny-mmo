class_name HurtBox
extends Area2D
## Passive damage-receiving area for a Character — the thing attacks target, so the
## navigation body can stay small without shrinking the hit target. Lives on the `hurtbox`
## physics layer and detects nothing itself; combat hitboxes resolve a hit on it back to
## [member character] (see CombatHit.try_damage). Wired as a child of the Character in
## character.tscn.

var character: Character


func _ready() -> void:
	character = get_parent() as Character
	collision_layer = PhysicsLayers.HURTBOX
	collision_mask = 0 # passive: attacks detect it; it detects nothing
