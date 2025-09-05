class_name ItemSlot
extends Resource


# &"Weapon", &"Helmet", ...
## Should be constant, never changed like an unique identifier.
@export var key: StringName

## Can be translated, means to be used in UI.
@export var display_name: String

## 1 to be unlocked by default and 0 if needs a specific condition.
@export_range(0, 99, 1.0, "suffix:lvl") var unlock_level: int = 1

## Option icon for UI
@export var icon: Texture2D

## Avoid keeping runtime flag on a resource, may move it later.
var unlocked: bool = false


# TO DO / TO CONSIDER LATER:
#@export var unlock_rule: SlotUnlockRule
#func is_unlocked_for(player: Player) -> bool:
	#return unlock_rule and unlock_level.is_unlocked(player)
#class_name SlotUnlockRule
#extends Resource
#enum Kind {ALWAYS, PLAYER_LEVEL, QUEST_COMPLETED, MANUAL_FLAG}
#@export var kind: Kind = Kind.ALWAYS
#@export var level: int = 0
#@export var quest_id: int = 0
#@export var flag_key: StringName = &""
#
#func is_unlocked(player: Player) -> bool:
	#match kind:
		#Kind.ALWAYS: return true
		#Kind.PLAYER_LEVEL: return player.player_resource.level >= level
		#Kind.QUEST_COMPLETED: return player.has_completed_quest(quest_id)
		#Kind.MANUAL_FLAG: return player.progress_flags.has(flag_key)
		#_: return false
