class_name BattleFormAbility
extends AbilityResource
## The Archon / Renekton-R ult: grow bigger (body sprite + hurtbox) with a HUGE temp HP
## wall for a few seconds. The bigger hurtbox is the honest tradeoff for the HP — you're
## a wall, but an easy-to-hit one. Heavy mana, long duration. Resolve branch, book.
##
## Server-authoritative HP + hurtbox scale + revert live in BattleFormState; this spawns
## it and broadcasts the client-side body grow (InstanceClient._on_battleform). No power
## bump by design (owner: keep it simple — the HP wall IS the ult).


## Temp max + current HP granted for the duration (clamped back on expiry).
@export var bonus_hp: float = 180.0
## How much bigger you get (1.6 = +60% sprite + hurtbox).
@export var scale_factor: float = 1.6
## How long you're a free titan AFTER the transformation finishes.
@export var buff_duration_s: float = 8.0
## The transformation is SEQUENCED (a channeled colossus entrance): first the rune builds
## on the ground for [member rune_build_s], THEN the body grows over [member grow_s] (rune
## at full), then the rune fades. You're FROZEN for the whole wind-up — its own counterplay,
## since enemies see it coming. HP + hurtbox apply at once on the server (you're a wall
## while vulnerable). The total form lasts wind-up + buff_duration_s.
@export var rune_build_s: float = 1.0
@export var grow_s: float = 1.2


func use_ability(user: Entity, _direction: Vector2) -> void:
	if not GameMode.is_world_server() or user is not Player:
		return
	var caster: Player = user as Player
	# Total form time = the wind-up (rune build + grow) + the free-titan duration.
	var total: float = rune_build_s + grow_s + buff_duration_s
	var state: BattleFormState = BattleFormState.new()
	state.caster = caster
	state.bonus_hp = bonus_hp
	state.scale_factor = scale_factor
	state.duration = total
	caster.add_child(state)
	# Tell every client to run the transformation + grow for the total time.
	if WorldServer.curr == null or caster.player_resource == null:
		return
	var map: Node = caster.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"battleform.start", {
			"p": int(caster.player_resource.current_peer_id),
			"d": total,
			"sc": scale_factor,
			"rb": rune_build_s,
			"g": grow_s,
		}),
		map.get_parent().name
	)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("+%d max health" % int(bonus_hp))
	lines.append("+%d%% size" % int(round((scale_factor - 1.0) * 100.0)))
	lines.append("%ss" % fmt_num(buff_duration_s))
	return lines
