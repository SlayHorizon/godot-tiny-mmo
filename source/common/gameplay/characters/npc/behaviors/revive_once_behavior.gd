class_name ReviveOnceBehavior
extends MobBehavior
## Second wind, staged like LoL's Guardian Angel (owner call 2026-07-10): the
## first time each life this mob would die, everyone SEES it die — death anim,
## body on the ground — then after [member down_s] it stands back up at
## [member revive_health_fraction] of max HP with a spawn burst and goes
## straight for whoever "killed" it. An instant revive read as a confusing
## self-heal; a body that visibly falls and gets back up is legible drama, and
## the down window doubles as a breather to reposition.
##
## While down the mob is damage-immune (is_dead stays latched, so take_damage
## no-ops — same rule as GA) and grants nothing: the on_death intercept runs
## before kill credit, loot, or the died signal ever fire. The "once" resets
## on respawn (behavior scratch clears each fresh life). A boss/elite knob —
## pair it with a phase change for the classic "it gets back up" beat.

@export var revive_health_fraction: float = 0.5
## How long the body lies there before standing back up.
@export var down_s: float = 1.6


func on_death(npc, killer) -> bool:
	var scratch: Dictionary = runtime_state(npc)
	if scratch.get("used", false):
		return false # already spent — this death is real
	scratch["used"] = true
	scratch["wake_at_ms"] = Time.get_ticks_msec() + int(down_s * 1000.0)
	scratch["killer"] = killer
	# Deliberately loud (revives are rare): proves the intercept ran when
	# playtesting reads confusing. journalctl/editor console, server-side.
	printerr("[SRV NPC %s] second wind: DOWN for %.1fs" % [npc.enemy_type, down_s])
	# Look properly dead: death anim syncs to every client, body stays down.
	# is_dead remains latched (take_damage set it just before die()), which is
	# exactly the GA immunity — no hit lands while the body is on the ground.
	npc.anim = Character.Animations.DEATH
	npc.velocity = Vector2.ZERO
	npc.targeted_player = null
	npc._state_owner = self
	npc.enemy_state = HostileNpc.EnemyState.REVIVING
	return true


func process_state(npc) -> void:
	var scratch: Dictionary = runtime_state(npc)
	if Time.get_ticks_msec() < int(scratch.get("wake_at_ms", 0)):
		return # still down — the chassis skips leash/regen/targeting meanwhile
	# Stand back up.
	npc.is_dead = false
	var hmax: float = npc.stats_component.get_stat(Stat.HEALTH_MAX)
	npc.stats_component.set_stat(Stat.HEALTH, maxf(1.0, hmax * revive_health_fraction))
	npc.anim = Character.Animations.IDLE
	npc.replicate_visual(&"rp_spawn_effect", [])
	printerr("[SRV NPC %s] second wind: BACK UP at %.0f HP" % [
		npc.enemy_type, npc.stats_component.get_stat(Stat.HEALTH)
	])
	# Come back swinging, not confused: the reviver remembers who dropped it.
	var killer: Variant = scratch.get("killer")
	if killer is Player and is_instance_valid(killer) \
			and not (killer as Player).is_dead and npc._is_hostile_to(killer as Player):
		npc.targeted_player = killer as Player
		npc.enemy_state = HostileNpc.EnemyState.CHASE
	else:
		npc._abandon_target()
	scratch.erase("killer")
