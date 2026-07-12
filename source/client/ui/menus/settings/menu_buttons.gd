extends Control


@export var navigator: Navigator
@export var close_button: Button

@export_category("Gameplay")
@export var gameplay_panel: NavPanel
@export var gameplay_button: Button

@export_category("Graphics")
@export var graphics_panel: NavPanel
@export var graphics_button: Button

@export_category("Controls")
@export var controls_panel: NavPanel
@export var controls_button: Button


func _ready() -> void:
	gameplay_button.pressed.connect(_on_gameplay_button_pressed)
	graphics_button.pressed.connect(_on_graphics_button_pressed)
	controls_button.pressed.connect(_on_controls_button_pressed)
	close_button.pressed.connect(navigator.back)
	# The navigator sets its initial panel in ITS _ready (after this one),
	# and never touches the sidebar toggles — sync once everything is up.
	_sync_pressed_state.call_deferred()


# Press the sidebar button of the panel the navigator is showing.
# set_pressed_no_signal bypasses the ButtonGroup, so every button is synced.
func _sync_pressed_state() -> void:
	var buttons: Dictionary = {
		gameplay_panel: gameplay_button,
		graphics_panel: graphics_button,
		controls_panel: controls_button,
	}
	for panel: NavPanel in buttons:
		buttons[panel].set_pressed_no_signal(panel == navigator.current)


func _on_gameplay_button_pressed() -> void:
	navigator.replace(gameplay_panel, {})


func _on_graphics_button_pressed() -> void:
	navigator.replace(graphics_panel, {})


func _on_controls_button_pressed() -> void:
	navigator.replace(controls_panel, {})
