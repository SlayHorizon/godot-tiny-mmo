extends MenuShell
## Friends list + player search. Built on the shared [MenuShell]: a search bar on
## top, then a scrollable list. With the search box empty the list shows your
## friends (online highlighted, offline dimmed); typing a query + Enter searches
## ALL players by character name, or by account name when the query starts with
## "@". Every row opens that player's profile, where add / remove friend lives.

var _search_field: LineEdit
var _status: Label
var _list: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	build_shell("Friends", null, true)

	# content is a MarginContainer (sizes every child to the same rect), so all the
	# pieces go in ONE VBox — otherwise the scroll list overlaps and covers the
	# search bar (you can't click it).
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	content.add_child(col)

	# Search bar: type a name and press Enter (or the button). Prefix with "@"
	# to match account names instead of character names.
	var search_bar: HBoxContainer = HBoxContainer.new()
	search_bar.add_theme_constant_override(&"separation", 6)
	col.add_child(search_bar)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "Search players…  (@name for account)"
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.clear_button_enabled = true
	_search_field.text_submitted.connect(_on_search_submitted)
	# Clearing the field drops back to the friends list.
	_search_field.text_changed.connect(_on_search_text_changed)
	search_bar.add_child(_search_field)

	var search_button: Button = Button.new()
	search_button.text = "Search"
	search_button.pressed.connect(func() -> void: _on_search_submitted(_search_field.text))
	search_bar.add_child(search_button)

	_status = Label.new()
	_status.modulate.a = 0.55
	_status.visible = false
	col.add_child(_status)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 4)
	_scroll.add_child(_list)

	visibility_changed.connect(_on_visibility_changed)
	if visible:
		_refresh()


func _on_visibility_changed() -> void:
	if visible:
		# Reopening always starts on the friends list, not a stale search.
		_search_field.text = ""
		_refresh()


# ---------------------------------------------------------------------------
# Friends list
# ---------------------------------------------------------------------------

func _refresh() -> void:
	_set_status("")
	Client.request_data(&"friend.list", fill_friend_list)


func fill_friend_list(payload: Dictionary) -> void:
	_clear_list()

	if payload.is_empty():
		_empty_hint("No friends yet. Search above to find players.")
		return

	for friend_id: int in payload:
		var friend_payload: Dictionary = payload.get(friend_id, {})
		var friend_name: String = friend_payload.get("name", "Unknown")
		var is_online: bool = friend_payload.get("online", false)
		_add_row(int(friend_id), friend_name, "", is_online)

	DragScroll.enable(_scroll) # touch/mouse drag-to-scroll the friends list


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

func _on_search_text_changed(new_text: String) -> void:
	if new_text.strip_edges().is_empty():
		_refresh()


func _on_search_submitted(text: String) -> void:
	var query: String = text.strip_edges()
	if query.is_empty():
		_refresh()
		return
	_set_status("Searching…")
	Client.request_data(&"friend.search", _fill_search_results, {"query": query})


func _fill_search_results(payload: Dictionary) -> void:
	_clear_list()

	var results: Array = payload.get("results", [])
	if results.is_empty():
		_set_status(str(payload.get("msg", "No players found.")))
		return

	_set_status("%d result%s" % [results.size(), "" if results.size() == 1 else "s"])
	for entry: Dictionary in results:
		var account: String = str(entry.get("account", ""))
		var subtitle: String = ("@%s" % account) if not account.is_empty() else ""
		if entry.get("friend", false):
			subtitle = ("%s  · friend" % subtitle).strip_edges()
		_add_row(int(entry.get("id", 0)), str(entry.get("name", "Unknown")), subtitle, entry.get("online", false))

	DragScroll.enable(_scroll) # touch/mouse drag-to-scroll the search results


# ---------------------------------------------------------------------------
# Shared row + helpers
# ---------------------------------------------------------------------------

## A clickable player row: name (+ optional dim subtitle like the @account) and
## an online/offline suffix. Opens the player's profile on click.
func _add_row(player_id: int, display_name: String, subtitle: String, is_online: bool) -> void:
	if player_id <= 0:
		return
	var label: String = display_name
	if not subtitle.is_empty():
		label += "   %s" % subtitle
	label += "    %s" % ("● Online" if is_online else "Offline")

	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = label
	if is_online:
		button.add_theme_color_override(&"font_color", Color(0.55, 0.9, 0.55))
	else:
		button.modulate.a = 0.55
	button.pressed.connect(_on_friend_button_pressed.bind(player_id))
	_list.add_child(button)


func _on_friend_button_pressed(player_id: int) -> void:
	hide()
	ClientState.player_profile_requested.emit(player_id)


func _clear_list() -> void:
	for node: Node in _list.get_children():
		node.queue_free()


func _empty_hint(text: String) -> void:
	var empty: Label = Label.new()
	empty.text = text
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.modulate.a = 0.55
	_list.add_child(empty)


func _set_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()
