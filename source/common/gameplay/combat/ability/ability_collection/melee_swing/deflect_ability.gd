class_name DeflectAbility
extends AbilityResource
## A brief defensive PARRY: a blue bubble flashes around you, and any projectile that
## enters it is destroyed (a "reflect" read — see DeflectBubble). Omnidirectional and
## purely defensive — NO damage (it's a guard, not a slash; the sword's offense lives
## in Whirlwind/Berserk). Resolve branch, sword.
##
## The bubble is spawned on EVERY peer (use_ability runs client + server via the action
## echo) AND predicted on the caster (predict_use) so it pops the incoming shot in real
## time, not one round-trip late. A matching is_deflecting window is opened server-side
## too — a damage backstop for the rare point-blank shot that starts already inside the
## bubble's edge. See CombatHit.try_damage's deflectable path.


## How long the parry bubble lasts (= the projectiles-destroyed window).
@export var deflect_window_s: float = 0.45
## Bubble radius — the visible parry range.
@export var bubble_radius: float = 45.0
## Bubble tint (blue = the Resolve / defensive branch).
@export var bubble_color: Color = Color(0.42, 0.66, 1.0)


func use_ability(user: Entity, _direction: Vector2) -> void:
	_deflect(user)


func predict_use(user: Entity, _direction: Vector2) -> void:
	# Caster-side: raise the bubble the instant the button is pressed.
	_deflect(user)


func _deflect(user: Entity) -> void:
	if user is not Character:
		return
	var character: Character = user as Character
	character.open_deflect(deflect_window_s)  # server damage backstop
	_spawn_bubble(character)


## Spawns (or refreshes) the parry bubble on [param character]. Idempotent so the
## caster's predicted bubble and the server echo's bubble don't stack into two.
func _spawn_bubble(character: Character) -> void:
	var existing: Node = character.get_node_or_null(^"DeflectBubble")
	if existing != null:
		existing.queue_free()
	var bubble: DeflectBubble = DeflectBubble.new()
	bubble.name = "DeflectBubble"
	bubble.radius = bubble_radius
	bubble.duration = deflect_window_s
	bubble.color = bubble_color
	bubble.position = Vector2(0.0, -10.0)  # centre on the torso, not the feet
	character.add_child(bubble)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Destroys projectiles for %ss" % fmt_num(deflect_window_s))
	lines.append("%dpx parry radius" % int(bubble_radius))
	return lines
