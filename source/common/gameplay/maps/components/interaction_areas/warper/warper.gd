@icon("res://assets/node_icons/blue/icon_door.png")
class_name Warper
extends InteractionArea


@export var target_instance: InstanceResource
@export var warper_id: int = 0
@export var target_id: int = 0
## Seconds a body must stay inside before the warp fires. 0 = instant, the right feel
## for doors. Portals set this: the server re-checks overlap after the dwell (stepping
## out cancels), and the client times its warp fade to the same value.
@export var warp_delay_s: float = 0.0

## Extra dwell added when the entering player is under-leveled (below floor - 2):
## a HESITATION window where the warning shows on a clear screen BEFORE the
## fade/charge starts, so "stay = confirm, step out = cancel" is a real choice
## (without it the fade swallowed the warning instantly). Client (Portal) and
## server (_warp_after_dwell) both derive it from level + gate_level() —
## deterministic on both ends, no wire traffic.
const GATE_WARN_EXTRA_S: float = 2.5

## Visible SPIN-UP phase on every charging portal: the swirl revs on a clear
## screen for this long BEFORE the fade rises (owner call 2026-07-20 — the rev
## was invisible because the fade swallowed it instantly). Client delays its
## fade by this; the server adds the same span to its dwell. Doors
## (warp_delay_s = 0) are unaffected.
const SPIN_UP_S: float = 0.8


func _ready() -> void:
	# Self-register with the owning map (warp resolution + spawn positions).
	var map: Map = Map.of(self)
	if map != null:
		map.register_keyed(map.warpers, warper_id, self, "warper")


## The destination's intended level floor, read from the InstanceResource — the
## zone owns its numbers, doors just present them, so every door into a zone
## agrees (the old per-warper required_level export duplicated this and was
## retired 2026-07-19). Gating is SOFT in alpha per docs/pve_plan.md: the Portal
## warns below floor - 2 and the dwell is the confirm; the v1 wardstone key-gate
## will hard-enforce in InstanceResource.can_join_instance. 0 = open.
func gate_level() -> int:
	return target_instance.level_min if target_instance != null else 0


## The hesitation window for a player of [param level]: GATE_WARN_EXTRA_S when
## they'd be warned (below floor - 2), else 0.
func warn_extra_for(level: int) -> float:
	return GATE_WARN_EXTRA_S if gate_level() > 0 and level < gate_level() - 2 else 0.0


## The destination's required wardstone (docs/wardstones.md) — the ONE hard
## access rule (levels stay advisory). &"" = open.
func required_stone() -> StringName:
	return target_instance.required_wardstone if target_instance != null else &""


#func _init() -> void:
	#print(target_instance)
	#if target_instance:
		#body_entered.connect(_on_body_entered)
