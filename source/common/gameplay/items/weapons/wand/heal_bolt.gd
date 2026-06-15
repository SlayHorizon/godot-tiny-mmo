class_name HealBolt
extends Projectile
## A bolt that heals the first ALLY it touches instead of damaging enemies.
## Ally = spar teammate while either side is in a match, otherwise a guildmate
## (the same definition the team-colored health bars use). Everyone else —
## enemies, neutral players, NPCs — it flies straight through; walls stop it.
##
## Server-authoritative: only the server bolt applies the heal (and broadcasts
## the green combat.hit number). Client bolts are visual and just stop on the
## first player they cross so the flight reads naturally.

var heal_amount: float = 0.0


func _on_body_entered(body: Node2D) -> void:
	if body == source:
		return
	# Walls / doors / flags stop the bolt; non-player characters don't block it.
	if body is not Character:
		queue_free()
		return
	if body is not Player:
		return
	# Client: visual only — the heal (and whether this was really an ally) is
	# the server's call; feedback arrives via the combat.hit broadcast.
	if not multiplayer.is_server():
		queue_free()
		return
	if source is not Player:
		queue_free()
		return
	var target: Player = body as Player
	if not CombatHit.is_heal_ally(source as Player, target):
		return # fly past non-allies, keep looking for a friend
	var sc: StatsComponent = target.stats_component
	var hp: float = sc.get_stat(Stat.HEALTH)
	var healed: float = minf(hp + heal_amount, sc.get_stat(Stat.HEALTH_MAX)) - hp
	if healed > 0.0:
		sc.set_stat(Stat.HEALTH, hp + healed)
		_broadcast_heal(target, healed)
	queue_free()


## Green floating "+N" over the healed ally, for everyone in the instance —
## same combat.hit path weapon damage and flag repairs use. Naming ServerInstance
## here is safe on client exports thanks to the stub-generating export plugin
## (addons/tinymmo/export_plugin/export_plugin.gd).
func _broadcast_heal(target: Player, healed: float) -> void:
	if ServerHub.current == null:
		return
	var instance: Node = target.get_parent()
	while instance != null and instance is not ServerInstance:
		instance = instance.get_parent()
	if instance == null:
		return
	ServerHub.current.propagate_rpc(
		ServerHub.current.data_push.bind(&"combat.hit", {
			"amount": int(round(healed)),
			"position": target.global_position,
			"heal": true,
		}),
		instance.name
	)
