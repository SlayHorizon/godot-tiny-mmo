extends PanelContainer
## HUD quest tracker: shows a single quest (the one pinned via the log, else the first
## active quest) with its objectives + live progress. Hidden when there's nothing to track.
## Click-through so it never blocks world interaction.

var _content: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# On-theme panel: dark card with an amber left accent so the tracker reads
	# as part of the same visual language as the quest log / giver dialog.
	add_theme_stylebox_override(&"panel", _make_panel_style())

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 12)
	margin.add_theme_constant_override(&"margin_right", 10)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	add_child(margin)

	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override(&"separation", 3)
	margin.add_child(_content)

	hide()
	ClientState.tracked_quest_changed.connect(func(_id: int): _refresh())
	Client.subscribe(&"quest.update", func(_data: Dictionary): _refresh())
	# COLLECT objectives track live inventory, which never fires quest.update on its
	# own. Refresh on the two open-world item-gain pushes — loot (combat.reward) and
	# gathering (mining.gather_result) — so a "Bring N item" objective climbs live
	# instead of only updating when a menu is reopened.
	Client.subscribe(&"combat.reward", func(_data: Dictionary): _refresh())
	Client.subscribe(&"mining.gather_result", func(_data: Dictionary): _refresh())
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _refresh())
	_refresh()


func _refresh() -> void:
	if InstanceClient.current == null:
		hide()
		return
	Client.request_data(&"quest.list", _on_received, {}, InstanceClient.current.name)


func _on_received(data: Dictionary) -> void:
	# -1 = explicitly untracked (player cleared the HUD); stay hidden.
	if ClientState.tracked_quest_id == -1:
		hide()
		return

	var tracked: Dictionary = {}
	var first_active: Dictionary = {}
	for quest: Dictionary in data.get("quests", []):
		if str(quest.get("state", "")) != "active":
			continue
		if first_active.is_empty():
			first_active = quest
		if int(quest.get("id", 0)) == ClientState.tracked_quest_id:
			tracked = quest

	if tracked.is_empty():
		if first_active.is_empty():
			hide()
			return
		# Auto-track the first active quest (set directly, no signal, to avoid a refetch loop).
		tracked = first_active
		ClientState.tracked_quest_id = int(first_active.get("id", 0))

	_display(tracked)
	show()


## Dark card with a thick amber left border — visually ties the floating
## tracker to the quest log's selected-row / section-tab accent.
func _make_panel_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.078, 0.117, 0.92)
	box.border_width_left = 3
	box.border_color = Color(0.96, 0.74, 0.16, 1)
	box.corner_radius_top_left = 4
	box.corner_radius_top_right = 4
	box.corner_radius_bottom_right = 4
	box.corner_radius_bottom_left = 4
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = 4
	return box


func _display(quest: Dictionary) -> void:
	for child in _content.get_children():
		child.queue_free()

	var complete: bool = bool(quest.get("complete", false))
	var any_mode: bool = int(quest.get("completion", 0)) == 1

	# Tiny "QUEST" eyebrow so the panel is self-explanatory at a glance.
	var eyebrow: Label = Label.new()
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eyebrow.text = "QUEST"
	eyebrow.add_theme_font_size_override(&"font_size", 9)
	eyebrow.add_theme_color_override(&"font_color", Color(0.6, 0.66, 0.78))
	_content.add_child(eyebrow)

	# Name: yellow while in progress, bright green with a ✓ prefix once ready.
	# The shift in color is the player's primary "I'm done!" cue.
	var name_label: Label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override(&"font_size", 14)
	var prefix: String = "✓ " if complete else ""
	name_label.text = prefix + str(quest.get("name", "?"))
	name_label.add_theme_color_override(
		&"font_color",
		Color(0.5, 0.95, 0.5) if complete else Color(1.0, 0.9, 0.55)
	)
	_content.add_child(name_label)

	var objectives: Array = quest.get("objectives", [])
	# Track whether we've already pushed at least one objective into the tracker;
	# the OR separator only goes between visible objectives, so an early continue
	# (ANY-mode complete hiding unmet paths) doesn't leave a leading "OR" line.
	var any_shown: bool = false
	for objective: Dictionary in objectives:
		var count: int = int(objective.get("count", 0))
		var required: int = int(objective.get("required", 1))
		var met: bool = count >= required
		# ANY-mode complete: only show the satisfied objective so the tracker
		# isn't cluttered with paths the player chose not to take.
		if any_mode and complete and not met:
			continue
		# In-progress ANY mode: drop an "OR" between alternatives so the
		# player reads them as a choice rather than a checklist.
		if any_mode and not complete and any_shown:
			var or_label: Label = Label.new()
			or_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			or_label.text = "OR"
			or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			or_label.add_theme_color_override(&"font_color", Color(0.65, 0.75, 0.9))
			_content.add_child(or_label)
		var objective_label: Label = Label.new()
		objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# VISIT rows aren't counted — show a ✓ when done, not "(0/1)".
		if bool(objective.get("countable", true)):
			objective_label.text = "• %s (%d/%d)" % [str(objective.get("desc", "")), count, required]
		else:
			objective_label.text = "• %s%s" % [str(objective.get("desc", "")), "  ✓" if met else ""]
		if met:
			objective_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
		_content.add_child(objective_label)
		any_shown = true

	# Ready-to-turn-in nudge. Same line every game uses, instantly readable.
	if complete:
		var ready_label: Label = Label.new()
		ready_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ready_label.text = "↩ Return to the quest giver"
		ready_label.add_theme_color_override(&"font_color", Color(0.55, 0.9, 0.55))
		_content.add_child(ready_label)
