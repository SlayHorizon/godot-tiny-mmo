class_name DailyQuestPool
extends Resource
## The full set of daily quest templates the board can roll from. A single
## pool resource covers the whole game; the level gates on each template
## handle which ones a given player is eligible for.

@export var templates: Array[DailyQuestTemplate]


## Returns templates the player's level is eligible for, copied (the pool is
## the source of truth — we never mutate it).
func eligible_for_level(player_level: int) -> Array[DailyQuestTemplate]:
	var out: Array[DailyQuestTemplate] = []
	for t: DailyQuestTemplate in templates:
		if t == null:
			continue
		if player_level < t.min_level:
			continue
		if t.max_level > 0 and player_level > t.max_level:
			continue
		out.append(t)
	return out


## Look up a template by its id. O(n) but pools are small (<50 templates).
func by_id(template_id: int) -> DailyQuestTemplate:
	for t: DailyQuestTemplate in templates:
		if t and t.template_id == template_id:
			return t
	return null
