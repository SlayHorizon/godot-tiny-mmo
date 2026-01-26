extends NavPanel


@onready var grid_container: GridContainer = $ScrollContainer/GridContainer


func enter(payload: Dictionary = {}) -> void:
	if not payload.has("name"):
		return
	Client.request_data(
		&"guild.get.members",
		_on_members_list_received,
		{"q": payload["name"]}
	)


func _on_members_list_received(result: Dictionary) -> void:
	#request_id = 0
	for child: Control in grid_container.get_children():
		child.queue_free()
	for member: String in result.get("members", {}):
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(240, 65)
		button.text = member

		var player_id: int = result.get("members", {}).get(member, 0);print(player_id)

		button.pressed.connect(_on_member_button_pressed.bind(button, player_id))
		grid_container.add_child(button)


func _on_member_button_pressed(button: Button, player_id: int) -> void:
	ClientState.player_profile_requested.emit(player_id)
