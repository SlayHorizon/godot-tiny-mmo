class_name PickSwingAbility
extends AbilityResource
## Pickaxe / tool swing. Spawns a PickArc that:
##   - Damages Character bodies a little (pickaxe-as-weapon: weak by design).
##   - Triggers MineableNode.register_pickaxe_hit on overlap (the actual harvest).
##
## Higher-tier pickaxes use the same ability with a tuned extraction_damage
## to chip ore HP faster — that's the "tool tier matters" progression.


@export var arc_scene: PackedScene = preload("res://source/common/gameplay/combat/pick_arc.tscn")
## Damage when this swing accidentally clips a Player or NPC. Kept low —
## you don't want a wooden pickaxe to be a real combat weapon.
@export var character_damage: float = 2.0
## Extraction damage applied to MineableNodes per swing. 1 = wooden, scale
## up for higher tiers. Combined with node.extraction_hp this sets the
## "swings per ore yield" feel.
@export var extraction_damage: int = 1
@export var spawn_offset: float = 0.0
## The tool this swing counts as. Veins want &"pickaxe", herbs want &"sickle".
## Forwarded to the PickArc so MineableNode.required_tool can gate the gather.
@export var tool_type: StringName = &"pickaxe"


func use_ability(user: Entity, direction: Vector2) -> void:
	# Visual: poke the pickaxe weapon to play its swing animation on every
	# client. The weapon-owned animation lives on Pickaxe; we route through
	# its method directly so we don't need to plumb an animation library
	# into the Character animation tree.
	if user is Character:
		var weapon: Node = (user as Character).equipment_component.mounted_nodes.get(&"weapon", null)
		if weapon is Pickaxe:
			(weapon as Pickaxe).play_pick_swing()

	if not GameMode.is_world_server():
		return
	if arc_scene == null or user == null:
		return

	var arc: PickArc = arc_scene.instantiate()
	arc.source = user if user is Character else null
	arc.character_damage = character_damage
	arc.extraction_damage = extraction_damage
	arc.tool_type = tool_type
	# Pass the ServerInstance reference through so the arc's area_entered
	# can route the gather result back to the right peer. user.get_parent()
	# is the Map, and Map's parent is the ServerInstance (matches the
	# parent chain Character._broadcast_hit_feedback walks).
	var maybe_map: Node = user.get_parent()
	if maybe_map != null:
		arc.instance = maybe_map.get_parent()

	var dir_norm: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	arc.global_position = user.global_position + dir_norm * spawn_offset
	arc.rotation = dir_norm.angle()
	user.get_parent().add_child(arc)
