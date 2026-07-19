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


#func _init() -> void:
	#print(target_instance)
	#if target_instance:
		#body_entered.connect(_on_body_entered)
