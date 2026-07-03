class_name DailyQuestTemplate
extends Resource
## One generative blueprint for a daily quest. The board rolls 3 of these per
## player per day, scoped to their level range.
##
## Kinds: KILL / COLLECT are targeted (match enemy_type / item); SPAR / DUNGEON /
## CRAFT are generic action counters (any duel / dungeon clear / craft). Fixed
## amount + reward, no per-level scaling — author a separate template at a higher
## min_level for a tougher version. Keeps numbers readable.

enum Kind { KILL, COLLECT, SPAR, DUNGEON, CRAFT }

## Stable id used to track progress on a player. Two templates must never share
## an id; rolling a duplicate would silently overwrite progress in the player's
## stored daily set.
@export var template_id: int = 0
@export var kind: Kind = Kind.KILL
## KILL: enemy_type to match (&"goblin", &"slime", etc.).
## COLLECT: target item to count in inventory.
@export var enemy_type: StringName
@export var item: Item
@export var required_amount: int = 1

## Eligibility window — a player whose level falls in [min_level, max_level]
## can be assigned this. 0 max = no cap.
@export var min_level: int = 0
@export var max_level: int = 0

@export var reward_xp: int = 10
@export var reward_gold: int = 3

## Friendly text for the UI. Auto-generated from kind/target if empty.
@export var description: String


func describe() -> String:
	if not description.is_empty():
		return description
	match kind:
		Kind.KILL: return "Defeat %d %s" % [required_amount, String(enemy_type).capitalize()]
		Kind.COLLECT: return "Collect %d %s" % [required_amount, str(item.item_name) if item else "?"]
		Kind.SPAR: return "Fight %d arena duel%s" % [required_amount, _plural(required_amount)]
		Kind.DUNGEON: return "Clear %d dungeon%s" % [required_amount, _plural(required_amount)]
		Kind.CRAFT: return "Craft %d item%s" % [required_amount, _plural(required_amount)]
	return "?"


static func _plural(n: int) -> String:
	return "" if n == 1 else "s"


## What the daily's "target_key" is for matching incoming kill/collect events.
## For KILL it's the enemy_type StringName. For COLLECT it's the item registry id.
func target_key() -> Variant:
	if kind == Kind.KILL:
		return enemy_type
	return int(item.get_meta(&"id", 0)) if item else 0
