class_name ChannelAbility
extends AbilityResource
## A CHANNELED ability: one press begins a ROOTED channel that ticks an effect
## every [member tick_interval_s] until it (a) reaches [member
## channel_duration_s], (b) the caster moves (the client sends channel.cancel),
## (c) the caster dies, or (d) runs out of mana ([member mana_per_tick] > 0).
##
## The generic machinery — tick Timer, cancel paths, the server→client
## channel.start / channel.end push — lives in [ChannelInstance]. Subclasses
## override [method channel_tick] (the per-tick effect) and [method
## channel_complete] (a one-shot payoff that fires ONLY if the channel runs the
## full duration uninterrupted, e.g. a recall teleport).
##
## Server-authoritative: [method use_ability] does work only on the world server;
## every client (the caster's included) renders from the channel.start push, so
## there is no client-side spawn here and the action.perform echo can't double it.

## Total channel length. The channel also ends early on move / death / mana-out.
@export var channel_duration_s: float = 6.0
## Seconds between effect ticks (also the heal-number / mana-drain cadence).
@export var tick_interval_s: float = 1.0
## Effect radius (heal-aura reach, …) — also sizes the client aura visual.
@export var radius: float = 60.0
## Mana drained per tick. 0 = free; > 0 self-limits the channel (running dry
## cancels it) and is the cleaner cost for a sustained channel than an upfront lump.
@export var mana_per_tick: float = 0.0
## If true, taking a hit during the channel cancels it (recall's anti-combat rule).
## The healing aura leaves this false — its vulnerability is the root, not damage.
@export var cancel_on_damage: bool = false
## Client-visual selector sent in channel.start — the client maps it to a look
## (&"heal_aura" = green ground ring). A new channel adds a new kind + visual.
@export var visual_kind: StringName = &"heal_aura"


func use_ability(user: Entity, _direction: Vector2) -> void:
	# Server-authoritative: only the world server runs the channel.
	if not GameMode.is_world_server() or user is not Character:
		return
	var caster: Character = user as Character
	# One channel per caster — clear any previous before starting a new one.
	var existing: ChannelInstance = caster.get_node_or_null(^"ChannelInstance") as ChannelInstance
	if existing != null:
		existing.cancel()
	var channel: ChannelInstance = ChannelInstance.new()
	channel.name = "ChannelInstance"
	channel.ability = self
	channel.caster = caster
	caster.add_child(channel)


## Per-tick effect (server-only). Override to heal allies, drain a resource, etc.
func channel_tick(_caster: Character) -> void:
	pass


## Fires once if the channel reaches full duration uninterrupted (server-only).
## Override for one-shot payoffs (recall teleport); sustained channels (aura)
## leave it empty.
func channel_complete(_caster: Character) -> void:
	pass
