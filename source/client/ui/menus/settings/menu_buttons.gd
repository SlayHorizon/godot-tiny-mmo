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


func _on_gameplay_button_pressed() -> void:
	navigator.replace(gameplay_panel, {})


func _on_graphics_button_pressed() -> void:
	navigator.replace(graphics_panel, {})


func _on_controls_button_pressed() -> void:
	navigator.replace(controls_panel, {})
