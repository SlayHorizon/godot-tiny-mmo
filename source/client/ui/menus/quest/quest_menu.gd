extends MenuShell
## Quest-giver dialog on the shared MenuShell frame (full-screen, same chrome
## as the quest log / other menus). Master-detail: left column lists the
## giver's quest titles with a state tag (New / Active / Ready / Done / LV n /
## Locked), right column shows the selected quest via the shared
## QuestDetailBody plus this menu's own action slot (Accept / Turn in / lock
## conditions). Locked chain quests render with their unlock conditions —
## never hidden (owner call 2026-07-04).

const COLOR_NEW: Color = Color(0.95, 0.95, 0.95)
const COLOR_ACTIVE: Color = Color(0.95, 0.85, 0.45)
const COLOR_READY: Color = Color(0.55, 0.9, 0.55)
const COLOR_DONE: Color = Color(0.55, 0.65, 0.55)
const COLOR_LOCKED: Color = Color(0.7, 0.5, 0.5)

var _giver_key: String
var _quests: Array = []
var _selected_quest_id: int = -1
## Title-row buttons keyed by quest id, kept for highlight refresh on selection.
var _title_buttons: Dictionary[int, Button]

var _title_scroll: ScrollContainer
var _title_list: VBoxContainer
var _detail_title: Label
var _action_slot: HBoxContainer
var _detail_body: QuestDetailBody


func _ready() -> void:
	build_shell("Quests", null, true)
	content.add_child(_build_body())
	visibility_changed.connect(_on_visibility_changed)
	# Live refresh while the dialog is open: kill counts tick and READY
	# appears without closing and re-talking to the giver.
	Client.subscribe(&"quest.update", func(_data: Dictionary) -> void:
		if is_visible_in_tree() and not _giver_key.is_empty():
			_refresh()
	)


## Same split layout (and stretch ratios) as the quest log, so the two quest
## screens read as one family.
func _build_body() -> Control:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 12)

	_title_scroll = ScrollContainer.new()
	_title_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title_scroll.size_flags_stretch_ratio = 0.85
	_title_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(_title_scroll)

	_title_list = VBoxContainer.new()
	_title_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_list.add_theme_constant_override(&"separation", 4)
	_title_scroll.add_child(_title_list)

	# Right: pinned header (title + action) above a scrolling detail body, so
	# Accept / Turn in stays reachable past a long description.
	var right_col: VBoxContainer = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.3
	right_col.add_theme_constant_override(&"separation", 8)
	hbox.add_child(right_col)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	right_col.add_child(header)

	_detail_title = Label.new()
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_title.add_theme_font_size_override(&"font_size", 18)
	_detail_title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.75))
	_detail_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_detail_title)

	_action_slot = HBoxContainer.new()
	header.add_child(_action_slot)

	var body_scroll: ScrollContainer = ScrollContainer.new()
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(body_scroll)

	_detail_body = QuestDetailBody.new()
	body_scroll.add_child(_detail_body)

	return hbox


func _on_visibility_changed() -> void:
	if visible and not _giver_key.is_empty():
		_refresh()


## Entry point from HUD.display_menu(&"quest", giver_key).
func open(giver_key: String) -> void:
	_giver_key = giver_key
	_refresh()


func _refresh() -> void:
	var result: Array = await Client.request_data_await(
		&"quest.list", {"giver": _giver_key}, InstanceClient.current.name
	)
	if result[1] != OK:
		return
	var data: Dictionary = result[0]
	var giver_name: String = str(data.get("giver_name", ""))
	set_title(giver_name if not giver_name.is_empty() else "Quests")
	_quests = data.get("quests", [])
	_build_title_list()
	_select_initial()


# ---------------------------------------------------------------------------
# Left column: list of quest titles
# ---------------------------------------------------------------------------

func _build_title_list() -> void:
	for child: Node in _title_list.get_children():
		child.queue_free()
	_title_buttons.clear()

	if _quests.is_empty():
		var empty: Label = Label.new()
		empty.text = "Nothing available."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_list.add_child(empty)
		_show_empty_details()
		return

	for quest: Dictionary in _quests:
		var quest_id: int = int(quest.get("id", 0))
		var button: Button = _make_title_row(quest)
		button.pressed.connect(_select_quest.bind(quest_id))
		_title_list.add_child(button)
		_title_buttons[quest_id] = button
	DragScroll.enable(_title_scroll) # touch/mouse drag-scroll (flips fresh rows to PASS)


func _make_title_row(quest: Dictionary) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	var tag: String = _status_tag(quest)
	var quest_name: String = str(quest.get("name", "?"))
	# Tag right-aligned by padding the name with spaces is fragile across fonts;
	# simpler is a plain "  · TAG" suffix the eye reads as a status pill.
	button.text = "%s   ·  %s" % [quest_name, tag] if not tag.is_empty() else quest_name
	button.add_theme_color_override(&"font_color", _status_color(quest))
	return button


## Plain-text status tag shown after the quest name on the title row.
func _status_tag(quest: Dictionary) -> String:
	var state: String = str(quest.get("state", ""))
	match state:
		"active":
			return "READY" if bool(quest.get("complete", false)) else "ACTIVE"
		"turned_in":
			return "DONE"
		_:
			# Chain lock outranks the level chip: "do the earlier quest" is the
			# actionable info; the level requirement still shows in the details.
			if not bool(quest.get("meets_prereq", true)):
				return "LOCKED"
			if not bool(quest.get("meets_level", true)):
				return "LV %d" % int(quest.get("min_level", 0))
			return "NEW"


