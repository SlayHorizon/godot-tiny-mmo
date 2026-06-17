class_name DungeonExit
extends Interactable
## A "leave the dungeon" station — place it at the entrance/spawn (where players
## respawn on death). Click → the dungeon-exit confirm (→ recall to town, drop from
## the run). Just an Interactable preconfigured with its menu; the click plumbing is
## inherited. (Recall works as the universal escape too; this is the obvious one.)


func _ready() -> void:
	menu_name = &"dungeon_exit"
	super._ready()
