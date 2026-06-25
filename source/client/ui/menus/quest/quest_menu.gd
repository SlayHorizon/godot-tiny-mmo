extends Control
## Quest-giver dialog, master-detail layout. Left column lists the quest titles
## this giver offers (with state tag: New / Active / Ready / Done / Locked).
## Right column shows the full details of the selected quest (description,
## objectives, rewards, action button).
##
## Standard RPG/MMO journal pattern — lets a giver carry many quests without
## scrolling and keeps the first read clean: the player sees all titles at a
## glance and drills in on what catches their eye.

const COLOR_NEW: Color = Color(0.95, 0.95, 0.95)
const COLOR_ACTIVE: Color = Color(0.95, 0.85, 0.45)
const COLOR_READY: Color = Color(0.55, 0.9, 0.55)
const COLOR_DONE: Color = Color(0.55, 0.65, 0.55)
const COLOR_LOCKED: Color = Color(0.7, 0.5, 0.5)
const COLOR_OBJ_MET: Color = Color(0.5, 0.9, 0.5)
const COLOR_HINT: Color = Color(0.65, 0.75, 0.9)
const COLOR_DESC: Color = Color(0.75, 0.75, 0.8)
const COLOR_REWARD: Color = Color(0.85, 0.8, 0.4)

var _giver_id: int
var _quests: Array = []
var _selected_quest_id: int = -1
## Title-row buttons keyed by quest id, kept for highlight refresh on selection.
var _title_buttons: Dictionary[int, Button]

@onready var title_label: Label = %TitleLabel
@onready var title_list: VBoxContainer = %TitleList
@onready var title_scroll: ScrollContainer = $Margin/Card/Pad/Root/Body/LeftPanel/LeftScroll
@onready var detail_title: Label = %DetailTitle
@onready var action_slot: HBoxContainer = %ActionSlot
@onready var details_container: VBoxContainer = %DetailsContainer


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible and _giver_id > 0:
		_refresh()


func open(giver_id: int) -> void:
	_giver_id = giver_id
	_refresh()


func _refresh() -> void:
	var result: Array = await Client.request_data_await(
		&"quest.list", {"giver": _giver_id}, InstanceClient.current.name
	)
	if result[1] != OK:
		return
	var data: Dictionary = result[0]
	var giver_name: String = str(data.get("giver_name", ""))
	title_label.text = giver_name if not giver_name.is_empty() else "Quests"
	_quests = data.get("quests", [])
	_build_title_list()
	_select_initial()


# ---------------------------------------------------------------------------
# Left column: list of quest titles
# ---------------------------------------------------------------------------

func _build_title_list() -> void:
	for child in title_list.get_children():
		child.queue_free()
	_title_buttons.clear()

	if _quests.is_empty():
		var empty: Label = Label.new()
		empty.text = "Nothing available."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_list.add_child(empty)
		_show_empty_details()
		return

	for quest: Dictionary in _quests:
		var quest_id: int = int(quest.get("id", 0))
		var button: Button = _make_title_row(quest)
		button.pressed.connect(_select_quest.bind(quest_id))
		title_list.add_child(button)
		_title_buttons[quest_id] = button
	DragScroll.enable(title_scroll) # touch/mouse drag-scroll the quest list (flips fresh rows to PASS)


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
			if not bool(quest.get("meets_level", true)):
				return COLOR_LOCKED
			return COLOR_NEW


# ---------------------------------------------------------------------------
# Selection plumbing
# ---------------------------------------------------------------------------

## Pick the first sensible quest to show on open: a Ready turn-in first
## (most actionable), then any Active, then the first one in the list.
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
		target_id = int(_quests[0].get("id", 0))
	_select_quest(target_id)


func _select_quest(quest_id: int) -> void:
	_selected_quest_id = quest_id
	# Refresh the toggle state on every row so only the selected one stays pressed.
	for qid in _title_buttons:
		_title_buttons[qid].button_pressed = qid == quest_id
	for quest: Dictionary in _quests:
		if int(quest.get("id", 0)) == quest_id:
			_show_details(quest)
			return


# ---------------------------------------------------------------------------
# Right column: full details for the selected quest
# ---------------------------------------------------------------------------

