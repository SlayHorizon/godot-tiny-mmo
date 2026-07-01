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
