class_name QuestBoard
extends Interactable
## A clickable town board posting the player's 3 daily quests — shown as a board
## sprite. Just an Interactable preconfigured to open the daily board; the click is
## inherited. One per map suffices (daily state is per-player, not per-board). No
## id/range needed — it opens the caller's OWN dailies, not a station's state.


func _ready() -> void:
	menu_name = &"daily_board"
	super._ready()
