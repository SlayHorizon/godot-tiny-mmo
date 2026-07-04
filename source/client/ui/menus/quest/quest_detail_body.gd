class_name QuestDetailBody
extends VBoxContainer
## Shared renderer for a quest's detail column — description, objectives
## (with ANY-mode OR separators and met/unmet coloring), and the rewards line.
## Used by BOTH the quest-giver menu and the quest log so the two always read
## identically; each host keeps its own header row (Accept/Turn-in vs
## Track/Untrack) above this body.
##
## Renders from the quest VIEW Dictionary the server ships in quest.list —
## it never touches QuestResource directly, so it works for locked quests
## the player doesn't hold yet.

const COLOR_SECTION: Color = Color(1.0, 0.85, 0.5)
const COLOR_DESC: Color = Color(0.75, 0.77, 0.83)
const COLOR_OBJ_MET: Color = Color(0.5, 0.9, 0.5)
const COLOR_HINT: Color = Color(0.65, 0.75, 0.9)
const COLOR_REWARD: Color = Color(0.85, 0.8, 0.4)


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 8)


## Rebuilds the body from a quest view Dictionary (see quest.list's _quest_view).
func render(quest: Dictionary) -> void:
	clear()

	var description: String = str(quest.get("description", ""))
	if not description.is_empty():
		var desc_label: Label = Label.new()
		desc_label.text = description
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.add_theme_color_override(&"font_color", COLOR_DESC)
		add_child(desc_label)

	var objectives: Array = quest.get("objectives", [])
	if not objectives.is_empty():
		var obj_header: Label = Label.new()
		obj_header.text = "Objectives"
		obj_header.add_theme_color_override(&"font_color", COLOR_SECTION)
		add_child(obj_header)
		# ANY-mode quests (completion == 1) treat objectives as alternatives —
		# an OR line between them reads them as a choice, not a checklist.
		var any_mode: bool = int(quest.get("completion", 0)) == 1
		for i: int in objectives.size():
			if any_mode and i > 0:
				add_child(_make_or_separator())
			add_child(_make_objective_row(objectives[i]))

	var reward_text: String = _reward_line(quest)
	if not reward_text.is_empty():
		add_child(HSeparator.new())
		var reward_label: Label = Label.new()
		reward_label.text = reward_text
		reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward_label.add_theme_color_override(&"font_color", COLOR_REWARD)
		add_child(reward_label)


func clear() -> void:
	for child: Node in get_children():
		child.queue_free()


func _make_objective_row(objective: Dictionary) -> Label:
	var count: int = int(objective.get("count", 0))
	var required: int = int(objective.get("required", 1))
	var met: bool = count >= required
	var desc: String = str(objective.get("desc", ""))
	var row: Label = Label.new()
	# VISIT rows aren't counted ("Speak with X") — show a ✓ when done rather
	# than a clumsy "(0/1)". Countable rows (defeat/bring/craft) show "(c/r)".
	if bool(objective.get("countable", true)):
		row.text = "• %s (%d/%d)" % [desc, count, required]
	else:
		row.text = "• %s%s" % [desc, "  ✓" if met else ""]
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if met:
		row.add_theme_color_override(&"font_color", COLOR_OBJ_MET)
	return row


func _make_or_separator() -> Label:
	var label: Label = Label.new()
	label.text = "OR"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", COLOR_HINT)
	return label


## "Rewards: 160 XP, 12 gold, Bone Maul ×1" — omits zero parts; empty string
## when the quest grants nothing (the line is skipped entirely).
func _reward_line(quest: Dictionary) -> String:
	var parts: Array[String] = []
	var xp: int = int(quest.get("reward_xp", 0))
	var gold: int = int(quest.get("reward_gold", 0))
	if xp > 0:
		parts.append("%d XP" % xp)
	if gold > 0:
		parts.append("%d gold" % gold)
	for item: Variant in quest.get("reward_items", []):
		var entry: Dictionary = item
		parts.append("%s ×%d" % [str(entry.get("name", "?")), int(entry.get("amount", 1))])
	return "Rewards: %s" % ", ".join(parts) if not parts.is_empty() else ""
