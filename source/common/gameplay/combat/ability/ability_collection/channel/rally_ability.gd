class_name RallyAbility
extends ChannelAbility
## Inspiration support: channel a rallying cry (rooted — moving cancels it), then on
## COMPLETION you and every nearby ALLY surge with bonus move speed for a few seconds.
## A windup-then-payoff that rewards positioning before a group push or escape; the
## sword's one supportive tool.
##
## The payoff rides ChannelAbility.channel_complete (fires only if the channel finishes
## uninterrupted) + BuffService (timed, auto-expiring). "Ally" is the shared
## CombatHit.are_allied rule (spar teammates / guildmates), same as the heal aura, so it
## never speeds up an enemy. A green aura on each rallied player shows who got the buff.


## Flat move speed granted to each rallied ally (and the caster).
@export var move_speed_bonus: float = 15.0
@export var buff_duration_s: float = 5.0
## Aura tint flashed on each rallied player (green = Inspiration / support).
@export var aura_color: Color = Color(0.5, 0.95, 0.6)


func channel_complete(caster: Character) -> void:
	if not GameMode.is_world_server() or caster is not Player:
		return
	_rally(caster as Player)  # the caller is always rallied
	var container: Node = caster.get_parent()
	if container == null:
		return
	for node: Node in container.get_children():
		if node == caster or node is not Player:
			continue
		var target: Player = node as Player
		if target.is_dead:
			continue
		if not CombatHit.are_allied(caster as Player, target):
			continue
		if caster.global_position.distance_to(target.global_position) <= radius:
			_rally(target)


## Grant the move-speed buff to [param player] and flash a green rally aura on them.
func _rally(player: Player) -> void:
	BuffService.apply(player, Stat.MOVE_SPEED, move_speed_bonus, buff_duration_s)
	if WorldServer.curr == null or player.player_resource == null:
		return
	var container: Node = player.get_parent()
	if container == null or container.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"guard.cast", {
			"p": int(player.player_resource.current_peer_id),
			"d": buff_duration_s,
			"fx": "",
			"col": aura_color,
		}),
		container.get_parent().name
	)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("+%s move speed to allies" % fmt_num(move_speed_bonus))
	lines.append("%ss buff" % fmt_num(buff_duration_s))
	lines.append_array(super())
	return lines
