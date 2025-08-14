extends Area2D


@export_enum("blue", "gold") var coin_type: String = "blue"

@onready var coin_anim: AnimatedSprite2D = $AnimatedSprite2D

var collected: bool = false


func _ready() -> void:
	coin_anim.play(coin_type + "_coin")
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body is Player or collected:
		return
	
	# To be sure it's called once.
	collected = true
	
	var container: ReplicatedPropsContainer = PropsAccess.get_owner_container(self)
	if not container:
		return
	
	var prop_id: int = container.child_id_of_node(self)
	var is_dynamic: bool = prop_id > ReplicatedPropsContainer.STATIC_MAX
	
	if is_dynamic:
		# Show for current viewers + remove for everyone (late joiners won't see it).
		container.queue_op(prop_id, "rp_collect", [true])  # delete_after = true
		container.queue_despawn(prop_id)
	else:
		# Baseline by function: newcomers will execute rp_pause() instantly.
		container.set_baseline_ops(prop_id, [["rp_pause", []]])
		rp_pause()
		# Live viewers get the pretty animation (no removal).
		container.queue_op(prop_id, "rp_collect", [false])
		# # Demo respawn 5s later (server authoritative)
		var timer: Timer = Timer.new()
		timer.wait_time = 15.0
		timer.one_shot = true
		timer.timeout.connect(
			func():
				container.queue_op(prop_id, "rp_unpause", [])
				rp_unpause()
				timer.queue_free()
		)
		add_child(timer)
		timer.start()


# Client-side ops (pure visuals)


func rp_collect(delete: bool) -> void:
	coin_anim.play(&"collected")
	coin_anim.animation_finished.connect(
		queue_free if delete else rp_pause,
		CONNECT_ONE_SHOT
	)


func rp_pause() -> void:
	hide()
	$CollisionShape2D.set_deferred(&"disabled", true)
	set_deferred(&"monitoring", false)


func rp_unpause() -> void:
	coin_anim.play(coin_type + "_coin")
	$CollisionShape2D.set_deferred(&"disabled", false)
	set_deferred(&"monitoring", true)
	show()
	collected = false
