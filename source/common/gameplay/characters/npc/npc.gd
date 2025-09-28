extends Character


var behavior: Callable = hostile_behavior
var arr: Array[Player]

var container: ReplicatedPropsContainer
var prop_id: int
var timer: float
var cooldown: float = 0.7

@onready var detection_area: Area2D = $DetectionArea


func _ready() -> void:
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	get_parent().ready.connect(func():
		container = get_parent()
		prop_id = container.child_id_of_node(self)
		container.set_baseline_ops(prop_id, [["rp_equip", ["wooden_bow.item"]]])
		container.queue_op(prop_id, "rp_equip", ["wooden_bow.item"])
		rp_equip("wooden_bow.item")
	)
	detection_area.body_entered.connect(_on_detection_area_body_entered)
	detection_area.body_exited.connect(_on_detection_area_body_exited)


func _physics_process(delta: float) -> void:
	#hostile_behavior()
	timer += delta
	if timer >= cooldown and arr:
		timer = 0
		var dir: Vector2 = global_position.direction_to(arr.front().global_position)
		#if equipped_weapon_right.can_use_weapon(0):
		equipped_weapon_right.perform_action(0, dir)
		container.queue_op(prop_id, "rp_attack", [dir])
			#rp_attack(dir)


func rp_equip(weapon_slug: String):
	var weapon: WeaponItem = ContentRegistryHub.load_by_slug(&"items", &"wooden_bow.item").duplicate(true)
	equipment_component.equip(weapon.slot.key, weapon)


func rp_attack(dir: Vector2):
	equipped_weapon_right.perform_action(0, dir)


func _on_detection_area_body_entered(body: Node2D) -> void:
	if body is Player:
		arr.append(body)


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body is Player:
		arr.erase(body)


func hostile_behavior(player: Player) -> void:
	pass
