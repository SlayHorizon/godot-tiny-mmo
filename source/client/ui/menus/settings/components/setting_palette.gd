extends SettingWidget

## Palette picker for the UI theme — drives BOTH the gateway and the in-game UI. Populates the
## controller OptionButton with the gateway palettes found on disk and persists the chosen slug to
## [gateway]/palette. Mirrors setting_language.gd. The gateway and the in-game HUD both live-apply
## the change via ClientState.settings.setting_changed, so no relaunch is needed.


func _ready() -> void:
	assert(is_instance_valid(controller) and controller is OptionButton)
	var options: OptionButton = controller
	for palette: StringName in ThemePalettes.list():
		var idx: int = options.item_count
		options.add_item(String(palette).capitalize(), idx)
		options.set_item_metadata(idx, palette)
	options.item_selected.connect(_on_palette_selected)
	_load_defaults()


func _on_palette_selected(index: int) -> void:
	var options: OptionButton = controller
	ClientState.settings.set_value(
		setting_section, setting_property, String(options.get_item_metadata(index))
	)


func _load_defaults() -> void:
	var saved: Variant = ClientState.settings.get_value(setting_section, setting_property)
	if saved == null:
		return
	var options: OptionButton = controller
	for idx: int in options.item_count:
		if String(options.get_item_metadata(idx)) == String(saved):
			options.select(idx)
			return
