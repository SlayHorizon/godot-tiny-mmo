extends NavPanel


@export var guild_details_panel: NavPanel

var request_id: int

@onready var result_container: VBoxContainer = $ScrollContainer/VBoxContainer


func enter(payload: Dictionary = {}) -> void:
	if request_id:
		Client.cancel_request_data(request_id)

	request_id = Client.request_data(
		&"guild.get.joined_guilds",
		_on_research_result_received
	).request_id



func _on_guild_button_pressed(button: Button, guild_name: String) -> void:
	Client.request_data(
		&"guild.get",
		_on_guild_data_received,
		{"q": guild_name}
	)


func _on_guild_data_received(data: Dictionary) -> void:
	navigate_requested.emit(NavigationAction.PUSH, guild_details_panel, data)


func _on_research_result_received(result: Dictionary) -> void:
	request_id = 0
	for child: Control in result_container.get_children():
		child.queue_free()
	for guild_name: String in result:
		var button: Button = Button.new()
		button.text = guild_name
		button.pressed.connect(_on_guild_button_pressed.bind(button, guild_name))
		result_container.add_child(button)
