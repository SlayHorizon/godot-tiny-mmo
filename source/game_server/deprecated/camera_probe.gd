# Only useful for debug purpose, shouldn't be on server side at all otherwise.
class_name CameraProbe
extends Camera2D

var mouse: MouseComponent

var desired_position: Vector2 = Vector2.ZERO

var direction: float = 0

var scrolling: Dictionary = {
	"desired": 1.0,
	"desired_speed": 25.0,
	"live": 1.0,
	"min": 0.5,
	"max": 10.0,
	"speed": 0.25
}

var speed_mul: Dictionary = {
	"desired": 1.0,
	"desired_speed": 25.0,
	"live": 1.0,
	"min": 1.0,
	"max": 5.0,
	"speed": 0.25
}

func _init() -> void:
	mouse = MouseComponent.new()
	add_child(mouse)

func _physics_process(_delta: float) -> void:
	if Input.is_action_pressed("action"):
		direction = atan2(mouse.position.y - global_position.y, mouse.position.x - global_position.x)
		
		global_position += Vector2.RIGHT.rotated(direction) * (global_position.distance_to(mouse.position) / 10) * speed_mul["live"]
	

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var ctrl: bool = Input.is_key_pressed(KEY_CTRL)
		
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if ctrl:
					speed_mul["desired"] = clampf(speed_mul["desired"] + speed_mul["speed"], speed_mul["min"], speed_mul["max"])
					return
					
				scrolling["desired"] = clampf(scrolling["desired"] + scrolling["speed"], scrolling["min"], scrolling["max"])
			MOUSE_BUTTON_WHEEL_DOWN:
				if ctrl:
					speed_mul["desired"] = clampf(speed_mul["desired"] - speed_mul["speed"], speed_mul["min"], speed_mul["max"])
					return
				
				scrolling["desired"] = clampf(scrolling["desired"] - scrolling["speed"], scrolling["min"], scrolling["max"])
	

func _process(_delta: float) -> void:
	queue_redraw()

	scrolling["live"] = move_toward(scrolling["live"], scrolling["desired"], _delta * scrolling["desired_speed"])
	speed_mul["live"] = move_toward(speed_mul["live"], speed_mul["desired"], _delta * speed_mul["desired_speed"])
	zoom = Vector2(scrolling["live"], scrolling["live"])

@onready var font_file: FontFile = FontFile.new()

func _draw() -> void:
	if Input.is_key_pressed(KEY_ALT):
		var screen_size: Vector2 = get_screen_transform().get_origin()
		font_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font_file.multichannel_signed_distance_field = true
		
		draw_string(font_file, Vector2(0, 30 / scrolling["live"]) - (screen_size / scrolling["live"]), "Zoom: " + str(scrolling["desired"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 32 / scrolling["live"])
		draw_string(font_file, Vector2(0, 60 / scrolling["live"]) - (screen_size / scrolling["live"]), "Speed*: " + str(speed_mul["desired"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 32 / scrolling["live"])
	
	if Input.is_action_pressed("action"):
		draw_line(Vector2.ZERO, mouse.position - global_position, Color.WHITE, 1.0)
