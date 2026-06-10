class_name SparTeam
extends Node2D
## One team of a spar station. Add as a CHILD of a DuelMaster; its Marker2D
## children ARE the team's spawn slots, so capacity = marker count. Give one team
## 1 marker and another 3 and you've authored a 1v3; add a third SparTeam and
## it's a three-way match. No code, just nodes.

## Optional display name. Empty = "Team N" by position under the station.
@export var team_name: String = ""


## The team's spawn slots, in child order. Capacity = size of this array.
func spawns() -> Array[Marker2D]:
	var out: Array[Marker2D] = []
	for child: Node in get_children():
		if child is Marker2D:
			out.append(child)
	return out


func capacity() -> int:
	return spawns().size()
