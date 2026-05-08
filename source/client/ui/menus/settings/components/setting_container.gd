class_name SettingsContainer
extends Control


@export var show_on: Array[StringName]
@export var widgets: Array[SettingWidget]


func update_visibility(active_context: StringName) -> void:
    visible = active_context in show_on