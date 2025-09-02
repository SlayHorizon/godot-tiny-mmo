# PropsAccess.gd
class_name PropsAccess
extends Node


const META: StringName = &"rp_container"


static func get_owner_container(prop: Node) -> ReplicatedPropsContainer:
	var container: ReplicatedPropsContainer = prop.get_meta(META, null)
	return container


#static func set_props_access()


static func container_for(n: Node) -> ReplicatedPropsContainer:
	# lookup O(1) if taged
	if n.has_meta(META):
		var c: Variant = n.get_meta(META)
		if is_instance_valid(c):
			return c as ReplicatedPropsContainer
		# meta stale : on purge
		n.remove_meta(META)

	# fallback: on remonte UNE FOIS, puis on tag pour O(1) futur
	var cur := n
	while cur:
		if cur is ReplicatedPropsContainer:
			n.set_meta(META, cur)
			return cur
		cur = cur.get_parent()
	return null


static func notify(n: Node, field_id: int, value: Variant, only_if_changed := true) -> void:
	var c := container_for(n)
	if c:
		c.mark_by_node(n, field_id, value, only_if_changed)
