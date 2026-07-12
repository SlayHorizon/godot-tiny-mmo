class_name WeaponAttack
extends MobAttack
## Fires the mob's MOUNTED weapon ability at a policy-picked target (refactor
## P2 — extracted from HostileNpc._perform_ranged_attack). The server fires
## the real (damaging) projectile — the same one players shoot — and clients
## replay the shot visual via rp_shoot. Requires the archetype (or the placed
## node's override) to set a WeaponItem; an unarmed mob's WeaponAttack simply
## never fires and the next attack in the array takes the swing.


func _fire(npc) -> bool:
	var mounted: Weapon = npc.equipment_component.mounted_nodes.get(&"weapon")
	if mounted == null:
		return false
	var target: Player = _pick_enemy(npc)
	if target == null:
		return false
	var direction: Vector2 = npc.global_position.direction_to(target.global_position)
	mounted.auto_attack(direction)
	npc.replicate_visual(&"rp_shoot", [direction])
	return true
