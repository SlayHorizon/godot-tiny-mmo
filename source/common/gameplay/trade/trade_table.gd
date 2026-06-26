class_name TradeTable
extends Area2D
## A world trade table. Click to claim a seat; place items + gold into your offer; both
## players accept; after a short countdown the server performs an atomic swap. The table
## broadcasts its full state to the whole instance, so seats AND offers are visible
## in-world to everyone nearby (no separate spectator system needed).
##
## Setup: Area2D + CollisionShape2D over the table, a unique table_id, direct child of
## the Map (like the merchant / crafting station).

@export var table_id: int = 0
## Max distance a player can be from the table to claim or keep a seat (auto-removed past it).
@export var seat_range: float = 80.0
## Gold charged once to claim a seat (a small anti-abuse tax; kept whether or not the
## trade completes). 0 = free.
@export var join_cost: int = 3

const COUNTDOWN_MS: int = 12000
## Max distinct items one player can put in an offer (keeps trades simple).
const MAX_OFFER_ITEMS: int = 6

## Server only. Per seat (index 0 = A, 1 = B):
var seat_players: Array = [null, null]               # Player ref or null
var seat_offers: Array = []                          # {"items": {item_id:int -> amount:int}, "gold": int}
var seat_accepted: Array[bool] = [false, false]
## When (ticks_msec) the swap fires once both have accepted (0 = no countdown running).
var countdown_until: int = 0

var _seat_labels: Array[Label] = []
var _countdown_label: Label


func _ready() -> void:
	if multiplayer.is_server():
		seat_offers = [_empty_offer(), _empty_offer()]
		input_pickable = false
		set_physics_process(true) # auto-leave + countdown
		return
	set_physics_process(false)
	input_pickable = true
	input_event.connect(_on_input_event)
	_build_display()
	Client.subscribe(&"trade.table", _on_table_state)


static func _empty_offer() -> Dictionary:
	return {"items": {}, "gold": 0}


# --- Server session ---

func _physics_process(_delta: float) -> void:
	var changed: bool = false

	# Auto-remove players who walked away or disconnected.
	for i: int in seat_players.size():
		var occupant = seat_players[i]
		if occupant == null:
			continue
		if not is_instance_valid(occupant) or occupant.global_position.distance_to(global_position) > seat_range:
			_clear_seat(i)
			changed = true

	# Fire the swap when the countdown elapses.
	if countdown_until > 0 and Time.get_ticks_msec() >= countdown_until:
		_complete_trade()
		changed = true

	if changed:
		var instance: Node = _server_instance()
		if instance:
			TradeService.broadcast(instance, self)


func _clear_seat(index: int) -> void:
	seat_players[index] = null
	seat_offers[index] = _empty_offer()
	_reset_accepts()


## Any change to seats/offers invalidates both accepts and cancels a pending swap.
func _reset_accepts() -> void:
	seat_accepted = [false, false]
	countdown_until = 0


func server_remove_player(player: Player) -> bool:
	var seat: int = seat_players.find(player)
	if seat == -1:
		return false
	_clear_seat(seat)
	return true


func server_set_offer(player: Player, items: Dictionary, gold: int) -> void:
	var seat: int = seat_players.find(player)
	if seat == -1:
		return
	seat_offers[seat] = {"items": items, "gold": gold}
	_reset_accepts() # changing an offer un-confirms both sides


func server_set_accepted(player: Player, accepted: bool) -> void:
	var seat: int = seat_players.find(player)
	if seat == -1:
		return
	seat_accepted[seat] = accepted
	if seat_accepted[0] and seat_accepted[1]:
		countdown_until = Time.get_ticks_msec() + COUNTDOWN_MS
	else:
		countdown_until = 0


func _complete_trade() -> void:
	countdown_until = 0
	var a = seat_players[0]
	var b = seat_players[1]
	var ok: bool = is_instance_valid(a) and is_instance_valid(b) and _try_swap(a, b)

	# Clear the table either way; players stay seated and can trade again.
	seat_offers = [_empty_offer(), _empty_offer()]
	seat_accepted = [false, false]

	for participant in [a, b]:
		if is_instance_valid(participant):
			var peer_id: int = int(participant.player_resource.current_peer_id)
			if peer_id > 0:
				WorldServer.curr.data_push.rpc_id(peer_id, &"trade.result", {"ok": ok})


## Validates both offers against current inventories, then swaps atomically.
func _try_swap(a: Player, b: Player) -> bool:
	var inv_a: Dictionary = a.player_resource.inventory
	var inv_b: Dictionary = b.player_resource.inventory
	if not _can_afford(inv_a, seat_offers[0]) or not _can_afford(inv_b, seat_offers[1]):
		return false
	_give(inv_a, inv_b, seat_offers[0])
	_give(inv_b, inv_a, seat_offers[1])
	return true


func _can_afford(inventory: Dictionary, offer: Dictionary) -> bool:
	if Inventory.count(inventory, Economy.gold_id()) < int(offer.get("gold", 0)):
		return false
	var items: Dictionary = offer.get("items", {})
	for item_id in items:
		if Inventory.count(inventory, int(item_id)) < int(items[item_id]):
			return false
	return true


func _give(from_inventory: Dictionary, to_inventory: Dictionary, offer: Dictionary) -> void:
	var gold: int = int(offer.get("gold", 0))
	if gold > 0:
		Inventory.remove_amount_by_id(from_inventory, Economy.gold_id(), gold)
		Inventory.add_item(to_inventory, Economy.gold_id(), gold)
	var items: Dictionary = offer.get("items", {})
	for item_id in items:
		var amount: int = int(items[item_id])
		Inventory.remove_amount_by_id(from_inventory, int(item_id), amount)
		for i: int in amount:
			Inventory.add_item(to_inventory, int(item_id), 1)


func _server_instance() -> Node:
	var node: Node = get_parent()
	while node and not (node is SubViewport):
		node = node.get_parent()
	return node


# --- Client input + in-world display ---

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if clicked:
		# Just open the panel (view). Joining a seat is an explicit button (costs gold).
		ClientState.set_viewed_trade(table_id)


func _build_display() -> void:
	for i: int in 2:
		var label: Label = Label.new()
		label.position = Vector2(-60.0, -96.0 + i * 40.0)
		label.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.4))
		add_child(label)
		_seat_labels.append(label)
	_countdown_label = Label.new()
	_countdown_label.position = Vector2(-60.0, -112.0)
	_countdown_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
	add_child(_countdown_label)


func _on_table_state(data: Dictionary) -> void:
	if int(data.get("id", 0)) != table_id:
		return
	var seats: Array = data.get("seats", [])
	for i: int in _seat_labels.size():
		_seat_labels[i].text = _format_seat(seats[i]) if i < seats.size() else ""
	var countdown: int = int(data.get("countdown", 0))
	_countdown_label.text = "Trading in %d…" % countdown if countdown > 0 else ""


func _format_seat(seat: Dictionary) -> String:
	var occupant: String = str(seat.get("name", ""))
	if occupant.is_empty():
		return ""
	var text: String = occupant + (" ✓" if seat.get("accepted", false) else "")
	for item: Dictionary in seat.get("items", []):
		text += "\n  %dx %s" % [int(item.get("amount", 1)), str(item.get("name", ""))]
	var gold: int = int(seat.get("gold", 0))
	if gold > 0:
		text += "\n  %dg" % gold
	return text
