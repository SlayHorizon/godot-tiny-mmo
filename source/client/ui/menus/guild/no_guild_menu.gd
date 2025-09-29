extends GuildPanel


@export var search_panel: GuildPanel
@export var create_panel: GuildPanel


func _on_search_guild_button_pressed() -> void:
	swap_requested.emit(search_panel, {})


func _on_create_guild_button_pressed() -> void:
	swap_requested.emit(create_panel, {})
