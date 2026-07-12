class_name MobBehavior
extends Resource
## Base for composable server-side mob behaviors (docs/hostile_npc_refactor.md).
##
## A behavior RESOURCE holds tuning (@exports) and stateless logic; it is
## SHARED between every mob of an archetype, so per-mob runtime scratch goes
## through [method runtime_state], never member vars. Behaviors run on the
## SERVER only (HostileNpc._physics_process is server-gated); client visuals
## replay via the npc's rp_* primitives ([method HostileNpc.replicate_visual]).
##
## `npc` params are deliberately untyped (duck-typed HostileNpc) to avoid a
## resource<->node class-reference cycle — the same dodge the state-sync
## hooks use for Character (see docs/netcode_smoothness.md).


## Called each physics tick while the mob is in CHASE, with the current
## distance to its target. Return true to TAKE OVER the state machine (the
## npc records this behavior as state owner; it then drives its own enum
## states via [method process_state] until it hands control back by setting
## enemy_state to a chassis state).
func try_start(_npc, _distance_to_target: float, _now: int) -> bool:
	return false


## Drives a state this behavior owns (called from the npc's state match while
## npc._state_owner == self).
func process_state(_npc) -> void:
	pass


## Death hook (refactor P4), server-side — called by HostileNpc.die BEFORE the
## death commits (state sync, kill credit, loot, respawn timer). Return true to
## INTERCEPT: the behavior brought the mob back (see ReviveOnceBehavior) and
## die() aborts with zero credit leaked. Return false to let death proceed —
## side effects welcome (see DeathBurstBehavior's spore cloud).
func on_death(_npc, _killer) -> bool:
	return false


## Per-mob runtime scratch for this behavior (cooldown stamps, locked
## positions...). Keyed by the shared resource on the npc, so N mobs of one
## archetype never bleed state into each other.
func runtime_state(npc) -> Dictionary:
	return npc.behavior_state.get_or_add(self, {})
