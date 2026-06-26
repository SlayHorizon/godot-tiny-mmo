class_name ChannelInstance
extends Node
## Server-side runtime for ONE active channel (see [ChannelAbility]). Lives as a
## child of the caster — so it dies with them, DamageOverTime-style — ticks the
## ability's effect on a Timer, and pushes channel.start / channel.end so every
## nearby client can render (and the caster's client can root + watch for a
## move-cancel).
##
## Ends by: full duration (fires the ability's completion payoff), the caster
## moving (the client sends a channel.cancel request → [method cancel]), death,
## mana-out, or a fresh channel replacing it. Server-only; frees itself on end.

var ability: ChannelAbility
var caster: Character

var _elapsed: float = 0.0
var _ended: bool = false
## Caster's combat timer at channel start — if a later tick sees it bumped, a hit
## landed during the channel (cancel_on_damage abilities like recall bail out).
var _start_combat_until: int = 0


func _ready() -> void:
	if not GameMode.is_world_server() or ability == null or not is_instance_valid(caster):
		queue_free()
		return
	_start_combat_until = caster.combat_until_ms
	_push(&"channel.start", {
		"p": _peer_id(),
		"d": ability.channel_duration_s,
		"r": ability.radius,
		"k": ability.visual_kind,
		"an": ability.name, # so the caster's ability bar can light the matching tile
	})
	var timer: Timer = Timer.new()
	timer.wait_time = maxf(0.1, ability.tick_interval_s)
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()


func _on_tick() -> void:
	if _ended:
		return
	if not is_instance_valid(caster) or caster.is_dead:
		cancel()
		return
	# Anti-combat (recall): a fresh hit since the channel began bumps the combat
	# timer past where it started — bail out.
	if ability.cancel_on_damage and caster.combat_until_ms > _start_combat_until:
		cancel()
		return
	# Optional per-tick mana cost — running dry ends the channel.
	if ability.mana_per_tick > 0.0:
		var mana: float = caster.stats_component.get_stat(Stat.MANA)
		if mana < ability.mana_per_tick:
			cancel()
			return
		caster.stats_component.set_stat(Stat.MANA, mana - ability.mana_per_tick)
	ability.channel_tick(caster)
	_elapsed += maxf(0.1, ability.tick_interval_s)
	if _elapsed >= ability.channel_duration_s:
		_complete()


## Reached full duration — fire the payoff. Push channel.end FIRST: the payoff
## (recall) may teleport the caster out of this instance, after which the
## instance-scoped push could no longer reach their client to clear the cast
## bar / root.
func _complete() -> void:
	if _ended:
		return
	_ended = true
	_push(&"channel.end", {"p": _peer_id()})
	if is_instance_valid(caster):
		ability.channel_complete(caster)
	queue_free()


## Stop the channel WITHOUT the completion payoff (move / death / mana-out).
func cancel() -> void:
	_end()


func _end() -> void:
	if _ended:
		return
	_ended = true
	_push(&"channel.end", {"p": _peer_id()})
	queue_free()


func _peer_id() -> int:
	if caster is Player and (caster as Player).player_resource != null:
		return int((caster as Player).player_resource.current_peer_id)
	return 0


## Push to every client in the caster's instance. Walk caster → Map → Instance
## for the instance name (the same trick as Character._broadcast_hit_feedback —
## common-side code mustn't import the server-only ServerInstance type).
func _push(topic: StringName, payload: Dictionary) -> void:
	if WorldServer.curr == null or not is_instance_valid(caster):
		return
	var map: Node = caster.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(topic, payload),
		map.get_parent().name
	)
