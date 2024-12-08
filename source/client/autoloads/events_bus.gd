extends Node
## Events Autoload (only for the client side)
## Should be removed on non-client exports.

# Map object
signal open_door(door_id: int)

# Chat
signal message_submitted(message: String)
signal message_received(message: String, sender_name: String)

# HUD
signal health_changed(new_value: float, is_max: bool)
signal item_icon_pressed(item_name: String)
