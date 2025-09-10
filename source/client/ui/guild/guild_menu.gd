extends Control


var current_guild: Dictionary
var _cached_guild_data: Dictionary[StringName, Dictionary]
var guild_data: Dictionary


func _ready() -> void:
	InstanceClient.current.request_data(&"guild/self", func(d: Dictionary): current_guild = d)


func search_guild(guild_name: String) -> void:
	pass


func _on_close_button_pressed() -> void:
	hide()


func _on_visibility_changed() -> void:
	if visible:
		prepare_menu()


func prepare_menu() -> void:
	print_debug(current_guild)
	if current_guild and not current_guild.is_empty():
		var guild_name: String = current_guild.get("guild", "")
		if guild_name:
			$GuildDisplay/MarginContainer/VBoxContainer/Label.text = guild_name
			$GuildDisplay.show()
	else:
		$NoGuildMenu.show()


func _on_button_pressed() -> void:
	$NoGuildMenu.hide()
	$CreateGuildMenu.show()