func _show_empty_details() -> void:
	detail_title.text = ""
	for child in action_slot.get_children():
		child.queue_free()
	for child in details_container.get_children():
		child.queue_free()
	var hint: Label = Label.new()
	hint.text = "No quests to discuss."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.55
	details_container.add_child(hint)


func _show_details(quest: Dictionary) -> void:
	for child in details_container.get_children():
		child.queue_free()
	for child in action_slot.get_children():
		child.queue_free()

	var state: String = str(quest.get("state", ""))
	var complete: bool = bool(quest.get("complete", false))
	var any_mode: bool = int(quest.get("completion", 0)) == 1

	# Title + action live in the pinned header (mirrors the quest log) so the
	# Accept / Turn-in button is always reachable without scrolling past a long
	# description.
	detail_title.text = str(quest.get("name", "?"))
	action_slot.add_child(_make_action(
		int(quest.get("id", 0)),
		state,
		complete,
		bool(quest.get("meets_level", true)),
		int(quest.get("min_level", 0)),
	))

	var description: String = str(quest.get("description", ""))
	if not description.is_empty():
		var desc_label: Label = Label.new()
		desc_label.text = description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override(&"font_color", COLOR_DESC)
		details_container.add_child(desc_label)

	var objectives: Array = quest.get("objectives", [])
	if not objectives.is_empty():
		var obj_header: Label = Label.new()
		obj_header.text = "Objectives"
		obj_header.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
		details_container.add_child(obj_header)
		for i: int in objectives.size():
			# ANY-mode quests intersperse an OR line between objectives so the
			# player reads them as alternatives, not a checklist. We render OR
			# rows even though they're not part of the data — they're a pure
			# layout affordance.
			if any_mode and i > 0:
				details_container.add_child(_make_or_separator())
			details_container.add_child(_make_objective_row(objectives[i]))

	details_container.add_child(_spacer(8))
	details_container.add_child(HSeparator.new())
	var reward_label: Label = Label.new()
	reward_label.text = "Rewards: %d XP, %d gold" % [
		int(quest.get("reward_xp", 0)), int(quest.get("reward_gold", 0))
	]
	reward_label.add_theme_color_override(&"font_color", COLOR_REWARD)
	details_container.add_child(reward_label)


func _make_objective_row(objective: Dictionary) -> Label:
	var count: int = int(objective.get("count", 0))
	var required: int = int(objective.get("required", 1))
	var met: bool = count >= required
	var desc: String = str(objective.get("desc", ""))
	var row: Label = Label.new()
	# VISIT objectives aren't counted ("Speak with X") — show a ✓ when done rather
	# than a clumsy "(0/1)". Countable rows (defeat/bring/craft) show "(c/r)".
	if bool(objective.get("countable", true)):
		row.text = "• %s (%d/%d)" % [desc, count, required]
	else:
		row.text = "• %s%s" % [desc, "  ✓" if met else ""]
	if met:
		row.add_theme_color_override(&"font_color", COLOR_OBJ_MET)
	return row


## Indented "OR" line slotted between objectives in ANY-mode quests so the
## player reads them as alternatives rather than a checklist.
func _make_or_separator() -> Label:
	var label: Label = Label.new()
	label.text = "OR"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", COLOR_HINT)
	return label


func _make_action(quest_id: int, state: String, complete: bool, meets_level: bool, min_level: int) -> Control:
	match state:
		"":
			if not meets_level:
				var locked: Label = Label.new()
				locked.text = "Requires level %d" % min_level
				locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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


## Small vertical spacer for visual rhythm between sections.
func _spacer(height: int) -> Control:
	var ctrl: Control = Control.new()
	ctrl.custom_minimum_size = Vector2(0, height)
	return ctrl


# ---------------------------------------------------------------------------
# Quest actions
# ---------------------------------------------------------------------------

func _on_accept(quest_id: int) -> void:
	var result: Array = await Client.request_data_await(
		&"quest.accept", {"giver": _giver_id, "id": quest_id}, InstanceClient.current.name
	)
	if result[1] == OK and result[0].get("ok", false):
		ClientState.set_tracked_quest(quest_id) # latest accepted becomes the tracked one
	_refresh()


func _on_turn_in(quest_id: int) -> void:
	await Client.request_data_await(
		&"quest.turn_in", {"giver": _giver_id, "id": quest_id}, InstanceClient.current.name
	)
	_refresh()


func _on_close_button_pressed() -> void:
	hide()
