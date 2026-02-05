extends NavPanel


@export var guild_details_panel: NavPanel

var request_id: int

@onready var line_edit: LineEdit = $MarginContainer/VBoxContainer/LineEdit
@onready var confirm_button: Button = $MarginContainer/VBoxContainer/Button


func _on_line_edit_text_submitted(new_text: String) -> void:
	request_create_guild(new_text)


func _on_button_pressed() -> void:
	request_create_guild(line_edit.text)


func request_create_guild(guild_name: String) -> void:
	if line_edit.text.is_empty() or request_id:
		return
	
	line_edit.editable = false
	confirm_button.disabled = true
	
	guild_name.strip_edges(true, true)
	guild_name = guild_name.substr(0, 21)
	
	request_id = Client.request_data(
		&"guild.create",
		_on_guild_create_response,
		{"name": guild_name},
		InstanceClient.current.name
	).request_id


func _on_guild_create_response(data: Dictionary) -> void:
	if data.has("error"):
		$MarginContainer/VBoxContainer/Label.text = data.get("message", "error")
	if data.has("name"):
		ClientState.active_guild_id = data.get("id", 0)
		navigate_requested.emit(NavigationAction.REPLACE, guild_details_panel, data)
