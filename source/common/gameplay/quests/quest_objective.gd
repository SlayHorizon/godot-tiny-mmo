class_name QuestObjective
extends Resource
## One step of a quest. KILL tracks an enemy type; COLLECT/CRAFT track an item;
## VISIT tracks talking to a specific QuestGiver (resolved by giver_id).

enum Type { KILL, COLLECT, CRAFT, VISIT }

@export var type: Type = Type.KILL
## KILL only: matched against HostileNpc.enemy_type (e.g. &"slime").
@export var enemy_type: StringName
## COLLECT (have N in the bag) / CRAFT (craft N) target item.
@export var item: Item
@export var required_amount: int = 1
## VISIT only: the QuestGiver to talk to. The objective advances when the
## player opens the quest menu at this giver.
@export var target_giver_id: int = 0
## VISIT only: human-readable target name used in the objective description
## (e.g. "Mira the Herbalist"). Lets the quest read cleanly without a runtime
## lookup of the giver's name.
@export var target_giver_name: String


## The key this objective tracks. Used to match incoming kill/craft/visit
## events against active quests.
func target_key() -> Variant:
	match type:
		Type.KILL:
			return enemy_type
		Type.VISIT:
			return target_giver_id
		_:
			return int(item.get_meta(&"id", 0)) if item else 0


func describe() -> String:
	match type:
		Type.KILL:
			return "Defeat %s" % String(enemy_type).capitalize()
		Type.COLLECT:
			# "Bring", not "Collect": COLLECT items are consumed and handed to the
			# giver on turn-in (see QuestService.apply_turn_in), so it's a delivery,
			# not a gather. (Daily COLLECT is NOT consumed — it keeps "Collect".)
			return "Bring %s" % (str(item.item_name) if item else "?")
		Type.CRAFT:
			return "Craft %s" % (str(item.item_name) if item else "?")
		Type.VISIT:
			var who: String = target_giver_name if not target_giver_name.is_empty() else "the indicated person"
			return "Speak with %s" % who
	return ""
