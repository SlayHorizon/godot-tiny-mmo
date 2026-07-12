extends NavPanel


## Curated remap categories: which player_* actions show in the Controls tab,
## grouped and ordered. Diffed against InputComponent.get_game_actions_list()
## at build time, so a new action can never silently miss the menu.
const REMAP_CATEGORIES: Array[Dictionary] = [
	{
		&"title": "Movement",
		&"show_on": [&"MOUSE_KEYBOARD", &"GAMEPAD"],
		&"actions": [&"player_move_up", &"player_move_down", &"player_move_left", &"player_move_right"],
	},
	{
		&"title": "Combat",
		&"show_on": [&"MOUSE_KEYBOARD", &"GAMEPAD"],
		&"actions": [&"player_shoot", &"player_special", &"player_special_2"],
	},
	{
		&"title": "Actions",
		&"show_on": [&"MOUSE_KEYBOARD", &"GAMEPAD"],
		&"actions": [
			&"player_interact", &"player_chat", &"player_recall",
			&"player_quickslot_1", &"player_quickslot_2", &"player_quickslot_3",
		],
	},
	{
		&"title": "Aim",
		&"show_on": [&"GAMEPAD"],
		&"actions": [&"player_look_up", &"player_look_down", &"player_look_left", &"player_look_right"],
	},
]

const REMAP_ROW: PackedScene = preload("res://source/client/ui/menus/settings/components/setting_remap.tscn")


@export var input_type_title: Label
@export var input_type_tabs: HBoxContainer
@export var settings_containers: Array[SettingsContainer]

var _active_input_type: String
var _remap_rows_built: bool


func enter(payload: Dictionary = {}) -> void:
	_build_input_type_tabs()
	_build_remap_rows()
	if is_instance_valid(input_type_title):
		input_type_title.text = "Controls"
	_select_input_type(payload.get("input_type", _default_input_type()))


## Build one toggle button per input type (Mouse & Keyboard / Gamepad / Touch), once.
func _build_input_type_tabs() -> void:
	if not is_instance_valid(input_type_tabs) or input_type_tabs.get_child_count() > 0:
		return
	var group: ButtonGroup = ButtonGroup.new()
	for input_type: String in InputComponent.InputType.keys():
		var button: Button = Button.new()
		button.text = input_type.replace("_", " & ").capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"FlatButton"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 44)
		button.set_meta(&"input_type", input_type)
		button.pressed.connect(_select_input_type.bind(input_type))
		input_type_tabs.add_child(button)


## Build the keybind rows from REMAP_CATEGORIES, once. Every player_* action
## in the InputMap must land in a category — anything uncovered is warned
## about loudly instead of silently staying unbindable.
func _build_remap_rows() -> void:
	if _remap_rows_built or not is_instance_valid(input_type_tabs):
		return
	_remap_rows_built = true

	var rows_parent: Node = input_type_tabs.get_parent()
	var covered: Array[StringName]
	for category: Dictionary in REMAP_CATEGORIES:
		var container: SettingsContainer = SettingsContainer.new()
		container.name = StringName(category[&"title"])
		container.show_on.assign(category[&"show_on"])
		container.visible = false

		var header: Label = Label.new()
		header.text = category[&"title"]
		container.add_child(header)

		for action_name: StringName in category[&"actions"]:
			if not InputMap.has_action(action_name):
				push_warning("controls: unknown action '%s' in REMAP_CATEGORIES." % action_name)
				continue
			var row: SettingWidget = REMAP_ROW.instantiate()
			row.setting_property = action_name
			container.add_child(row)
			container.widgets.append(row)
			covered.append(action_name)

		rows_parent.add_child(container)
		settings_containers.append(container)

	for action_name: StringName in InputComponent.get_game_actions_list():
		if not action_name in covered:
			push_warning("controls: action '%s' is in no remap category — players can't rebind it." % action_name)

	var reset_button: Button = Button.new()
	reset_button.text = "Reset to Defaults"
	reset_button.custom_minimum_size = Vector2(180, 40)
	reset_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset_button.pressed.connect(_reset_active_to_defaults)
	rows_parent.add_child(reset_button)


## The tab shown when Controls is opened without an explicit type.
func _default_input_type() -> String:
	var keys: Array = InputComponent.InputType.keys()
	return String(keys[0]) if not keys.is_empty() else "MOUSE_KEYBOARD"


## Show the settings for [input_type] and reflect the active tab.
func _select_input_type(input_type: String) -> void:
	_active_input_type = input_type
	_update_containers_visibility(input_type)
	_update_remap_buttons(input_type.to_lower())
	if is_instance_valid(input_type_tabs):
		# Sync EVERY tab: set_pressed_no_signal bypasses the ButtonGroup's
		# exclusivity, so the previous tab must be unpressed explicitly or it
		# keeps its active style after leaving and re-entering the panel.
		for button: Button in input_type_tabs.get_children():
			button.set_pressed_no_signal(button.get_meta(&"input_type", "") == input_type)


## Writes the active input type's shipped defaults back over the player's
## overrides (keybinds AND feel settings like deadzones), then refreshes rows.
func _reset_active_to_defaults() -> void:
	var section: StringName = StringName(_active_input_type.to_lower())
	var defaults: Dictionary = ClientState.settings.get_defaults_section(section)
	for property: StringName in defaults:
		ClientState.settings.set_value(section, property, defaults[property])

	for container: SettingsContainer in settings_containers:
		for widget: SettingWidget in container.widgets:
			if is_instance_valid(widget):
				widget.refresh()


func _update_containers_visibility(section: String) -> void:
	if settings_containers.is_empty(): return
	for container: SettingsContainer in settings_containers:
		container.update_visibility(section)


func _update_remap_buttons(section: String) -> void:
	if settings_containers.is_empty(): return
	for container: SettingsContainer in settings_containers:
		for widget: SettingWidget in container.widgets:
			if not widget is SettingRemapWidget: continue
			widget.setting_section = section
