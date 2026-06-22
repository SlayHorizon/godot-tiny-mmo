extends Control
## Character window shell. A banner header holds the window title on the left,
## the Stats / Jobs / Mastery toggle tabs in the centre, and a Close button on
## the right. Selecting a tab swaps which content panel is visible; each panel
## self-drives its own data (stats watch the local player, jobs/quests fetch
## from the server when shown).

@onready var _tabs: Dictionary[StringName, Button] = {
	&"stats": %StatsTab,
	&"jobs": %JobsTab,
	&"mastery": %MasteryTab,
}
@onready var _panels: Dictionary[StringName, Control] = {
	&"stats": %StatsContent,
	&"jobs": %JobsContent,
	&"mastery": %MasteryContent,
}

var _current: StringName = &"stats"


func _ready() -> void:
	for tab_name: StringName in _tabs:
		_tabs[tab_name].pressed.connect(_select.bind(tab_name))
	%CloseButton.pressed.connect(_on_close_button_pressed)
	_select(_current)


## Switches the active tab. Toggle state + panel visibility both follow the
## selection so a deselected tab can't visually stick "pressed".
func _select(tab_name: StringName) -> void:
	_current = tab_name
	for key: StringName in _tabs:
		_tabs[key].button_pressed = (key == tab_name)
		_panels[key].visible = (key == tab_name)


func _on_close_button_pressed() -> void:
	hide()
