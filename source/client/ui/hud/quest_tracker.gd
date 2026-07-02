class_name QuestTracker
extends PanelContainer
## HUD quest tracker: shows a single quest (the one pinned via the log, else the first
## active quest) with its objectives + live progress. Hidden when there's nothing to track.
## Click-through so it never blocks world interaction.

var _content: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# On-theme panel: a transparent dark-neutral card (no accent bar) that reads cleanly over the
	# world under any palette — same overlay language as the chat. The palette shows through the
	# quest name instead (see _display).
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


## Re-derive visibility + content from the live tracked / active quest state. Public so the HUD
## can re-validate after a menu closes — a quest may have been untracked while the tracker was
## menu-hidden, and a blind show() would otherwise resurrect it.
func refresh() -> void:
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


## Transparent dark-neutral card: a soft charcoal fill (palette-agnostic, like the chat overlay)
## with a faint hairline edge + drop shadow for definition over the world. No accent bar — the
## palette comes through the quest name instead (see _display). Alpha is the one knob to nudge if
## text dips on very bright scenes.
func _make_panel_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.08, 0.6)
	box.set_border_width_all(1)
	box.border_color = Color(1.0, 1.0, 1.0, 0.07)
	box.set_corner_radius_all(4)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 5
	return box


func _display(quest: Dictionary) -> void:
	for child in _content.get_children():
		child.queue_free()

	var complete: bool = bool(quest.get("complete", false))
	var any_mode: bool = int(quest.get("completion", 0)) == 1

	# Name leads the panel — no "QUEST" eyebrow, the layout speaks for itself. It follows the active
	# palette accent while in progress, then flips to bright green with a ✓ prefix once ready: that
	# color shift is the player's primary "I'm done!" cue.
	var name_label: Label = Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override(&"font_size", 14)
	var prefix: String = "✓ " if complete else ""
	name_label.text = prefix + str(quest.get("name", "?"))
	name_label.add_theme_color_override(
		&"font_color",
		Color(0.5, 0.95, 0.5) if complete else _accent_color()
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


## The active palette's accent (the same hue the gateway + menus focus-tint with), read live from
## the shared [gateway]/palette setting so the quest name matches the player's chosen theme. Mirrors
## ui.gd's palette read; falls back to the default palette.
func _accent_color() -> Color:
	var saved: Variant = ClientState.settings.get_value(&"gateway", &"palette")
	var slug: StringName = StringName(saved) if saved is String or saved is StringName else ThemePalettes.DEFAULT
	return ThemePalettes.accent(slug)
