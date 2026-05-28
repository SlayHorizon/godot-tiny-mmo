extends Control
## Dialog opened when clicking a DuelMaster NPC. Shows queue status, lets the
## player join or leave, and gets out of the way once the match starts
## (countdown UI lives on the HUD so it stays visible after this menu is closed).
##
## Opened via HUD.display_menu("sparring", master_id), which calls open(arg).

@export var title_label: Label
@export var status_label: Label
@export var queue_button: Button
@export var close_button: Button

var _master_id: int = 0
var _in_queue: bool = false


func _ready() -> void:
	queue_button.pressed.connect(_on_queue_pressed)
	close_button.pressed.connect(hide)
	# Live queue size updates: server broadcasts on every join/leave so anyone
	# already viewing the dialog sees the count change without polling.
	Client.subscribe(&"sparring.queue.update", _on_queue_update)
	# Auto-hide when a match starts. Previously only the joiner's response
	# carried `started=true`; the first queuer was left staring at "0/2" after
	# the match kicked off.
	Client.subscribe(&"sparring.match.state", _on_match_state)


## Called by HUD.display_menu when this menu is shown with an arg.
func open(master_id: int) -> void:
	_master_id = master_id
	# Reset to a neutral state so the brief moment before _apply_state arrives
	# doesn't show stale "Leave Queue / 1 / 2" left over from before the last
	# match. (The match.state hide fires before the queue.update broadcast can
	# update the count, leaving the menu's text frozen at its pre-hide values
	# until a fresh response repaints it.)
	_reset_ui("Loading...")
	_refresh()


func _reset_ui(status_text: String) -> void:
	_in_queue = false
	status_label.text = status_text
	queue_button.text = "Queue for 1v1"
	queue_button.disabled = true


func _refresh() -> void:
	# Always send — even master_id 0 (likely a designer-forgot-to-set case)
	# hits the server, which responds with no_master so the menu can toast
	# + close. Silently returning here used to leave the button stuck at
	# "Loading...".
	Client.request_data(
		&"sparring.info",
		_apply_state,
		{"master_id": _master_id},
		InstanceClient.current.name if InstanceClient.current else ""
	)


func _apply_state(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		# Map the server's rejection reason to a friendly message and back out
		# of the menu — there's nothing to interact with.
		var reason: String = str(response.get("reason", ""))
		var msg: String = {
			"too_far":   "You're too far from the duel master.",
			"in_match":  "You're already in a match.",
			"no_master": "Duel master not found.",
			"no_player": "Couldn't find your character on the server.",
			"no_map":    "Map unavailable.",
		}.get(reason, "Sparring unavailable.")
		Toaster.toast(msg)
		hide()
		return
	var master_name: String = str(response.get("master_name", "Duel Master"))
	title_label.text = master_name
	var qsize: int = int(response.get("queue_size", 0))
	_in_queue = str(response.get("status", "")) == "queued"
	status_label.text = "Queue: %d / 2" % qsize
	queue_button.text = "Leave Queue" if _in_queue else "Queue for 1v1"
	queue_button.disabled = false
	# If a match just started in response to my join, the menu can step out.
	if bool(response.get("started", false)):
		hide()


func _on_queue_pressed() -> void:
	Client.request_data(
		&"sparring.queue",
		_apply_state,
		{"master_id": _master_id, "action": "leave" if _in_queue else "join"},
		InstanceClient.current.name if InstanceClient.current else ""
	)


## Live queue size push from the server (anyone joining/leaving this master
## triggers this on every viewer). Only updates the count if our menu is
## showing this same duel master.
func _on_queue_update(payload: Dictionary) -> void:
	if not visible:
		return
	if int(payload.get("master_id", 0)) != _master_id:
		return
	var qsize: int = int(payload.get("queue_size", 0))
	status_label.text = "Queue: %d / 2" % qsize


## Push fired to both fighters when a match starts/ends. Hide the menu on
## start so the first queuer doesn't sit with a stale dialog up.
func _on_match_state(payload: Dictionary) -> void:
	if bool(payload.get("in_match", false)) and visible:
		hide()
