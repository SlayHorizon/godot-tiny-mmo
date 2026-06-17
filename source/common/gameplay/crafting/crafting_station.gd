class_name CraftingStation
extends Interactable
## World-space click target that opens a crafting station (workbench, anvil, ...) —
## shown as the station's sprite. Just an Interactable preconfigured to open the
## crafting menu for its station; the click is inherited. The server validates the
## station id against the map.
##
## Setup: an Area2D with this script, a CollisionShape2D over the station, and a
## CraftingStationResource assigned. Place as a direct child of the Map.

@export var station: CraftingStationResource


func _ready() -> void:
	if station != null:
		menu_name = &"crafting"
		menu_arg = int(station.get_meta(&"id", 0))
	super._ready()
