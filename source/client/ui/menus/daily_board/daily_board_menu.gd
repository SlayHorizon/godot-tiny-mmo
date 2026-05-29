extends Control
## Daily quest board. Shows the player's 3 rolled dailies with progress + claim
## buttons. Auto-fetches state on open and after each claim. Resets at UTC
## midnight (server-driven; we just display the time until refresh).
##
## All UI children are wired through @export node paths so the .tscn stays
## editable in the inspector. Quest rows themselves are spawned dynamically
## under entries_box from the server response — variable count not worth
## hand-authoring 3 slots.

@export var title_label: Label
@export var refresh_label: Label
@export var entries_box: VBoxContainer
@export var close_button: Button
@export var status_label: Label


func _ready() -> void:
	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


## Called by HUD.display_menu when the board is opened (arg is unused — there's
## only one set of dailies per player, not per board).
func open(_unused: int) -> void:
	_refresh()


func _refresh() -> void:
	status_label.text = "Loading..."
	Client.request_data(
		&"quest.board.info",
		_apply,
		{},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _apply(response: Dictionary) -> void:
	for child: Node in entries_box.get_children():
		child.queue_free()
	if not bool(response.get("ok", false)):
		status_label.text = "Couldn't load dailies: %s" % response.get("reason", "unknown")
		return

	var entries: Array = response.get("entries", [])
	if entries.is_empty():
		status_label.text = "No dailies available at your level yet."
		return
	status_label.text = ""

	# Countdown to next refresh.
	var refresh_at_ms: int = int(response.get("refresh_at_ms", 0))
	var seconds_left: int = maxi(0, int((refresh_at_ms - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	refresh_label.text = "Resets in %s" % _fmt_duration(seconds_left)

	for entry: Dictionary in entries:
		entries_box.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_right", 10)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	card.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 4)
	margin.add_child(vbox)

	var desc: Label = Label.new()
	desc.text = str(entry.get("description", "?"))
	vbox.add_child(desc)

	var meta: HBoxContainer = HBoxContainer.new()
	meta.add_theme_constant_override(&"separation", 12)
	vbox.add_child(meta)

	var progress: Label = Label.new()
	progress.text = "Progress: %d / %d" % [int(entry.get("progress", 0)), int(entry.get("required", 0))]
	progress.size_flags_horizontal = SIZE_EXPAND_FILL
	meta.add_child(progress)

	var reward: Label = Label.new()
	reward.text = "+%d XP · %d g" % [int(entry.get("reward_xp", 0)), int(entry.get("reward_gold", 0))]
	meta.add_child(reward)

	var claim: Button = Button.new()
	if bool(entry.get("claimed", false)):
		claim.text = "Claimed ✓"
		claim.disabled = true
	elif bool(entry.get("complete", false)):
		claim.text = "Claim"
		claim.pressed.connect(_claim.bind(int(entry.get("template_id", 0))))
	else:
		claim.text = "Claim"
		claim.disabled = true
	vbox.add_child(claim)

	return card


func _claim(template_id: int) -> void:
	Client.request_data(
		&"quest.board.claim",
		_on_claimed,
		{"template_id": template_id},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _on_claimed(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		status_label.text = "Claim failed: %s" % response.get("reason", "unknown")
		return
	# Re-fetch so the row updates to "Claimed ✓".
	_refresh()


func _fmt_duration(seconds: int) -> String:
	if seconds <= 0:
		return "now"
	@warning_ignore("integer_division")
	var h: int = seconds / 3600
	@warning_ignore("integer_division")
	var m: int = (seconds % 3600) / 60
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % m
