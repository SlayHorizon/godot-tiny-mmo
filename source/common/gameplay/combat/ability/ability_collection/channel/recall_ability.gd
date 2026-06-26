class_name RecallAbility
extends ChannelAbility
## The universal Recall: a long channel anyone can start (no weapon, no mastery —
## see the recall.start handler + the Recall keybind). Stand still for the full
## duration and you're whisked to the town hub; moving cancels it (the shared
## channel root) and a hit cancels it (cancel_on_damage), so you can't escape a
## fight by teleporting. The payoff is server-side instance travel via WorldServer.curr
## (the export stub keeps this common resource free of a hard server import).


func channel_complete(caster: Character) -> void:
	if not GameMode.is_world_server() or caster is not Player:
		return
	if WorldServer.curr != null:
		WorldServer.curr.recall_player(caster as Player)