func _status_color(quest: Dictionary) -> Color:
	var state: String = str(quest.get("state", ""))
	match state:
		"active":
			return COLOR_READY if bool(quest.get("complete", false)) else COLOR_ACTIVE
		"turned_in":
			return COLOR_DONE
		_:
			if not bool(quest.get("meets_prereq", true)) or not bool(quest.get("meets_level", true)):
				return COLOR_LOCKED
			return COLOR_NEW


# ---------------------------------------------------------------------------
# Selection plumbing
# ---------------------------------------------------------------------------

## Pick the first sensible quest to show on open: a Ready turn-in first
## (most actionable), then any Active, then the first ACCEPTABLE one (opening
## on a locked row buries the lede), then the first in the list.
func _select_initial() -> void:
	if _quests.is_empty():
		return
	var target_id: int = -1
	for quest: Dictionary in _quests:
		if str(quest.get("state", "")) == "active" and bool(quest.get("complete", false)):
			target_id = int(quest.get("id", 0))
			break
	if target_id == -1:
		for quest: Dictionary in _quests:
			if str(quest.get("state", "")) == "active":
				target_id = int(quest.get("id", 0))
				break
	if target_id == -1:
		for quest: Dictionary in _quests:
			if str(quest.get("state", "")) == "" and _unmet_conditions(quest).is_empty():
				target_id = int(quest.get("id", 0))
				break
	if target_id == -1:
		target_id = int(_quests[0].get("id", 0))
	_select_quest(target_id)


func _select_quest(quest_id: int) -> void:
	_selected_quest_id = quest_id
	# Refresh the toggle state on every row so only the selected one stays pressed.
	for qid: int in _title_buttons:
		_title_buttons[qid].button_pressed = qid == quest_id
	for quest: Dictionary in _quests:
		if int(quest.get("id", 0)) == quest_id:
			_show_details(quest)
			return


# ---------------------------------------------------------------------------
# Right column: full details for the selected quest
# ---------------------------------------------------------------------------

func _show_empty_details() -> void:
	_detail_title.text = ""
	for child: Node in _action_slot.get_children():
		child.queue_free()
	_detail_body.clear()
	var hint: Label = Label.new()
	hint.text = "No quests to discuss."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.55
	_detail_body.add_child(hint)


func _show_details(quest: Dictionary) -> void:
	for child: Node in _action_slot.get_children():
		child.queue_free()
	_detail_title.text = str(quest.get("name", "?"))
	_action_slot.add_child(_make_action(
		quest, str(quest.get("state", "")), bool(quest.get("complete", false))
	))
	_detail_body.render(quest)


## Human-readable list of everything still blocking an Accept, one line each.
## Chain conditions first (they're the actionable ones), level after. ANY-mode
## prereqs read as a single "one of" line.
func _unmet_conditions(quest: Dictionary) -> Array[String]:
	var conditions: Array[String] = []
	if not bool(quest.get("meets_prereq", true)):
		var names: Array = quest.get("prereq_names", [])
		if names.is_empty():
			conditions.append("Locked") # flag-gated (e.g. a future wardstone key)
		elif int(quest.get("prereq_mode", 0)) == 1:
			conditions.append("Complete one of: %s" % ", ".join(names))
		else:
			for prereq_name: Variant in names:
				conditions.append("Complete \"%s\"" % str(prereq_name))
	if not bool(quest.get("meets_level", true)):
		conditions.append("Requires level %d" % int(quest.get("min_level", 0)))
	return conditions


func _make_action(quest: Dictionary, state: String, complete: bool) -> Control:
	var quest_id: int = int(quest.get("id", 0))
	match state:
		"":
			var conditions: Array[String] = _unmet_conditions(quest)
			if not conditions.is_empty():
				var locked: Label = Label.new()
				locked.text = "\n".join(conditions)
				locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				# No autowrap: in an HBox an autowrapped label's min width
				# collapses to ~one glyph (the goblin-chief overflow bug).
				locked.add_theme_color_override(&"font_color", COLOR_LOCKED)
				return locked
			var accept: Button = Button.new()
			accept.text = "Accept"
			accept.custom_minimum_size = Vector2(110, 36)
			accept.pressed.connect(_on_accept.bind(quest_id))
			return accept
		"active":
			if complete:
				var turn_in: Button = Button.new()
				turn_in.text = "Turn in"
				turn_in.custom_minimum_size = Vector2(110, 36)
				turn_in.pressed.connect(_on_turn_in.bind(quest_id))
				return turn_in
			var in_progress: Label = Label.new()
			in_progress.text = "In progress…"
			in_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			in_progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			in_progress.add_theme_color_override(&"font_color", COLOR_ACTIVE)
			return in_progress
		_:
			var done: Label = Label.new()
			done.text = "Completed ✓"
			done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			done.add_theme_color_override(&"font_color", COLOR_READY)
			return done


# ---------------------------------------------------------------------------
# Quest actions
# ---------------------------------------------------------------------------

func _on_accept(quest_id: int) -> void:
	var result: Array = await Client.request_data_await(
		&"quest.accept", {"giver": _giver_key, "id": quest_id}, InstanceClient.current.name
	)
	if result[1] == OK and result[0].get("ok", false):
		ClientState.set_tracked_quest(quest_id) # latest accepted becomes the tracked one
	_refresh()


func _on_turn_in(quest_id: int) -> void:
	await Client.request_data_await(
		&"quest.turn_in", {"giver": _giver_key, "id": quest_id}, InstanceClient.current.name
	)
	_refresh()
