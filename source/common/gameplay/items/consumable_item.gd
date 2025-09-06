class_name ConsumableItem
extends Item


@export var effects: Array[GameplayEffect] = []
@export var shared_cooldown_ms: int = 1500
@export var cooldown_category: StringName = &"potion"
## initial charges per single copy if 1 can use the potion one time, if 2 can use the potion 2 times for example.
@export var default_charges: int = 1


func can_use(player: Player) -> bool:
	return false
	#var charges := stack.get_int(&"charges", default_charges)
	#if charges <= 0:
		#return false
	#if asc.has_method("cooldown_ready"):
		#return asc.cooldown_ready(cooldown_category)
	#return true


func on_use(character: Character) -> void:
	pass
#func on_use(asc: Node, stack: ItemStack) -> bool:
	#if not can_use(asc, stack):
		#return false
	#for e in effects:
		#asc.add_effect(e)
	#if asc.has_method("trigger_cooldown"):
		#asc.trigger_cooldown(cooldown_category, shared_cooldown_ms)
	## decrement charges (per-copy state lives in stack.data)
	#var charges := stack.get_int(&"charges", default_charges)
	#charges -= 1
	#stack.set_int(&"charges", max(0, charges))
	# If stackable, the inventory system can also reduce stack.count
	#return true
