class_name InstanceResource
extends Resource

## [DEFAULT] - uses default map spawn logic.
## [ENTRY] - spawn player on map entrance.
## [WORLD] - spawn player on default map spawn.
enum SpawnOverride {
	DEFAULT,
	ENTRY,
	WORLD
}

@export var instance_name: StringName
@export_file("*.tscn") var map_path: String
@export var load_at_startup: bool = false
@export var spawn_override: SpawnOverride = SpawnOverride.DEFAULT

@export_group("Zone display")
## Player-facing zone name ("Goblin Woodland"). Empty = capitalized instance_name.
@export var zone_title: String = ""
## The zone's intended level band. Shown as the banner subtitle ("Levels 1-5")
## and intended as the single source of truth for entry gating too — warper
## warnings and the future v1 wardstone can_join_instance check should read
## THESE numbers, not carry their own, so every door into a zone agrees. 0 = no band.
@export var level_min: int = 0
@export var level_max: int = 0
## Show the zone banner when a player enters this instance's map (see ZoneDiscovery).
@export var show_discovery: bool = false

var loading_instances: Array
var charged_instances: Array[Node]


## Banner title: explicit zone_title, else the instance_name prettified
## ("bandit_hideout" -> "Bandit Hideout").
func display_title() -> String:
	return zone_title if not zone_title.is_empty() else String(instance_name).capitalize()


## Banner subtitle from the level band ("Levels 1-5"); empty when no band is set.
func level_band() -> String:
	if level_min <= 0:
		return ""
	if level_max > level_min:
		return "Levels %d-%d" % [level_min, level_max]
	return "Level %d+" % level_min


@warning_ignore("unused_parameter")
func can_join_instance(player: Player, index: int = -1) -> bool:
	return true


func get_instance(index: int = -1) -> Node:
	if charged_instances.is_empty() or charged_instances.size() <= index:
		return null
	return charged_instances[index]
