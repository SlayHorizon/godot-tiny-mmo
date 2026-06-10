extends VBoxContainer


var attributes: Dictionary
var available_points: int:
	set = _set_available_points

@onready var available_points_label: Label = $AvailablePointsLabel

## Human-readable stat names for the per-point attribute descriptions.
const STAT_LABELS: Dictionary = {
	&"health_max": "Max HP",
	&"health": "HP",
	&"ad": "Attack",
	&"ap": "Magic",
	&"armor": "Armor",
	&"mr": "Magic Res",
	&"mana_max": "Mana",
	&"energy": "Energy",
	&"move_speed": "Move Speed",
	&"attack_speed": "Atk Speed",
	&"ability_haste": "Haste",
	&"mana_regen": "Mana Regen",
	&"tenacity": "Tenacity",
}

## Attributes whose stats aren't wired into gameplay yet. Empty since the magic
## update went live (AP scales wand damage/heals, MR mitigates magic damage) —
## add a name here to disable its row with a "Coming soon" tag.
const LOCKED_ATTRIBUTES: PackedStringArray = []


func _ready() -> void:
	# Re-fetch every time the panel becomes visible — without this, the
	# values shown reflect the first open only, and a mid-session level-up
	# leaves the panel reporting stale "available points" until relog.
	visibility_changed.connect(_refetch_if_visible)
	_refetch_if_visible()
	for child: Node in get_children():
		if child is HBoxContainer:
			_setup_attribute_row(child)


func _refetch_if_visible() -> void:
	if not visible:
		return
	Client.request_data(
		&"attribute.get",
		_on_attribute_received,
		{},
		InstanceClient.current.name
	)


## Wires a [Label, +Button] attribute row and adds an inline "what a point grants" note.
func _setup_attribute_row(row: HBoxContainer) -> void:
	var name_label: Label = row.get_child(0)
	var attribute_name: String = name_label.text.get_slice(" ", 0).to_lower()
	var locked: bool = attribute_name in LOCKED_ATTRIBUTES

	var description: String = "Coming soon" if locked else _describe_attribute(attribute_name)
	if not description.is_empty():
		var desc_label: Label = Label.new()
		desc_label.text = description
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		desc_label.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.75))
		row.add_child(desc_label)
		row.move_child(desc_label, 1)

	# Dim locked rows so the "Coming soon" reads as inactive, not broken.
	if locked:
		row.modulate.a = 0.5

	# Find the + button by type (robust to the inserted description label).
	for node: Node in row.get_children():
		if node is Button:
			# Locked attributes (magic, not wired yet) can't be spent — disable the
			# button instead of letting players waste points. Re-enable by removing
			# the name from LOCKED_ATTRIBUTES once the magic system ships.
			if locked:
				(node as Button).disabled = true
				(node as Button).tooltip_text = "Unlocks with the magic update."
			else:
				node.pressed.connect(_on_attribute_pressed.bind(name_label, node))
			break


## "+1 Max HP", "+0.7 Mana, +0.53 Energy", ... — what one point in this attribute grants.
func _describe_attribute(attribute_name: String) -> String:
	var stats: Dictionary = AttributeMap.attr_to_stats({attribute_name: 1})
	var parts: PackedStringArray = []
	for stat_name: StringName in stats:
		var stat_label: String = str(STAT_LABELS.get(stat_name, String(stat_name).capitalize()))
		parts.append("+%s %s" % [("%s" % stats[stat_name]), stat_label])
	return ", ".join(parts)


func _on_attribute_pressed(label: Label, button: Button) -> void:
	# Checked on server too.
	if not available_points > 0:
		return
	available_points -= 1
	
	var attribute_name: String = label.text.get_slice(" ", 0).to_lower()
	if attributes.has(attribute_name):
		attributes[attribute_name] += 1
	else:
		attributes[attribute_name] = 1
		
	var attribute_points: int = attributes[attribute_name]
	
	label.text = "%s %d" % [attribute_name.capitalize(), attribute_points]
	
	var stats: Dictionary = AttributeMap.attr_to_stats({attribute_name: 1})
	for stat_name: StringName in stats:
		if ClientState.stats.data.has(stat_name):
			ClientState.stats.data[stat_name] += stats[stat_name]
		else:
			ClientState.stats.data[stat_name] = stats[stat_name]
	Client.data_push(&"stats.update", ClientState.stats.data)
	
	Client.request_data(
		&"attribute.spend",
		Callable(),
		{"attr": attribute_name},
		InstanceClient.current.name
	)


func _on_attribute_received(data: Dictionary) -> void:
	attributes = data.get("attr", {})
	available_points = data.get("points", 0)
	for child: Node in get_children():
		if child is HBoxContainer:
			var label: Label = child.get_child(0)
			var label_attribute: String = label.text.get_slice(" ", 0).to_lower()
			if attributes.has(label_attribute):
				label.text = "%s %d" % [label_attribute.capitalize(), int(attributes[label_attribute])]


func _set_available_points(value: int) -> void:
	available_points_label.text = "Available points: %d" % value
	available_points = value
