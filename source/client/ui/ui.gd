class_name UI
extends CanvasLayer

## In-game UI root. The full-screen menus mount under a sibling Control ("Submenu") of the HUD, both
## under THIS CanvasLayer — and a CanvasLayer breaks theme inheritance up to the root Window, so each
## Control child must be themed directly (this used to assign the static `Client.theme`). We pick the
## variant matching the shared [gateway]/palette setting, so the single Settings "Theme" picker reskins
## BOTH the gateway and the in-game UI; live-applied on change, no relaunch.

@onready var hud: Control = $HUD


func _ready() -> void:
	_apply_palette(_saved_palette())
	ClientState.settings.setting_changed.connect(_on_setting_changed)


## Load the theme variant for [palette] and assign it to every Control child (HUD + Submenu). Falls
## back to the horizon master if that palette has no generated theme.
func _apply_palette(palette: StringName) -> void:
	var ui_theme: Theme = ThemePalettes.theme(palette)
	for child: Node in get_children():
		if child is Control:
			(child as Control).theme = ui_theme


## The saved palette slug from the shared client settings (the same key the gateway picker writes).
func _saved_palette() -> StringName:
	var saved: Variant = ClientState.settings.get_value(&"gateway", &"palette")
	return StringName(saved) if saved is String or saved is StringName else ThemePalettes.DEFAULT


## Live-apply a palette change made in the Settings menu — no relaunch. Persistence is the widget's job.
func _on_setting_changed(section: StringName, property: StringName, value: Variant) -> void:
	if section == &"gateway" and property == &"palette" and (value is String or value is StringName):
		_apply_palette(StringName(value))
