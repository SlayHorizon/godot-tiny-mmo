extends GuildPanel


@export var display_panel: GuildPanel

var request_id: int

@onready var result_container: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer
@onready var search_bar: LineEdit = $MarginContainer/VBoxContainer/LineEdit


func _on_line_edit_text_submitted(new_text: String) -> void:
	if request_id:
		InstanceClient.current.cancel_request_data(request_id)
	request_id = InstanceClient.current.request_data(&"guild/search/" + new_text, _on_research_result_received)
	


func _on_research_result_received(result: Dictionary) -> void:
	request_id = 0
	for child: Control in result_container.get_children():
		child.queue_free()
	for guild_name: String in result:
		var button: Button = Button.new()
		button.text = guild_name
		button.pressed.connect(_on_guild_button_pressed.bind(button, guild_name))
		result_container.add_child(button)


func _on_guild_button_pressed(button: Button, guild_name: String) -> void:
	InstanceClient.current.request_data(&"guild/get/" + guild_name, _on_guild_data_received)


func _on_guild_data_received(data: Dictionary) -> void:
	swap_requested.emit(display_panel, data)


func _on_search_guild_button_pressed() -> void:
	var to_search: String = search_bar.text
	if to_search.is_empty() or to_search.length() > 10:
		return
	
	if request_id:
		InstanceClient.current.cancel_request_data(request_id)
	request_id = InstanceClient.current.request_data(
		&"guild/search/" + to_search,
		_on_research_result_received
	)
