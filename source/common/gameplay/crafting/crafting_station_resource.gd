class_name CraftingStationResource
extends Resource
## Editor-authored crafting station. Assign one to a CraftingStation node's `station`
## field (inline, or a shared .tres dragged in). The server resolves the station from
## the player's map by the CraftingStation node's name, and the client renders the
## recipe list from the resource carried in the menu arg — no registry id needed.

@export var station_name: String = "Workbench"
## Which profession this station trains/uses — a skills key, e.g. &"smithing", &"cooking".
@export var profession: StringName = &"smithing"
## Flat gold fee charged per craft (0 = free). A small per-craft gold sink so
## crafted goods carry a natural price floor in player trade.
@export var craft_fee: int = 0
@export var recipes: Array[CraftingRecipe]
