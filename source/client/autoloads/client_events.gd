extends Node
## Events Autoload (only for the client side)

signal open_door(door_id: int)
signal message_entered(message: String)
signal message_received(new_message: String, sender_name: String)

signal health_changed(new_value: float, is_max: bool)
