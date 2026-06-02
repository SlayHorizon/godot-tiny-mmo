@tool
extends EditorScript
## Editor-only tool. Scans the project's gathering nodes + crafting stations
## and rewrites every JobPerks `.tres` with the matching `source_slugs` and
## `recipe_slugs` arrays. Eliminates the hand-maintained content drift on the
## Jobs UI's Sources / Recipes tabs.
##
## **Run it:** open this file in the script editor, then [b]File → Run[/b]
## (Ctrl+Shift+X). The summary is printed to the Output panel.
##
## What it scans:
##   • [code]mineable_nodes/[/code] — each MineableNodeResource's
##     [code]job_xp[/code] dict tells which jobs it feeds; the [code]ore[/code]
##     resource path's basename becomes the slug appended to those jobs.
##   • [code]crafting/resources/[/code] — each CraftingStationResource's
##     [code]profession[/code] field is the target job; every recipe's
##     [code]output_item[/code] basename becomes a recipe slug for that job.
##
## What it writes:
##   • Every JobPerks .tres has its [code]source_slugs[/code] and
##     [code]recipe_slugs[/code] replaced with the scanned, sorted, deduped
##     lists. Other fields untouched. Save is via ResourceSaver so UIDs and
##     authoring formatting Godot owns stay intact.

const JOBS_DIR: String = "res://source/common/gameplay/jobs/"
const NODES_DIR: String = "res://source/common/gameplay/maps/components/mineable_nodes/"
const STATIONS_DIR: String = "res://source/common/gameplay/crafting/resources/"


func _run() -> void:
	print("[bake_source_slugs] start")

	var sources_by_job: Dictionary[StringName, Array] = {}
	var recipes_by_job: Dictionary[StringName, Array] = {}

	_scan_mineable_nodes(sources_by_job)
	_scan_crafting_stations(recipes_by_job)

	# Sort + dedupe so the order is stable across re-runs (avoids spurious
	# git diffs when the bake order shifts).
	for job in sources_by_job:
		sources_by_job[job] = _sort_unique(sources_by_job[job])
	for job in recipes_by_job:
		recipes_by_job[job] = _sort_unique(recipes_by_job[job])

	_apply_to_job_perks(sources_by_job, recipes_by_job)

	print("[bake_source_slugs] done")


# ---------------------------------------------------------------------------
# Scan: mineable nodes → which jobs get fed which ore slugs
# ---------------------------------------------------------------------------

func _scan_mineable_nodes(out: Dictionary[StringName, Array]) -> void:
	for path in _list_tres(NODES_DIR):
		var res: Resource = load(path)
		if not (res is MineableNodeResource):
			continue
		var node_res: MineableNodeResource = res
		if node_res.ore == null:
			push_warning("MineableNodeResource %s has no ore — skipping." % path)
			continue
		var slug: String = _slug_from_resource(node_res.ore)
		for job: StringName in node_res.job_xp:
			if not out.has(job):
				out[job] = []
			out[job].append(slug)
		print("  source: %s → %s" % [slug, str(node_res.job_xp.keys())])


# ---------------------------------------------------------------------------
# Scan: crafting stations → which job gets which recipe-output slugs
# ---------------------------------------------------------------------------

func _scan_crafting_stations(out: Dictionary[StringName, Array]) -> void:
	for path in _list_tres(STATIONS_DIR):
		var res: Resource = load(path)
		if not (res is CraftingStationResource):
			continue
		var station: CraftingStationResource = res
		var job: StringName = station.profession
		if job == &"":
			push_warning("CraftingStationResource %s has no profession — skipping." % path)
			continue
		if not out.has(job):
			out[job] = []
		var added: Array[String] = []
		for recipe: CraftingRecipe in station.recipes:
			if recipe == null or recipe.output_item == null:
				continue
			var slug: String = _slug_from_resource(recipe.output_item)
			out[job].append(slug)
			added.append(slug)
		print("  recipes (%s): %s" % [String(job), str(added)])


# ---------------------------------------------------------------------------
# Apply: write each JobPerks .tres
# ---------------------------------------------------------------------------

func _apply_to_job_perks(
	sources_by_job: Dictionary[StringName, Array],
	recipes_by_job: Dictionary[StringName, Array]
) -> void:
	for path in _list_tres(JOBS_DIR):
		var res: Resource = load(path)
		if not (res is JobPerks):
			continue
		var jp: JobPerks = res
		var sources_typed: Array[String] = []
		for s: String in sources_by_job.get(jp.job_slug, []):
			sources_typed.append(s)
		var recipes_typed: Array[String] = []
		for s: String in recipes_by_job.get(jp.job_slug, []):
			recipes_typed.append(s)
		jp.source_slugs = sources_typed
		jp.recipe_slugs = recipes_typed
		var err: int = ResourceSaver.save(jp, path)
		if err != OK:
			push_error("Failed to save %s (err %d)" % [path, err])
			continue
		print("  baked %s: sources=%d recipes=%d" % [path, sources_typed.size(), recipes_typed.size()])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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


## "res://.../items/materials/copper_ore.tres" → "copper_ore". Matches the
## hand-authored slug convention currently used in the JobPerks .tres files.
func _slug_from_resource(res: Resource) -> String:
	return res.resource_path.get_file().get_basename()


func _sort_unique(arr: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for v in arr:
		if seen.has(v):
			continue
		seen[v] = true
		out.append(v)
	out.sort()
	return out
