class_name CraftingStation
extends Interactable
## World-space click target that opens a crafting station (workbench, anvil, ...) —
## shown as the station's sprite. Just an Interactable preconfigured to open the
## crafting menu for its station; the click is inherited. The server resolves the
## station from the player's map by this node's name, so no registry id is needed.
##
## Setup: an Area2D with this script, a CollisionShape2D over the station, and a
## CraftingStationResource assigned. Place as a direct child of the Map.

@export var station: CraftingStationResource


func _ready() -> void:
	if station != null:
		menu_name = &"crafting"
	super._ready()


## Hand the crafting menu the station's catalog directly (rendered client-side) plus
## this node's name as the key the server resolves the station by.
func _build_menu_arg() -> Variant:
	return {"key": String(name), "station": station}
