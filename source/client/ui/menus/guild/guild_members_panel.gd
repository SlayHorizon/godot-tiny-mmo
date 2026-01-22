extends NavPanel


@onready var grid_container: GridContainer = $ScrollContainer/GridContainer


func enter(payload: Dictionary = {}) -> void:
	if not payload.has("name"):
		return
	DataSynchronizerClient._self.request_data(
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
		if result.get("members", {}).get(member, 2) == 0:
			button.text += " (Leader)"
		#button.pressed.connect(_on_guild_button_pressed.bind(button, guild_name))
		grid_container.add_child(button)
