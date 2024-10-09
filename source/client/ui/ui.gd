class_name UI
extends CanvasLayer

const HUD_SCENE = preload("res://source/client/ui/hud/hud.tscn")

#var hud: CanvasLayer:
	#get():
		#if not hud:
			#hud = HUD_SCENE.instantiate()
			#add_child(hud)
			#if not hud.is_node_ready():
				#await hud.ready
		#return hud
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	pass
