class_name Projectile
extends Area2D


var source: Entity
var attack: Attack
var speed: float = 200.0
var direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	# Quick and dirty for tests - Need proper system
	if OS.has_feature("client"):
		var vosn := VisibleOnScreenNotifier2D.new()
		vosn.screen_exited.connect(queue_free)
		add_child(vosn)
	rotate(direction.angle())
	# One timer by bullet is bad practice.
	var timer: Timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	add_child(timer)


func _physics_process(delta: float) -> void:
	position += speed * direction * delta


#func _on_body_entered(body: Node2D) -> void:
	#if body == source:
		#return
	#if body is Entity:
		#if not body.health_component:
			#return
	#queue_free()
