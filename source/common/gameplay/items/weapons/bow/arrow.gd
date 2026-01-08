class_name Projectile
extends Area2D

var speed: float = 300.0
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
		monitoring = true
		area_entered.connect(_on_area_entered)
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


func _on_area_entered(area: Area2D) -> void:
	# Check if this is a HurtBox
	if area.name != "HurtBox":
		return
	
	# Get the Character parent from the HurtBox
	var character: Character = area.get_parent() as Character
	if not character:
		return
	
	if character == source:
		return
	
	# Damage logic:
	# - NPCs can always damage players (regardless of PvP)
	# - Players can always damage NPCs
	# - Players can only damage other players in PvP zones
	if character is Player:
		# Target is a Player
		# If source is not a Player (i.e., it's an NPC), allow damage regardless of PvP
		if not (source is Player):
			_apply_damage_to_character(character)
		# If source is a Player, only damage in PvP
		elif source is Player and character.is_pvp():
			_apply_damage_to_character(character)
	else:
		# Target is an NPC (or other Character that's not a Player)
		# Players can always damage NPCs - this should work for player arrows hitting NPCs
		_apply_damage_to_character(character)


func _on_body_entered(body: Node2D) -> void:
	# Legacy support - but prefer area_entered for HurtBox
	if body == source or not body.has_node(^"AbilitySystemComponent"):
		return
	
	# Only apply damage if it's not a player, or if PvP is enabled
	if body is Player:
		# NPCs can always damage players (source is not a Player)
		if not (source is Player):
			_apply_damage_to_character(body as Character)
		# Players can only damage other players in PvP
		elif source is Player and body.is_pvp():
			_apply_damage_to_character(body as Character)
	else:
		_apply_damage_to_character(body as Character)


func _apply_damage_to_character(character: Character) -> void:
	if not character or not character.has_node(^"AbilitySystemComponent"):
		return
	
	# Don't damage dead characters
	if character.is_dead:
		return
	
	var asc: AbilitySystemComponent = character.ability_system_component
	var damage_source: Character = source as Character
	asc.apply_damage(10, damage_source)

	#var burn := BurnDotEffect.new()
	#burn.name_id = &"RedBuffBurn"
	#burn.duration = 3.0
	#burn.period = 0.5
	#asc.add_effect(burn, null)
	#asc.set_attribute_value(&"health")
	#asc.apply_spec_server(
		#effect,
		#source.get_node(^"AbilitySystemComponent")
	#)
	if not piercing or pierce_left <= 0:
		queue_free()
	pierce_left -= 1
