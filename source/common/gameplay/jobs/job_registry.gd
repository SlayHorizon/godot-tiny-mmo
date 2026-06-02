class_name JobRegistry
## Single source of truth for which jobs exist. Each entry maps a job's
## internal slug to its [JobPerks] resource. Adding a new job is now a
## **content** change: drop a `<name>.tres` under jobs/ and add one line
## here.
##
## `static var` (not `const`) because preload() expressions, while
## constant-folded at parse time, can't initialise typed `const Dictionary`
## with class-shaped values in GDScript 4 — `Assigned value isn't a
## constant expression`. `static var` initialises lazily, no issue.

static var JOBS: Dictionary[StringName, JobPerks] = {
	&"mining": preload("res://source/common/gameplay/jobs/mining.tres"),
	&"harvesting": preload("res://source/common/gameplay/jobs/harvesting.tres"),
	&"smithing": preload("res://source/common/gameplay/jobs/smithing.tres"),
	&"tailoring": preload("res://source/common/gameplay/jobs/tailoring.tres"),
	&"leatherworking": preload("res://source/common/gameplay/jobs/leatherworking.tres"),
}


## True if [param job_slug] is a registered job. Cheap dict lookup, callable
## from anywhere.
static func has_job(job_slug: StringName) -> bool:
	return JOBS.has(job_slug)


## The [JobPerks] for [param job_slug], or null if unknown. Callers get a
## typed reference so static dispatch on perks methods is clean:
##   var perks: JobPerks = JobRegistry.perks_for(&"mining")
##   if perks != null:
##       var mult: float = perks.xp_multiplier(skill["perks"])
static func perks_for(job_slug: StringName) -> JobPerks:
	return JOBS.get(job_slug, null)


## Human-readable label for [param job_slug]. Falls back to a capitalised
## slug if the job is unknown — UI never crashes on a typo.
static func display_name(job_slug: StringName) -> String:
	var p: JobPerks = perks_for(job_slug)
	if p != null and not p.display_name.is_empty():
		return p.display_name
	return String(job_slug).capitalize()


## Category slug (`&"gathering"` / `&"crafting"`) for [param job_slug], or
## empty if unknown. Used by the Jobs UI to bucket the list.
static func category(job_slug: StringName) -> StringName:
	var p: JobPerks = perks_for(job_slug)
	if p == null:
		return &""
	return p.category
