class_name BlinkAbility
extends AbilityResource
## A short teleport in the caster's aim direction (rank-scaled distance), raycast-clamped
## so you can't blink INTO a wall. The book's dive/escape tool (Inspiration). No i-frames
## — the teleport itself is the dodge.
##
## Client-side: movement is client-authoritative, so the local player teleports ITSELF the
## instant the button is pressed (predict_use, which runs only on the caster's client),
## and the regular position sync shows the jump to everyone. use_ability stays a no-op —
## the server just runs cooldown + mana like any other ability. No new exploit surface: a
## position-hacker could already move anywhere; the raycast is purely "don't land in geo".


## Teleport distance in pixels (ranks raise it).
@export var distance: float = 140.0
## Stop this far short of a wall the ray hits (so you don't clip the surface).
@export var wall_margin: float = 8.0


func predict_use(user: Entity, direction: Vector2) -> void:
	if user is not Player:
		return
	var player: Player = user as Player
	var dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	var from: Vector2 = player.global_position
	var to: Vector2 = from + dir * distance
	# Clamp to the first WORLD-layer wall along the path so we land in front of it.
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(from, to, PhysicsLayers.WORLD)
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		to = (hit["position"] as Vector2) - dir * wall_margin
	player.global_position = to
	# A smoke poof at the launch and landing points (caster-side; the position sync
	# already shows the jump to others).
	var map: Node = player.get_parent()
	if map != null:
		var poof: SpriteFrames = load("res://source/common/gameplay/combat/vfx/smoke_poof.tres") as SpriteFrames
		if poof != null:
			for at: Vector2 in [from, to]:
				var fx: SpriteEffect = SpriteEffect.spawn(map, poof, {"scale": Vector2(0.6, 0.6), "z_index": 1})
				if fx != null:
					fx.global_position = at + Vector2(0, -16)  # raise it onto the body (sheet has top whitespace)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%dpx teleport" % int(distance))
	return lines
