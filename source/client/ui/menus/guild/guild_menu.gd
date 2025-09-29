extends Control


var current_guild: Dictionary:
	set = _set_current_guild
var _cached_guild_data: Dictionary[StringName, Dictionary]
var guild_data: Dictionary

# UI
var current_panel: GuildPanel
var history: Array[Control]


func _ready() -> void:
	InstanceClient.current.request_data(&"guild.self", _set_current_guild)
	# Hide all by default.
	for child: Control in get_children():
		if child is GuildPanel:
			child.back_requested.connect(_on_guild_panel_back_requested.bind(child))
			child.swap_requested.connect(_on_guild_panel_swap_requested.bind(child))
			child.hide()
	if visible: _on_visibility_changed();


func _on_guild_panel_back_requested(guild_panel: GuildPanel) -> void:
	guild_panel.hide()
	if history.size():
		current_panel = history.pop_back()
		current_panel.open({})
		current_panel.show()
	else:
		hide()


func _on_guild_panel_swap_requested(target: GuildPanel, data: Dictionary, origin: GuildPanel) -> void:
	current_panel = target
	
	origin.hide()
	history.append(origin)
	target.show()
	target.open(data)


func _on_close_button_pressed() -> void:
	if current_panel and history.size():
		_on_guild_panel_back_requested(current_panel)
	else:
		hide()


func _on_visibility_changed() -> void:
	if visible:
		if not current_panel:
			if current_guild.is_empty():
				current_panel = $NoGuildMenu
			else:
				current_panel = $GuildDisplay
			current_panel.open(current_guild)
			current_panel.show()
		else:
			current_panel.show()


func _set_current_guild(new_guild: Dictionary) -> void:
	current_guild = new_guild
	if visible:
		_on_visibility_changed()
