@tool
extends EditorScript
## Editor-only tool. Scans the project's gathering nodes + crafting stations
## and rewrites every JobPerks `.tres` with the matching
## `source_items` / `source_levels` and `recipe_items` / `recipe_levels`
## arrays. Eliminates the hand-maintained content drift on the Jobs UI's
## Sources / Recipes tabs.
##
## **Run it:** open this file in the script editor, then [b]File → Run[/b]
## (Ctrl+Shift+X). The summary is printed to the Output panel.
##
## What it scans:
##   • [code]mineable_nodes/[/code] — each MineableNodeResource's
##     [code]job_xp[/code] dict says which jobs the node feeds; its
##     [code]ore[/code] item + [code]required_level[/code] are appended to
##     each of those jobs' source list.
##   • [code]crafting/resources/[/code] — each CraftingStationResource's
##     [code]profession[/code] field is the target job; every recipe's
##     [code]output_item[/code] + [code]required_level[/code] is appended
##     to that job's recipe list.
##
## Dedup rule: when the same item shows up multiple times for one job (e.g.
## two veins of iron with different level gates), the LOWEST required level
## wins so the Sources tab shows the entry-level requirement.

const JOBS_DIR: String = "res://source/common/gameplay/jobs/"
const NODES_DIR: String = "res://source/common/gameplay/maps/components/mineable_nodes/"
const STATIONS_DIR: String = "res://source/common/gameplay/crafting/resources/"


func _run() -> void:
	print("[bake_source_slugs] start")

	# job_slug → { Item → required_level (min so far) }
	var sources_by_job: Dictionary[StringName, Dictionary] = {}
	var recipes_by_job: Dictionary[StringName, Dictionary] = {}

	_scan_mineable_nodes(sources_by_job)
	_scan_crafting_stations(recipes_by_job)

	_apply_to_job_perks(sources_by_job, recipes_by_job)

	print("[bake_source_slugs] done")


# ---------------------------------------------------------------------------
# Scan: mineable nodes → which jobs get fed which ores (with level gates)
# ---------------------------------------------------------------------------

func _scan_mineable_nodes(out: Dictionary[StringName, Dictionary]) -> void:
	for path in _list_tres(NODES_DIR):
		var res: Resource = load(path)
		if not (res is MineableNodeResource):
			continue
		var node_res: MineableNodeResource = res
		if node_res.ore == null:
			push_warning("MineableNodeResource %s has no ore — skipping." % path)
			continue
		for job: StringName in node_res.job_xp:
			_record_min(out, job, node_res.ore, node_res.required_level)
		print("  source: %s (lv %d) → %s" % [
			node_res.ore.resource_path.get_file(),
			node_res.required_level,
			str(node_res.job_xp.keys())
		])


# ---------------------------------------------------------------------------
# Scan: crafting stations → which job gets which recipe outputs
# ---------------------------------------------------------------------------

func _scan_crafting_stations(out: Dictionary[StringName, Dictionary]) -> void:
	for path in _list_tres(STATIONS_DIR):
		var res: Resource = load(path)
		if not (res is CraftingStationResource):
			continue
		var station: CraftingStationResource = res
		var job: StringName = station.profession
		if job == &"":
			push_warning("CraftingStationResource %s has no profession — skipping." % path)
			continue
		var added: Array[String] = []
		for recipe: CraftingRecipe in station.recipes:
			if recipe == null or recipe.output_item == null:
				continue
			_record_min(out, job, recipe.output_item, recipe.required_level)
			added.append(recipe.output_item.resource_path.get_file())
		print("  recipes (%s): %s" % [String(job), str(added)])


# ---------------------------------------------------------------------------
# Apply: write each JobPerks .tres
# ---------------------------------------------------------------------------

func _apply_to_job_perks(
	sources_by_job: Dictionary[StringName, Dictionary],
	recipes_by_job: Dictionary[StringName, Dictionary]
) -> void:
	for path in _list_tres(JOBS_DIR):
		var res: Resource = load(path)
		if not (res is JobPerks):
			continue
		var jp: JobPerks = res

		var s_items: Array[Item] = []
		var s_levels: Array[int] = []
		_flatten_sorted(sources_by_job.get(jp.job_slug, {}), s_items, s_levels)
		jp.source_items = s_items
		jp.source_levels = s_levels

		var r_items: Array[Item] = []
		var r_levels: Array[int] = []
		_flatten_sorted(recipes_by_job.get(jp.job_slug, {}), r_items, r_levels)
		jp.recipe_items = r_items
		jp.recipe_levels = r_levels

		var err: int = ResourceSaver.save(jp, path)
		if err != OK:
			push_error("Failed to save %s (err %d)" % [path, err])
			continue
		print("  baked %s: sources=%d recipes=%d" % [path, s_items.size(), r_items.size()])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Record (item, level) — keeping the MIN level seen so far if the item
## was already recorded for this job. That way a content authoring mistake
## of two veins for the same ore at different levels doesn't randomly pick.
func _record_min(
	out: Dictionary[StringName, Dictionary],
	job: StringName,
	item: Item,
	level: int
) -> void:
	if not out.has(job):
		out[job] = {}
	var bucket: Dictionary = out[job]
	if bucket.has(item):
		bucket[item] = mini(int(bucket[item]), level)
	else:
		bucket[item] = level


## Flatten a {Item: level} bucket into parallel arrays, sorted by required
## level ascending then item name. Stable output → stable git diffs.
func _flatten_sorted(
	bucket: Dictionary,
	out_items: Array[Item],
	out_levels: Array[int]
) -> void:
	var pairs: Array = []
	for item: Item in bucket:
		pairs.append([item, int(bucket[item])])
	pairs.sort_custom(func(a, b):
		if a[1] != b[1]:
			return a[1] < b[1]
		return String(a[0].item_name) < String(b[0].item_name))
	for p: Array in pairs:
		out_items.append(p[0])
		out_levels.append(p[1])


## Lists every `.tres` directly inside [param dir] (non-recursive — current
## content folders are flat). Returns absolute res:// paths.
func _list_tres(dir: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		push_warning("Could not open dir: %s" % dir)
		return out
	d.list_dir_begin()
	var entry: String = d.get_next()
	while entry != "":
		if not d.current_is_dir() and entry.ends_with(".tres"):
			out.append(dir + entry)
		entry = d.get_next()
	d.list_dir_end()
	return out
