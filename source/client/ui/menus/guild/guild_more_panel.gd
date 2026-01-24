extends NavPanel


@export var guild_main: NavPanel
@export var edit_panel: NavPanel

var guild_details: Dictionary

@onready var edit_button: Button = $ScrollContainer/GridContainer/EditButton


func enter(payload: Dictionary = {}) -> void:
	if payload.is_empty():
		return
	guild_details = payload
	var permission: int = payload.get("permissions", Guild.Permissions.NONE)
	edit_button.disabled = (permission & Guild.Permissions.EDIT) == 0


func _on_edit_button_pressed() -> void:
	navigate_requested.emit(NavigationAction.PUSH, edit_panel, guild_details)


func _on_leave_button_pressed() -> void:
	DataSynchronizerClient._self.request_data(
		&"guild.quit",
		navigate_requested.emit.bind(NavigationAction.PUSH, guild_main, {}),
		{"guild_name": guild_details.get("name", "")}
	)
