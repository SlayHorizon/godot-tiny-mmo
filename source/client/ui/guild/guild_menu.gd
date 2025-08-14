extends Control


var guild_data: Dictionary


func _ready() -> void:
	Events.data_received.connect(_on_data_received)
	Events.data_requested.emit("guild")


func _on_data_received(data: Dictionary, data_type: String) -> void:
	if data.is_empty() or data_type != "guild":
		return
	data = guild_data
	if visible:
		prepare_menu()


func _on_close_button_pressed() -> void:
	hide()


func _on_visibility_changed() -> void:
	if visible and guild_data:
		prepare_menu()


func prepare_menu() -> void:
	var guild_name: String = guild_data.get("guild", "")
	if guild_name:
		$GuildDisplay/MarginContainer/VBoxContainer/Label.text = guild_name
		$GuildDisplay.show()
	else:
		$NoGuildMenu.show()


func _on_button_pressed() -> void:
	$NoGuildMenu.hide()
	$CreateGuildMenu.show()
