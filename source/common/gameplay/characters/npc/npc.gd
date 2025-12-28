extends Character


signal display_name_changed(new_name: String)

var behavior: Callable = hostile_behavior
var arr: Array[Player]

var display_name: String = "Goblin":
	set = _set_display_name

var container: ReplicatedPropsContainer
var prop_id: int
var timer: float
var cooldown: float = 0.7
var is_charging: bool = false
var charge_start_time: float = 0.0
var charge_direction: Vector2 = Vector2.ZERO

@onready var detection_area: Area2D = $DetectionArea


func _ready() -> void:
	# Call parent _ready() first to set up base character functionality
	super._ready()
	
	# Initialize display name (triggers signal for label update on client)
	if not multiplayer.is_server():
		display_name_changed.emit(display_name)
		set_physics_process(false)
		return
	
	# Initialize NPC health and stats BEFORE connecting watchers
	# This prevents the watcher from being called with 0.0 and triggering death
	var asc: AbilitySystemComponent = ability_system_component
	asc.set_attribute_value(Stat.HEALTH_MAX, 100.0)
	asc.set_attribute_value(Stat.HEALTH, 100.0)
	
	# Connect to death signal
	asc.entity_died.connect(_on_npc_died)
	
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
	if not multiplayer.is_server():
		return
	
	# Don't process if dead
	if is_dead:
		return
	
	if is_charging:
		var now: float = Time.get_ticks_msec() / 1000.0
		var weapon: Weapon = equipment_component._mounted.get(&"weapon", null)
		var charge_time: float = 0.4  # Default charge time
		if weapon and "charge_time_s" in weapon:
			charge_time = weapon.charge_time_s
		
		if now - charge_start_time >= charge_time:
			# Release the arrow
			if equipment_component.can_use(&"weapon", 1):
				equipment_component._mounted[&"weapon"].perform_action(1, charge_direction)
				container.queue_op(prop_id, "rp_attack_release", [charge_direction])
			is_charging = false
		return
	
	timer += delta
	if timer >= cooldown and arr:
		timer = 0
		if equipment_component.can_use(&"weapon", 0):
			var dir: Vector2 = global_position.direction_to(arr.front().global_position)
			equipment_component._mounted[&"weapon"].perform_action(0, dir)
			container.queue_op(prop_id, "rp_attack", [dir])
			# Start charging
			is_charging = true
			charge_start_time = Time.get_ticks_msec() / 1000.0
			charge_direction = dir


func rp_equip(weapon_slug: String):
	var weapon: WeaponItem = ContentRegistryHub.load_by_slug(&"items", &"wooden_bow.item").duplicate(true)
	equipment_component.equip(weapon.slot.key, weapon)


func rp_attack(dir: Vector2):
	equipment_component._mounted[&"weapon"].perform_action(0, dir)


func rp_attack_release(dir: Vector2):
	equipment_component._mounted[&"weapon"].perform_action(1, dir)


func _on_detection_area_body_entered(body: Node2D) -> void:
	if body is Player:
		arr.append(body)


func _on_detection_area_body_exited(body: Node2D) -> void:
	if body is Player:
		arr.erase(body)


func hostile_behavior(player: Player) -> void:
	pass


func _set_display_name(new_name: String) -> void:
	display_name = new_name
	if not multiplayer.is_server():
		display_name_changed.emit(new_name)


func _on_npc_died(entity: Character, killer: Character) -> void:
	# Stop AI behavior
	arr.clear()
	is_charging = false
	# Disable detection area
	if detection_area:
		detection_area.set_deferred("monitoring", false)
	# Death animation and movement disable handled by Character._on_health_changed
	# Optionally despawn after delay - for now just leave dead NPCs
