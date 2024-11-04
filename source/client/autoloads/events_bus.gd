extends Node
## Events Autoload (only for the client side)

# Map object
signal open_door(door_id: int)

# Chat
signal message_entered(message: String)
signal message_received(new_message: String, sender_name: String)

# HUD
signal health_changed(new_value: float, is_max: bool)
signal item_icon_pressed(item_name: String)
