extends MenuShell
## Inbox: a mail list (left) + detail pane (right). Reads mail.list, marks a mail
## read on open, previews + claims reward attachments (server reuses the redeem
## grant pipeline), and soft-deletes. The detail's Claim/Delete bar is pinned
## below a scrolling body, so it stays visible no matter how long the message.
## Content-heavy, so it's a full MenuShell — unlike the tiny redeem popup.
## See docs/mailbox.md.

var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _detail: VBoxContainer
var _mails: Array = []
var _selected_id: int = 0

# GM compose form — the "New mail" button + fields appear only for senior-admins
# (mail.list reports can_send; mail.send re-checks server-side).
var _compose_button: Button
var _compose_target: LineEdit
var _compose_from: LineEdit
var _compose_subject: LineEdit
var _compose_body: TextEdit
var _compose_attach: LineEdit
var _compose_status: Label


func _ready() -> void:
	build_shell("Mail", null, true)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	# First open: the menu starts visible, so the launcher's show() is a no-op and
	# visibility_changed never fires — seed the inbox here. Reopens use the signal.
	_refresh()


func _build_layout() -> void:
	var split: HBoxContainer = HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", 12)
	content.add_child(split)

	_list_scroll = ScrollContainer.new()
	_list_scroll.custom_minimum_size = Vector2(280, 0)
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 4)
	_list_scroll.add_child(_list)

	# Right pane: header + scrolling body, with the action bar PINNED below it (a
	# sibling, NOT inside the scroll) so Claim/Delete stay put for long mails.
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override(&"separation", 8)
	split.add_child(_detail)

	# GM-only "New mail" button in the header (shown when mail.list reports can_send).
	_compose_button = Button.new()
	_compose_button.text = "New mail"
	_compose_button.visible = false
	_compose_button.pressed.connect(_show_compose)
	header_right.add_child(_compose_button)
	header_right.move_child(_compose_button, 0) # keep Close right-most


func _refresh() -> void:
	_selected_id = 0
	_set_detail_placeholder("Select a message.")
	var result: Array = await Client.request_data_await(&"mail.list", {}, String(InstanceClient.current.name))
	if not is_inside_tree() or not visible:
		return
	_mails = []
	if result[1] != OK or not bool((result[0] as Dictionary).get("ok", false)):
		_clear(_list)
		var err: Label = Label.new()
		err.text = "Couldn't load mail."
		_list.add_child(err)
		return
	var payload: Dictionary = result[0] as Dictionary
	_mails = payload.get("mails", [])
	_compose_button.visible = bool(payload.get("can_send", false))
	_rebuild_rows()


func _rebuild_rows() -> void:
	_clear(_list)
	if _mails.is_empty():
		var empty: Label = Label.new()
		empty.text = "No mail."
		empty.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.75))
		_list.add_child(empty)
		return
	for mail: Dictionary in _mails:
		_list.add_child(_make_row(mail))
	DragScroll.enable(_list_scroll) # touch/mouse drag-to-scroll the inbox list


func _make_row(mail: Dictionary) -> Button:
	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, 46)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	var unread: bool = not bool(mail.get("read", false))
	# Reward dot shows only while there's an UNCLAIMED reward — clears once claimed.
	var has_unclaimed: bool = not (mail.get("rewards", []) as Array).is_empty() and not bool(mail.get("claimed", false))
	var prefix: String = "• " if unread else "    "
	row.text = "%s%s%s" % [prefix, str(mail.get("subject", "(no subject)")), "  ●" if has_unclaimed else ""]
	row.pressed.connect(_on_select.bind(int(mail.get("mail_id", 0))))
	return row


func _on_select(mail_id: int) -> void:
	_selected_id = mail_id
	var mail: Dictionary = _find(mail_id)
	if mail.is_empty():
		return
	if not bool(mail.get("read", false)):
		mail["read"] = true
		Client.request_data(&"mail.read", Callable(), {"mail_id": mail_id}, String(InstanceClient.current.name))
		_rebuild_rows()
	_show_detail(mail)


