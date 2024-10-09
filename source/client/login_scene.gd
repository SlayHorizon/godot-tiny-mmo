class_name LoginScene
extends Node


@onready var login_menu: LoginMenu = $CanvasLayer/LoginMenu


func _ready() -> void:
	login_menu.connection_succeed.connect(_on_connection_succeed)


func _on_connection_succeed() -> void:
	add_sibling(preload("res://source/client/ui/ui.tscn").instantiate())
	queue_free.call_deferred()
