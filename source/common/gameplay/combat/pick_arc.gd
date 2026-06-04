class_name PickArc
extends Area2D
## Pickaxe swing hitbox. Hybrid of MeleeArc and an Area2D-vs-Area2D detector:
## - body_entered → Character → small "weak weapon" damage (your point 4)
## - area_entered → MineableNode → register_pickaxe_hit (your point 3)
##
## Lives ~lifetime seconds then frees itself. Server-only damage / extraction
## logic — clients spawn the same scene for visual feedback but the gates
## around body_entered / area_entered keep effects scoped to the server.


@export var lifetime: float = 0.2

## Damage dealt to Character bodies (players + NPCs). Kept low — the pickaxe
## is a tool, not a sword. ~25-30% of a basic sword swing.
var character_damage: float = 2.0
## Extraction damage dealt per swing to MineableNodes. Wooden pickaxe = 1,
## iron = 2, etc. Combined with the node's extraction_hp this determines
## swings-per-yield.
var extraction_damage: int = 1
var source: Character
## Instance ref passed through so register_pickaxe_hit can route the result
## back to the right peer (server pushes mining.gather_result).
var instance: Node


func _ready() -> void:
	if GameMode.is_world_server():
		body_entered.connect(_on_body_entered)
		area_entered.connect(_on_area_entered)

	var t: Timer = Timer.new()
	t.wait_time = lifetime
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()


# Character bodies — same target-validation rules as MeleeArc so PvP zones
# and sparring stay consistent. Damage is the low pickaxe-as-weapon value.
func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	if body is not Character:
		return
	if source is not Player and body is not Player:
		return
	if body is Player and source is Player and not (body as Player).is_pvp():
		if not (SparringService.is_pvp_live_for(body as Player) and SparringService.is_pvp_live_for(source as Player)):
			return
	# Guild friendly fire: same-tagged-guild members don't damage each other
	# (except in a live sparring match).
	if _same_guild_no_spar(source, body):
		return
	body.take_damage(character_damage, source if source is Character else null)


func _same_guild_no_spar(source_node: Node, body: Node) -> bool:
	if source_node is not Player or body is not Player:
		return false
	var src_guild: int = (source_node as Player).player_resource.active_guild_id
	var tgt_guild: int = (body as Player).player_resource.active_guild_id
	if src_guild <= 0 or src_guild != tgt_guild:
		return false
	return not (SparringService.is_pvp_live_for(body as Player) and SparringService.is_pvp_live_for(source_node as Player))


# MineableNode is an Area2D, so it surfaces via area_entered (Area2D vs Area2D).
# Routes through the node's register_pickaxe_hit; that method handles charge
# accounting, per-player progress, awards, and returns the result we push back.
func _on_area_entered(area: Area2D) -> void:
	if not (area is MineableNode):
		return
	if not (source is Player):
		return
	var node: MineableNode = area as MineableNode
	var result: Dictionary = node.register_gather_hit(source as Player, extraction_damage, instance)
	# Push the result to the swinging player so the client can toast / SFX
	# without polling. Only fire when something happened (extraction or a
	# named failure) — silent failures like cooldown stay silent.
	if result.get("ok", false) or result.has("reason"):
		var peer_id: int = int((source as Player).player_resource.current_peer_id)
		if peer_id > 0 and ServerHub.current != null:
			ServerHub.current.data_push.rpc_id(peer_id, &"mining.gather_result", result)
