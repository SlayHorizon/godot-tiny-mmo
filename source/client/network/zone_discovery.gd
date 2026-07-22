class_name ZoneDiscovery
## Region banners (client-only cosmetic), DATA-DRIVEN by InstanceResource: an
## instance opts in by setting show_discovery (+ zone_title / level_min / max)
## on its .tres in instance_collection/ — the same folder the server's
## name-lookup scans, so a resource parked elsewhere still warps via direct ref
## but won't banner. No code edit per biome.
##
## EVERY entry into an opted-in map shows the zone text (it's the only surface
## with the biome name + level band today — no world map yet; owner call
## 2026-07-19). The true FIRST visit on this install gets the full ceremony
## (sound + long dwell); repeats are a quieter, shorter echo so portal-hopping
## never gets noisy. First-visit persistence is a local ConfigFile by owner
## decision (2026-07-19): zero server/DB work, and a reinstall re-showing the
## fanfare is harmless. NOTE: user:// is shared across F5 multi-client runs.

const SAVE_PATH: String = "user://discovered_zones.cfg"

## Map scene stem -> its InstanceResource (only show_discovery ones), built
## lazily from the same instance_collection scan the server does — client
## builds carry the .tres files, so this stays purely client-side.
static var _zones_by_stem: Dictionary = {}
static var _indexed: bool = false


## Called by InstanceManagerClient when a map scene finished loading. The banner
## waits out the warp fade (delay) before showing.
static func on_map_loaded(map_path: String) -> void:
	if not _indexed:
		_build_index()
	var stem: String = _stem_of(map_path)
	var zone: InstanceResource = _zones_by_stem.get(stem, null)
	if zone == null:
		return

	var config: ConfigFile = ConfigFile.new()
	config.load(SAVE_PATH) # A missing file is fine — first discovery creates it.
	var first_visit: bool = not bool(config.get_value("discovered", stem, false))
	if first_visit:
		config.set_value("discovered", stem, true)
		config.save(SAVE_PATH)

	# First visit = the unlock ceremony (eyebrow + sound + long dwell); repeats
	# are a plain quiet zone-text echo.
	Announcer.announce(zone.display_title(), zone.level_band(), {
		"delay": 1.0,
		"sound": first_visit,
		"duration": 3.0 if first_visit else 1.8,
		"eyebrow": "New region discovered" if first_visit else "",
	})


static func _build_index() -> void:
	_indexed = true
	for file_path: String in FileUtils.get_all_file_at(InstanceManagerServer.INSTANCE_COLLECTION_PATH, "*.tres"):
		# Untyped load, same as the server's scan: the custom-class loader isn't
		# guaranteed registered when this first runs in an export.
		var loaded: Resource = ResourceLoader.load(file_path)
		if loaded == null or not (loaded is InstanceResource):
			continue
		var res: InstanceResource = loaded
		if not res.show_discovery:
			continue
		var stem: String = _stem_of(res.map_path)
		if not stem.is_empty():
			_zones_by_stem[stem] = res


## The zone whose portal [param stone] unlocks — pretty title for the grant
## ceremony's "The way to X is open." line. Empty if no listed zone requires it
## (the ceremony falls back to a generic line).
static func zone_unlocked_by(stone: String) -> String:
	if not _indexed:
		_build_index()
	for zone: InstanceResource in _zones_by_stem.values():
		if String(zone.required_wardstone) == stone:
			return zone.display_title()
	return ""


## The scene-file stem is the join key between the charge_new_instance map_path
## and an InstanceResource's map_path. Either side may be authored as uid://
## (fungus_cave was; woodland res://) — resolve before comparing.
static func _stem_of(map_path: String) -> String:
	if map_path.begins_with("uid://"):
		var uid: int = ResourceUID.text_to_id(map_path)
		if uid == ResourceUID.INVALID_ID or not ResourceUID.has_id(uid):
			return ""
		map_path = ResourceUID.get_id_path(uid)
	return map_path.get_file().get_basename()
