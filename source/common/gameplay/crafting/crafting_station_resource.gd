class_name CraftingStationResource
extends Resource
## Editor-authored crafting station, registered as the "crafting_stations" content type
## (same workflow as ShopResource): create instances under a data folder, run the
## TinyMMO plugin's Generate for content_name "crafting_stations", and each station gets
## a registry id/slug baked into metadata so it resolves through ContentRegistryHub and
## travels over the network as a small id.

@export var station_name: String = "Workbench"
## Which profession this station trains/uses — a skills key, e.g. &"smithing", &"cooking".
@export var profession: StringName = &"smithing"
@export var recipes: Array[CraftingRecipe]


## Loads a station by its registry id, or null if the content type hasn't been generated
## yet / the id is unknown.
static func load_station(station_id: int) -> CraftingStationResource:
	if ContentRegistryHub.registry_of(&"crafting_stations") == null:
		return null
	return ContentRegistryHub.load_by_id(&"crafting_stations", station_id) as CraftingStationResource
