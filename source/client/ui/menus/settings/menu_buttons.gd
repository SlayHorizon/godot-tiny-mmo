extends Control


@export var navigator: Navigator
@export var close_button: Button
@export var button_group: ButtonGroup

var panels: Dictionary[StringName, NavPanel] = {}


func _ready() -> void:
    for button: Button in button_group.get_buttons():
        var target_panel: StringName = button.get_meta(&"target_panel", &"none")
        if target_panel == navigator.initial_panel.name:
            button.set_pressed_no_signal(true)
            break
    
    for panel: NavPanel in navigator.nav_panels:
        panels[panel.name] = panel

    close_button.pressed.connect(_on_close_button_pressed)
    button_group.pressed.connect(_on_button_pressed)


func _on_button_pressed(button: Button) -> void:
    if not button.has_meta(&"target_panel"): return
    var target_panel: StringName = button.get_meta(&"target_panel")
    if target_panel in panels:
        navigator.replace(panels[target_panel], {})


func _on_close_button_pressed() -> void:
    navigator.back()