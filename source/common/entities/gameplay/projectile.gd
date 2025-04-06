class_name Projectile


var source: Entity
var attack: Attack


func _on_body_entered(body: Node2D):
	if body is Entity:
		body = body as Entity
		
		# Check if not has health_component, if true, return.
		if not body.health_component:
			return
		
		# If the entity has no team (neutral) or belongs to a different team, apply attack.
		if not body.team or body.team.team_id != source.team.team_id:
				body.health_component.apply_attack(attack)
