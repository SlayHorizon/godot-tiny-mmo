class_name QuestObjective
extends Resource
## One step of a quest. KILL tracks an enemy type; COLLECT/CRAFT track an item.

enum Type { KILL, COLLECT, CRAFT }

@export var type: Type = Type.KILL
## KILL only: matched against HostileNpc.enemy_type (e.g. &"slime").
@export var enemy_type: StringName
## COLLECT (have N in the bag) / CRAFT (craft N) target item.
@export var item: Item
@export var required_amount: int = 1


## The key this objective tracks: the enemy_type (KILL) or the item's registry id
## (COLLECT/CRAFT). Used to match incoming kill/craft events.
func target_key() -> Variant:
	if type == Type.KILL:
		return enemy_type
	return int(item.get_meta(&"id", 0)) if item else 0


func describe() -> String:
	match type:
		Type.KILL:
			return "Defeat %d %s" % [required_amount, String(enemy_type).capitalize()]
		Type.COLLECT:
			return "Collect %d %s" % [required_amount, str(item.item_name) if item else "?"]
		Type.CRAFT:
			return "Craft %d %s" % [required_amount, str(item.item_name) if item else "?"]
	return ""
