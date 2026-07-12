class_name DeathBurstBehavior
extends MobBehavior
## Dying leaves a lingering hazard where the body fell (refactor P4): the
## puffcap's spore cloud today; band-4 poison pools ride the same knobs. NOT a
## death intercept — death (credit, loot, respawn timer) proceeds normally and
## the cloud outlives the corpse. Tick damage means standing in it is the
## mistake and walking out is the dodge; the first tick is delayed one
## interval so stepping through a fresh cloud never feels like a trap.
##
## Late-joiner note: a player entering the instance MID-cloud won't see the
## visual (rp ops don't replay) — acceptable for seconds-long clouds; a
## permanent hazard would need to be a real replicated prop instead.

@export var radius: float = 48.0
@export var duration_s: float = 3.0
@export var tick_interval_s: float = 0.5
## Damage per tick as a fraction of the mob's AD — output tuning stays on the
## archetype's attack_damage, like every other knob.
@export var ad_ratio_per_tick: float = 0.35


func on_death(npc, _killer) -> bool:
	var zone: HazardZone = HazardZone.new()
	zone.radius = radius
	zone.duration_s = duration_s
	zone.tick_interval_s = tick_interval_s
	zone.damage_per_tick = maxf(0.0, npc.stats_component.get_stat(Stat.AD) * ad_ratio_per_tick)
	zone.source = npc
	# Plain sibling of the mob: runtime children are invisible to the
	# replication container's sync (it only tracks baked/dynamic ids).
	npc.add_sibling(zone)
	zone.global_position = npc.global_position
	npc.replicate_visual(&"rp_hazard_zone", [npc.global_position, radius, duration_s])
	return false # death proceeds — the cloud is a parting gift, not a save
