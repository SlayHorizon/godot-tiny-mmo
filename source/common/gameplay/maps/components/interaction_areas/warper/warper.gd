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
## Minimum character level to pass (0 = open to all). Enforced server-side at entry
## (denial goes to system chat); the Portal also pre-checks it client-side so the warp
## fade doesn't start for an attempt the server will refuse, and gates its label.
@export var required_level: int = 0


func _ready() -> void:
	# Self-register with the owning map (warp resolution + spawn positions).
	var map: Map = Map.of(self)
	if map != null:
		map.register_keyed(map.warpers, warper_id, self, "warper")


#func _init() -> void:
	#print(target_instance)
	#if target_instance:
		#body_entered.connect(_on_body_entered)
