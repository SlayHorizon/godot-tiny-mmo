class_name BerserkAbility
extends AbilityResource
## Active RAGE (the sword's Domination capstone): for a few seconds you heal a % of all
## the damage you DEAL — go aggressive to claw your health back. It's worth the most
## when you're low (you have the most missing HP to recover), which is the "lifesteal
## your missing health" fantasy without per-hit HP math. Optionally bumps AD for bite.
##
## Reuses [BuffService] (timed, auto-expiring on the status tick) for the LIFESTEAL +
## AD bonuses — the heal itself rides Character.take_damage's lifesteal hook, so there's
## no new combat code. A red aura on the caster (the guard.cast push, reused with a
## colour) tells everyone it's live.


## Heal this % of damage dealt while active (granted via Stat.LIFESTEAL).
@export var lifesteal_percent: float = 25.0
## Flat attack damage added for the duration (0 = lifesteal only).
@export var ad_bonus: float = 0.0
@export var buff_duration_s: float = 6.0
## Aura tint (red = rage / Domination). Sent in the cast push so clients colour it.
@export var aura_color: Color = Color(0.95, 0.27, 0.2)


func use_ability(user: Entity, _direction: Vector2) -> void:
	# Server-authoritative: grant the timed buffs, then tell every client to show the aura.
	if not GameMode.is_world_server() or user is not Player:
		return
	var caster: Player = user as Player
	BuffService.apply(caster, Stat.LIFESTEAL, lifesteal_percent, buff_duration_s)
	if ad_bonus > 0.0:
		BuffService.apply(caster, Stat.AD, ad_bonus, buff_duration_s)
	if WorldServer.curr == null or caster.player_resource == null:
		return
	var map: Node = caster.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"guard.cast", {
			"p": int(caster.player_resource.current_peer_id),
			"d": buff_duration_s,
			"fx": "",  # aura only, no shield flash
			"col": aura_color,
		}),
		map.get_parent().name
	)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Lifesteal %d%%" % int(round(lifesteal_percent)))
	if ad_bonus > 0.0:
		lines.append("+%s attack damage" % fmt_num(ad_bonus))
	lines.append("%ss" % fmt_num(buff_duration_s))
	return lines
