extends NavPanel


@export var guild_details_panel: NavPanel

var request_id: int

@onready var result_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer
@onready var search_bar: LineEdit = $VBoxContainer/LineEdit


func _on_line_edit_text_submitted(new_text: String) -> void:
	if request_id:
		DataSynchronizerClient.cancel_request_data(request_id)

	request_id = DataSynchronizerClient._self.request_data(
		&"guild.search",
		_on_research_result_received,
		{"q": new_text}
	).request_id
	


func _on_guild_button_pressed(button: Button, guild_name: String) -> void:
	DataSynchronizerClient._self.request_data(
		&"guild.get",
		_on_guild_data_received,
		{"q": guild_name}
	)


func _on_guild_data_received(data: Dictionary) -> void:
	navigate_requested.emit(NavigationAction.PUSH, guild_details_panel, data)


func _on_search_guild_button_pressed() -> void:
	var to_search: String = search_bar.text
	if to_search.is_empty() or to_search.length() > 10:
		return

	if request_id:
		DataSynchronizerClient.cancel_request_data(request_id)

	request_id = DataSynchronizerClient._self.request_data(
		&"guild.search",
		_on_research_result_received,
		{"q": to_search}
	).request_id


func _on_research_result_received(result: Dictionary) -> void:
	request_id = 0
	for child: Control in result_container.get_children():
		child.queue_free()
	for guild_name: String in result:
		var button: Button = Button.new()
		button.text = guild_name
		button.pressed.connect(_on_guild_button_pressed.bind(button, guild_name))
		result_container.add_child(button)
