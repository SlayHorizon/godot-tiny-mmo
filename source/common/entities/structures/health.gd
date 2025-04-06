extends HealthComponent


func apply_attack(attack: Attack) -> void:
	if attack.source.team:
		health -= attack.damage
