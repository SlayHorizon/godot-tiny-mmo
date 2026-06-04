class_name MeleeArc
extends Area2D
## Short-lived hitbox spawned by melee weapons. Damages every valid target
## it overlaps during its brief lifetime, then frees itself. Honors the same
## PvP / sparring / friendly-fire rules as the bow arrow so combat behaves
## consistently regardless of weapon type.
##
## Server-only logic — clients spawn an empty visual placeholder (the
## CollisionShape and damage path are gated behind multiplayer.is_server()).

## How long the arc stays live before despawning. Short enough to feel like
## a single swing, long enough to forgive timing.
@export var lifetime: float = 0.18

var source: Character
var damage: float = 10.0


func _ready() -> void:
	if GameMode.is_world_server():
		body_entered.connect(_on_body_entered)

	var t: Timer = Timer.new()
	t.wait_time = lifetime
	t.one_shot = true
	t.timeout.connect(queue_free)
	add_child(t)
	t.start()


func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return

	# Same target-validation rules as the arrow — flags get a special path,
	# everything else funnels through take_damage with PvP/sparring gates.
	if body is TerritoryFlag:
		if source is not Player:
			return
		# Flag damage = weapon damage straight. AD coupling removed so the
		# weapon's tuned values are the source of truth.
		body.take_damage(damage, source if source is Character else null)
		return

	if body is not Character:
		return

	# No NPC-vs-NPC friendly fire (until proper teams exist).
	if source is not Player and body is not Player:
		return

	# Player-vs-player only lands in PvP zones — same exception for live
	# sparring matches the arrow respects.
	if body is Player and source is Player and not (body as Player).is_pvp():
		if not (SparringService.is_pvp_live_for(body as Player) and SparringService.is_pvp_live_for(source as Player)):
			return

	# Guild friendly fire: members tagged into the same guild don't damage each
	# other — except in a live sparring match (a consented duel still lands).
	if _same_guild_no_spar(source, body):
		return

	# Damage is whatever the ability tuned in (`base_damage` field on the
	# MeleeSwingAbility .tres). Mitigation happens inside take_damage via
	# the target's armor.
	body.take_damage(damage, source if source is Character else null)


## True when both are Players tagged into the same guild and not in a live
## sparring match (so guildmates are protected from friendly fire).
func _same_guild_no_spar(source_node: Node, body: Node) -> bool:
	if source_node is not Player or body is not Player:
		return false
	var src_guild: int = (source_node as Player).player_resource.active_guild_id
	var tgt_guild: int = (body as Player).player_resource.active_guild_id
	if src_guild <= 0 or src_guild != tgt_guild:
		return false
	return not (SparringService.is_pvp_live_for(body as Player) and SparringService.is_pvp_live_for(source_node as Player))