func _show_detail(mail: Dictionary) -> void:
	_clear(_detail)

	# --- Fixed header ---
	var subject: Label = Label.new()
	subject.text = str(mail.get("subject", ""))
	subject.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	subject.add_theme_font_size_override(&"font_size", 20)
	subject.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(subject)

	var meta: Label = Label.new()
	meta.text = "From %s" % str(mail.get("sender_name", "System"))
	meta.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.75))
	meta.add_theme_font_size_override(&"font_size", 12)
	_detail.add_child(meta)

	_detail.add_child(HSeparator.new())

	# --- Body (+ reward preview) in a RichTextLabel: it wraps to its own width and
	# scrolls itself, so long mail reflows reliably, and it expands to push the
	# action bar to the bottom. (A plain Label inside a ScrollContainer would NOT
	# wrap — the scroll sizes its child to content width, defeating autowrap.) ---
	var rewards: Array = mail.get("rewards", [])
	var rtl: RichTextLabel = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = false
	rtl.scroll_active = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.focus_mode = Control.FOCUS_NONE
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var text: String = "[color=#e0e6f2]%s[/color]" % _bb(str(mail.get("body", "")))
	if not rewards.is_empty():
		var claimed: bool = bool(mail.get("claimed", false))
		text += "\n\n[color=#d9dbeb]%s[/color]" % ("Claimed rewards:" if claimed else "Rewards:")
		for r: Variant in rewards:
			text += "\n[color=#f2ebc7]•  %s[/color]" % _bb(RewardFormat.describe(r as Dictionary))
	rtl.text = text
	_detail.add_child(rtl)

	# --- Pinned action bar (sibling of the scroll, not inside it) ---
	# Right-aligned so Delete stays at the right edge and Claim slides in to its
	# left when present, instead of shoving Delete around.
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_detail.add_child(buttons)

	var has_unclaimed: bool = not rewards.is_empty() and not bool(mail.get("claimed", false))

	if not rewards.is_empty():
		var claim: Button = Button.new()
		claim.text = "Claim reward" if has_unclaimed else "Claimed"
		claim.disabled = not has_unclaimed
		claim.custom_minimum_size = Vector2(140, 38)
		if has_unclaimed: # accent the live reward action so it pops vs. neutral Delete
			claim.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.45))
			claim.add_theme_color_override(&"font_hover_color", Color(1.0, 0.92, 0.62))
		claim.pressed.connect(_on_claim.bind(int(mail.get("mail_id", 0))))
		buttons.add_child(claim)

	var del: Button = Button.new()
	del.text = "Delete"
	del.custom_minimum_size = Vector2(110, 38)
	del.pressed.connect(_on_delete.bind(int(mail.get("mail_id", 0)), del, has_unclaimed))
	buttons.add_child(del)


func _on_claim(mail_id: int) -> void:
	var result: Array = await Client.request_data_await(&"mail.claim", {"mail_id": mail_id}, String(InstanceClient.current.name))
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if bool(data.get("ok", false)):
		var lines: PackedStringArray = PackedStringArray()
		for r: Variant in (data.get("rewards", []) as Array):
			lines.append(RewardFormat.describe(r as Dictionary))
		Toaster.toast_group("Claimed!", lines, 3.0)
		var mail: Dictionary = _find(mail_id)
		if not mail.is_empty():
			mail["claimed"] = true
			_rebuild_rows() # clears the reward dot in the list
			if _selected_id == mail_id:
				_show_detail(mail) # Claim → "Claimed", preview heading flips
	else:
		Toaster.toast("Couldn't claim that mail.")


func _on_delete(mail_id: int, button: Button, has_unclaimed: bool) -> void:
	# Two-step guard ONLY when an unclaimed reward would be lost — first press arms
	# the button, second deletes. Claimed / reward-less mail deletes in one press.
	# The armed flag lives on the button, so reselecting (fresh button) resets it.
	if has_unclaimed and not bool(button.get_meta("armed", false)):
		button.set_meta("armed", true)
		button.text = "Confirm delete?"
		button.add_theme_color_override(&"font_color", Color(0.95, 0.6, 0.55))
		return
	Client.request_data(&"mail.delete", Callable(), {"mail_id": mail_id}, String(InstanceClient.current.name))
	for i: int in _mails.size():
		if int((_mails[i] as Dictionary).get("mail_id", 0)) == mail_id:
			_mails.remove_at(i)
			break
	_rebuild_rows()
	if _selected_id == mail_id:
		_selected_id = 0
		_set_detail_placeholder("Select a message.")


