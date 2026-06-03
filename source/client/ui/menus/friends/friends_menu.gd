extends MenuShell
## Friends list. Built on the shared [MenuShell]: a scrollable list of friends,
## each row clickable to open that player's profile. Online friends show a green
## status; offline ones are dimmed.

var _list: VBoxContainer


func _ready() -> void:
	build_shell("Friends")
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(_list)

	visibility_changed.connect(_on_visibility_changed)
	if visible:
		_refresh()


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	Client.request_data(&"friend.list", fill_friend_list)


func fill_friend_list(payload: Dictionary) -> void:
	for node: Node in _list.get_children():
		node.queue_free()

	if payload.is_empty():
		var empty: Label = Label.new()
		empty.text = "No friends yet."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate.a = 0.55
		_list.add_child(empty)
		return

	for friend_id: int in payload:
		var friend_payload: Dictionary = payload.get(friend_id, {})
		var friend_name: String = friend_payload.get("name", "Unknown")
		var is_online: bool = friend_payload.get("online", false)

		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(0, 44)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# Status suffix; offline rows are dimmed so online friends stand out.
		button.text = "%s    %s" % [friend_name, "● Online" if is_online else "Offline"]
		if is_online:
			button.add_theme_color_override(&"font_color", Color(0.55, 0.9, 0.55))
		else:
			button.modulate.a = 0.55
		button.pressed.connect(_on_friend_button_pressed.bind(friend_id))
		_list.add_child(button)


func _on_friend_button_pressed(player_id: int) -> void:
	hide()
	ClientState.player_profile_requested.emit(player_id)
