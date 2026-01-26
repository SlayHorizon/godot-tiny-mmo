extends Control


@onready var friends_container: VBoxContainer = $PanelContainer/VBoxContainer/ScrollContainer/VBoxContainer


func _ready() -> void:
	pass


func fill_friend_list(payload: Dictionary) -> void:
	for node: Node in friends_container.get_children():
		node.queue_free()
	for friend_id: int in payload:
		var button: Button = Button.new()
		var friend_payload: Dictionary = payload.get(friend_id, {})
		var friend_name: String = friend_payload.get("name", "Unknown")
		var is_online: bool = friend_payload.get("online", false)
		button.text = friend_name + "(Online)" if is_online else "(Offline)"
		button.custom_minimum_size = Vector2(200, 90)
		button.pressed.connect(_on_friend_button_pressed.bind(friend_id))
		friends_container.add_child(button)


func _on_friend_button_pressed(player_id: int) -> void:
	hide()
	ClientState.player_profile_requested.emit(player_id)


func _on_close_buttonn_pressed() -> void:
	hide()


func _on_visibility_changed() -> void:
	if visible:
		Client.request_data(&"friend.list", fill_friend_list)