func _set_detail_placeholder(text: String) -> void:
	_clear(_detail)
	var placeholder: Label = Label.new()
	placeholder.text = text
	placeholder.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.75))
	_detail.add_child(placeholder)


## GM compose form (in the detail pane): a multiline TextEdit body, so there's no
## chat length cap. Sends via mail.send (the server re-checks senior-admin).
func _show_compose() -> void:
	_selected_id = 0
	_clear(_detail)
	var title: Label = Label.new()
	title.text = "New mail"
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	title.add_theme_font_size_override(&"font_size", 20)
	_detail.add_child(title)

	_compose_target = LineEdit.new()
	_compose_target.text = "self"
	_compose_target.placeholder_text = "self · #id · @account · all · online"
	_detail.add_child(_field_row("To", _compose_target))

	_compose_from = LineEdit.new()
	_compose_from.placeholder_text = "System  (optional)"
	_detail.add_child(_field_row("From", _compose_from))

	_compose_subject = LineEdit.new()
	_compose_subject.placeholder_text = "Subject"
	_detail.add_child(_field_row("Subject", _compose_subject))

	var body_label: Label = Label.new()
	body_label.text = "Body"
	body_label.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.75))
	_detail.add_child(body_label)
	_compose_body = TextEdit.new()
	_compose_body.placeholder_text = "Write your message…"
	_compose_body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_compose_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compose_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(_compose_body)

	_compose_attach = LineEdit.new()
	_compose_attach.placeholder_text = "gold:100, item:1x3, title:Name  (optional)"
	_detail.add_child(_field_row("Rewards", _compose_attach))

	_compose_status = Label.new()
	_compose_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_compose_status)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_detail.add_child(buttons)
	var send: Button = Button.new()
	send.text = "Send"
	send.custom_minimum_size = Vector2(120, 38)
	send.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.45))
	send.pressed.connect(_on_send)
	buttons.add_child(send)
	var cancel: Button = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(100, 38)
	cancel.pressed.connect(func() -> void: _set_detail_placeholder("Select a message."))
	buttons.add_child(cancel)

	_compose_target.grab_focus.call_deferred()


func _on_send() -> void:
	var target: String = _compose_target.text.strip_edges()
	var subject: String = _compose_subject.text.strip_edges()
	var body: String = _compose_body.text.strip_edges()
	if target.is_empty() or subject.is_empty() or body.is_empty():
		_set_compose_status("Target, subject and body are required.", false)
		return
	_set_compose_status("Sending…", true)
	var result: Array = await Client.request_data_await(&"mail.send", {
		"target": target,
		"from": _compose_from.text.strip_edges(),
		"subject": subject,
		"body": body,
		"attachments": _compose_attach.text.strip_edges(),
	}, String(InstanceClient.current.name))
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if bool(data.get("ok", false)):
		Toaster.toast(str(data.get("message", "Mail sent.")))
		_refresh() # back to the inbox; a self/all mail shows up in the list
	else:
		_set_compose_status(str(data.get("message", "Couldn't send.")), false)


func _set_compose_status(text: String, neutral: bool) -> void:
	if not is_instance_valid(_compose_status):
		return
	_compose_status.add_theme_color_override(&"font_color", Color(0.75, 0.8, 0.9) if neutral else Color(0.95, 0.6, 0.55))
	_compose_status.text = text


func _field_row(label_text: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var lbl: Label = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(70, 0)
	lbl.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.75))
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _find(mail_id: int) -> Dictionary:
	for mail: Dictionary in _mails:
		if int(mail.get("mail_id", 0)) == mail_id:
			return mail
	return {}


func _clear(box: Node) -> void:
	for child: Node in box.get_children():
		child.queue_free()


## Escapes a literal '[' so GM-authored body text / reward names can't trip a
## bbcode tag in the RichTextLabel.
func _bb(text: String) -> String:
	return text.replace("[", "[lb]")
