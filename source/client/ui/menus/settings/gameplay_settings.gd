extends NavPanel


@export var hsliders: Array[HSlider]


func _ready() -> void:
    for slider: HSlider in hsliders:
        slider.drag_ended.connect(_on_slider_drag_ended.bind(slider))


func enter(_payload: Dictionary = {}) -> void:
    update_buttons()


func _on_slider_drag_ended(value_changed: bool, slider: HSlider) -> void:
    if not value_changed: return
    if slider.has_meta(&"property_name"):
        var property_name: StringName = slider.get_meta(&"property_name")
        ClientState.settings.set_value(&"gameplay", property_name, slider.value)


func update_buttons() -> void:
    var settings: Dictionary = ClientState.settings.data
    var section: StringName = &"gameplay"
    if not settings.has(section): return

    for slider: HSlider in hsliders:
        var property_name: StringName = slider.get_meta(&"property_name", &"none")
        if settings[section].has(property_name):
            slider.set_value_no_signal(settings[section][property_name])