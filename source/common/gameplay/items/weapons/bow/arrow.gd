class_name Projectile
extends Area2D

var speed: float = 200.0
var direction: Vector2 = Vector2.RIGHT

var piercing: bool = false
var pierce_left: int = 0
# OLD
var source: Node
var attack: Attack
# NEW
var effect: EffectSpec

func _ready() -> void:
	# Quick and dirty for tests - Need proper system
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
	else:
		var vosn := VisibleOnScreenNotifier2D.new()
		vosn.screen_exited.connect(queue_free)
		add_child(vosn)
	rotate(direction.angle())
	
	# One timer by bullet is bad practice.
	# TODO MOVE IT TO A MANAGER
	var timer: Timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)


func _physics_process(delta: float) -> void:
	position += speed * direction * delta


func _on_body_entered(body: Node2D) -> void:
	if body == source or not body.has_node(^"AbilitySystemComponent"):
		return
	var asc: AbilitySystemComponent = body.get_node(^"AbilitySystemComponent")
	var burn := BurnDotEffect.new()
	burn.name_id = &"RedBuffBurn"
	burn.duration = 3.0
	burn.period = 0.5
	asc.add_effect(burn, null)

	asc.apply_spec_server(
		effect,
		source.get_node(^"AbilitySystemComponent")
	)
	if not piercing or pierce_left <= 0:
		queue_free()
	pierce_left -= 1
