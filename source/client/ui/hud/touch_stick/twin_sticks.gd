extends Control


@export var move_stick: TouchStick
@export var shoot_stick: TouchStick
@export var enabled: bool:
    set(value):
        enabled = value
        set_enabled(value)


func _ready() -> void:
    set_enabled(enabled)


func set_enabled(enable: bool) -> void:
    visible = enable
    if is_instance_valid(move_stick):
        move_stick.enabled = enable
    if is_instance_valid(shoot_stick):
        shoot_stick.enabled = enable