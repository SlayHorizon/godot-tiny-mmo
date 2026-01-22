extends NavPanel


@export var guild_search_panel: NavPanel
@export var guild_create_panel: NavPanel
@export var my_guilds_panel: NavPanel


func _on_search_guild_button_pressed() -> void:
	navigate_requested.emit(NavigationAction.PUSH, guild_search_panel, {})


func _on_create_guild_button_pressed() -> void:
	navigate_requested.emit(NavigationAction.PUSH, guild_create_panel, {})


func _on_my_guilds_button_pressed() -> void:
	navigate_requested.emit(NavigationAction.PUSH, my_guilds_panel, {})
