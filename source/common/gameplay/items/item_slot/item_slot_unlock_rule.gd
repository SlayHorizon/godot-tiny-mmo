class_name SlotUnlockRule
extends Resource


enum Kind {
	ALWAYS,
	PLAYER_LEVEL,
	QUEST_COMPLETED,
	MANUAL_FLAG
}

@export var kind: Kind = Kind.ALWAYS
@export var level: int = 0
@export var quest_id: int = 0
@export var flag_key: StringName = &""


func is_unlocked(player: PlayerResource) -> bool:
	match kind:
		Kind.ALWAYS: return true
		Kind.PLAYER_LEVEL: return player.level >= level
		# Later ?
		#Kind.QUEST_COMPLETED: return player.has_completed_quest(quest_id)
		# Later ?
		#Kind.MANUAL_FLAG: return player.progress_flags.has(flag_key)
		_: return false
