class_name FloatingDamageNumber
extends Node2D
## Spawns at a world position, displays a damage amount, tweens upward while
## fading, and frees itself. Generic — used by every weapon's hit feedback
## via the combat.hit push.

## How far upward the number rises across its lifetime.
const RISE_DISTANCE: float = 28.0
## Total lifetime (rise + fade run in parallel).
const LIFETIME: float = 0.9
## Horizontal jitter so back-to-back hits don't stack into one unreadable
## blob.
const JITTER_X: float = 12.0

@onready var label: Label = $Label

var _amount: int = 0
var _spawn_position: Vector2


## Set before adding to the tree so [member label] has the value when it
## wakes up.
func set_amount(amount: int) -> void:
	_amount = amount
	if label != null:
		label.text = str(amount)


## Pass the world-space spawn position BEFORE add_child. _ready uses this
## to seed the tween's start point — if we set global_position AFTER
## add_child instead, _ready has already created a tween against (0,0) and
## the number snaps to a wrong location.
func set_spawn(pos: Vector2) -> void:
	_spawn_position = pos


func _ready() -> void:
	label.text = str(_amount)
	# Random horizontal offset for visual variety. Use roundi to keep the
	# number on a whole pixel — labels at fractional positions blur badly
	# under the project's stretched 960x540 base resolution.
	var jitter: int = int(round(randf_range(-JITTER_X, JITTER_X)))
	global_position = _spawn_position + Vector2(jitter, 0)

	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, ^"global_position:y", global_position.y - RISE_DISTANCE, LIFETIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, ^"modulate:a", 0.0, LIFETIME)\
		.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
