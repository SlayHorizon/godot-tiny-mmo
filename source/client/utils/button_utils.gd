class_name ButtonUtils


static func set_focus_for_children_buttons(target: Node) -> void:
	var buttons: Array[Button] = find_buttons_in_children(target)
	if buttons.size() >= 2:
		set_focus_neighbors_for_buttons(buttons)


# Similar to find_children("*", "CharacterClassButton", true)
static func find_buttons_in_children(target: Node, type_hint: Variant = Button) -> Array:
	var buttons: Array = []
	for child: Node in target.get_children():
		if is_instance_of(child, type_hint):
			buttons.append(child)
		if child.get_child_count() > 0:
			buttons.append_array(find_buttons_in_children(child))
	return buttons


static func set_focus_neighbors_for_buttons(buttons: Array[Button]) -> void:
	var previous_button: Button = buttons.front()
	for button: Button in buttons:
		button.focus_neighbor_top = previous_button.get_path()
		previous_button.focus_neighbor_bottom = button.get_path()
		previous_button = button
	buttons.front().focus_neighbor_top = buttons.back().get_path()
	buttons.back().focus_neighbor_bottom = buttons.front().get_path()
