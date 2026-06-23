extends MenuShell
## Quest log as its OWN top-level menu — split out of the Character window, since a quest log isn't a
## character stat. Hosts the existing code-built quest_log_panel inside the shared menu shell, so the
## panel itself needed no changes. Opened via open_menu_requested(&"quests") → the HUD's display_menu.

const QUEST_LOG_PANEL: GDScript = preload("res://source/client/ui/menus/character/quest_log_panel.gd")


func _ready() -> void:
	build_shell("Quests", null, true)
	var panel: VBoxContainer = QUEST_LOG_PANEL.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(panel)
