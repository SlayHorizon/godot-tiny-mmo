extends Node
class_name HealthComponent

# To-do: Display damage in game like with label text -20 
@export var hurtbox: Area2D
@export var progress_bar: ProgressBar

var health: float = 10.0
var max_health: float = 10.0


#func _init(_health: float, _max_health: float) -> void:
	#health = _health
	#max_health = _max_health


func _ready() -> void:
	if hurtbox:
		hurtbox.area_entered.connect(_on_hurt_box_area_entered)
	if progress_bar:
		progress_bar.min_value = 0.0
		progress_bar.max_value = max_health
		progress_bar.value = health


func apply_attack(attack: Attack) -> void:
	health -= attack.damage
	if progress_bar:
		progress_bar.value = health


func _on_hurt_box_area_entered(area: Area2D) -> void:
	if area is Projectile and area.attack and area.attack.source != owner:
		apply_attack(area.attack)
