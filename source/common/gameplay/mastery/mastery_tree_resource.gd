class_name MasteryTreeResource
extends Resource
## A weapon category's full mastery tree. Branch grouping lives on the nodes
## themselves (MasteryNode.branch). One .tres per category in
## res://source/common/gameplay/mastery/trees/ — MasteryService discovers them
## by folder and keys them by [member category].


@export var category: StringName
@export var display_name: String
@export var nodes: Array[MasteryNode]


func get_node_by_id(node_id: StringName) -> MasteryNode:
	for node: MasteryNode in nodes:
		if node.id == node_id:
			return node
	return null


## Sum of every node's cost — design target: equals the points available at
## mastery cap, so a capped player can own the whole tree.
func total_cost() -> int:
	var total: int = 0
	for node: MasteryNode in nodes:
		total += node.tier
	return total
