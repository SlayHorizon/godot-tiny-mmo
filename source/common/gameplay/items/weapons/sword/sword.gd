extends Weapon


var cooldown: float = 1.0
var last_used: float = -INF


func _ready() -> void:
	super._ready()
	if character.animation_player.has_animation_library(&"weapon"):
		return
	character.animation_player.add_animation_library(
		&"weapon",
		animation_libraries[&"weapon"]
	)


func try_perform_action(action_index: int, direction: Vector2) -> bool:
	if not can_use_weapon(action_index):
		return false
	
	perform_action(action_index, direction)

	return true


func can_use_weapon(action_index: int) -> bool:
	return (Time.get_ticks_msec() / 1000.0) - last_used >= cooldown


func perform_action(action_index: int, direction: Vector2) -> void:
	last_used = Time.get_ticks_msec() / 1000.0
	#print_debug("perform action")
	character.animation_tree[&"parameters/OnFoot/RightOneShot/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
