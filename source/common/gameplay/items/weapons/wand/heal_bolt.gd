class_name HealBolt
extends Projectile
## A bolt that heals the first ALLY it touches instead of damaging enemies. Ally = spar teammate
## (while either side is in a match), otherwise a guildmate / groupmate — the same definition the
## team-colored health bars use. Everyone else (enemies, neutral players, NPCs) it flies straight
## through; walls stop it.
##
## Only overrides the per-hit RESPONSE — the Projectile base owns all detection, walls and piercing.
## Server-authoritative: only the server bolt applies the heal (+ broadcasts the green number);
## client bolts stop on the first ally so the flight reads naturally.

var heal_amount: float = 0.0


## Heal the first allied player crossed; pass non-allies; stop on solid geometry.
func _resolve_hit(node: Node2D) -> CombatHit.Result:
	var target: Node2D = node
	if node is HurtBox:
		target = (node as HurtBox).character
	# Walls / doors / flags stop the bolt; a non-character collider isn't a heal target.
	if target == null or target is not Character:
		return CombatHit.Result.BLOCKED
	if target is not Player:
		return CombatHit.Result.IGNORED # non-player character — fly past
	# Client: visual only — stop on the first player; the ally check + heal are the server's call.
	if not multiplayer.is_server():
		return CombatHit.Result.DAMAGED
	if source is not Player:
		return CombatHit.Result.IGNORED
	var ally: Player = target as Player
	if not CombatHit.are_allied(source as Player, ally):
		return CombatHit.Result.IGNORED # fly past non-allies, keep looking for a friend
	var sc: StatsComponent = ally.stats_component
	var hp: float = sc.get_stat(Stat.HEALTH)
	var healed: float = minf(hp + heal_amount, sc.get_stat(Stat.HEALTH_MAX)) - hp
	if healed > 0.0:
		sc.set_stat(Stat.HEALTH, hp + healed)
		_broadcast_heal(ally, healed)
	return CombatHit.Result.DAMAGED # consumed


## Green floating "+N" over the healed ally, for everyone in the instance — same combat.hit path
## weapon damage and flag repairs use. Naming ServerInstance here is safe on client exports thanks
## to the stub-generating export plugin (addons/tinymmo/export_plugin/export_plugin.gd).
func _broadcast_heal(target: Player, healed: float) -> void:
	if WorldServer.curr == null:
		return
	var instance: Node = target.get_parent()
	while instance != null and instance is not ServerInstance:
		instance = instance.get_parent()
	if instance == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"combat.hit", {
			"amount": int(round(healed)),
			"position": target.global_position,
			"heal": true,
		}),
		instance.name
	)
