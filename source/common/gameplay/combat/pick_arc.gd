class_name PickArc
extends Area2D
## Pickaxe / sickle swing hitbox. Hybrid:
## - bodies (players, NPCs, territory flags) → small "tool as weapon" damage via
##   CombatHit, using the SAME deterministic shape query as MeleeArc so a swing
##   lands on still targets (a flag) that enter-events miss.
## - areas (MineableNode) → register_gather_hit (the actual harvest).
##
## Server-only damage / extraction; clients spawn the same scene for visual
## feedback but the gates keep effects server-side.


@export var lifetime: float = 0.2

## Damage dealt to Character bodies + flags. Kept low — a tool is a weak weapon.
var character_damage: float = 2.0
## Extraction damage per swing to MineableNodes (wooden = 1, iron = 2, …).
var extraction_damage: int = 1
## Which tool this swing represents (&"pickaxe", &"sickle", …) — checked against
## a MineableNode's required_tool.
var tool_type: StringName = &"pickaxe"
var source: Character
## Instance ref so register_gather_hit can route the result back to the peer.
var instance: Node

var _hit_bodies: Array[Node] = []
var _scanned: bool = false


func _ready() -> void:
	collision_mask = PhysicsLayers.HARVEST_TARGET_MASK
	if GameMode.is_world_server():
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)
	else:
		set_physics_process(false)

	var t: Timer = Timer.new()
	t.wait_time = lifetime
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()


func _physics_process(_delta: float) -> void:
	set_physics_process(false)
	if _scanned:
		return
	_scanned = true
	for body: Node2D in CombatHit.overlapping_bodies(self):
		_on_body_entered(body)


func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	if _hit_bodies.has(body):
		return
	_hit_bodies.append(body)
	# Shared target rules (flags, PvP, sparring, guild friendly-fire) via CombatHit.
	# The tool is a weak weapon; mining nodes come through _on_area_entered.
	CombatHit.try_damage(source if source is Character else null, body, character_damage)


# MineableNode is an Area2D, so it surfaces via area_entered. Routes through the
# node's register_gather_hit; that handles charges, per-player progress, awards,
# and returns the result we push back.
func _on_area_entered(area: Area2D) -> void:
	if not (area is MineableNode):
		return
	if not (source is Player):
		return
	var node: MineableNode = area as MineableNode
	var result: Dictionary = node.register_gather_hit(source as Player, extraction_damage, instance, tool_type)
	if result.get("ok", false) or result.has("reason"):
		var peer_id: int = int((source as Player).player_resource.current_peer_id)
		if peer_id > 0 and WorldServer.curr != null:
			WorldServer.curr.data_push.rpc_id(peer_id, &"mining.gather_result", result)
