extends Control


@export var navigator: Navigator
@export var close_button: Button

@export_category("Gameplay")
@export var gameplay_panel: NavPanel
@export var gameplay_button: Button

@export_category("Controls")
@export var controls_panel: NavPanel
@export var controls_button: OptionButton


func _ready() -> void:
	for input_type: String in InputComponent.InputType.keys():
		var item_id: int = (controls_button.item_count - 1) + 1
		var text: String = input_type.replace("_", " & ").capitalize()
		controls_button.add_item(text, item_id)
		controls_button.set_item_metadata(item_id, input_type)

	controls_button.select(0)

	gameplay_button.pressed.connect(_on_gameplay_button_pressed)
	controls_button.item_selected.connect(_on_controls_item_selected)
	close_button.pressed.connect(navigator.back)


func _on_gameplay_button_pressed() -> void:
	navigator.replace(gameplay_panel, {})


func _on_controls_item_selected(index: int) -> void:
	var option: String = controls_button.get_item_metadata(index)
	controls_button.select(0)
	controls_button.set_pressed_no_signal(true)
	if not option: return
	navigator.replace(controls_panel, {"input_type": option})
