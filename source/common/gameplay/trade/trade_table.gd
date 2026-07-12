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
## Per-seat tint for the in-world offer labels (seat 0 = gold, seat 1 = blue) — the SAME tones the
## spar banner uses, so the colour->player association is learned once across features.
const SEAT_COLORS: PackedStringArray = ["f2bd2a", "73b3ff"]

## Server only. Per seat (index 0 = A, 1 = B):
var seat_players: Array = [null, null]               # Player ref or null
var seat_offers: Array = []                          # {"items": {item_id:int -> amount:int}, "gold": int}
var seat_accepted: Array[bool] = [false, false]
## When (ticks_msec) the swap fires once both have accepted (0 = no countdown running).
var countdown_until: int = 0

var _seat_labels: Array[RichTextLabel] = []
var _countdown_label: Label
var _countdown_tween: Tween
var _hovered: bool = false # client: cursor over the table (suppresses the attack so a click opens it)


func _ready() -> void:
	# Self-register with the owning map (BEFORE the server early-return below).
	var map: Map = Map.of(self)
	if map != null:
		map.register_keyed(map.trade_tables, table_id, self, "trade table")
	if multiplayer.is_server():
		seat_offers = [_empty_offer(), _empty_offer()]
		input_pickable = false
		set_physics_process(true) # auto-leave + countdown
		return
	set_physics_process(false)
	# Clicking the table opens the trade view. Use the shared ClickableArea (like NPCs / players /
	# statues) instead of the table's own input_event, so the same left-click/tap detection AND the
	# hover combat-suppression apply — clicking the table no longer also fires your weapon.
	_spawn_click_area()
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
	# Clamp to what the player ACTUALLY holds — joining costs gold so the client's max can lag, and
	# offering more than you own would just fail the swap at completion (a confusing silent failure).
	var inventory: Dictionary = player.player_resource.inventory
	var clamped: Dictionary = {}
	for item_id: Variant in items:
		var want: int = mini(int(items[item_id]), Inventory.count(inventory, int(item_id)))
		if want > 0:
			clamped[int(item_id)] = want
	seat_offers[seat] = {"items": clamped, "gold": clampi(int(gold), 0, Inventory.count(inventory, Economy.gold_id()))}
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


## Server: a player-facing summary of an offer (item names + amounts + gold) for the result toast.
func _describe_offer(offer: Dictionary) -> Dictionary:
	var items: Array = []
	var offer_items: Dictionary = offer.get("items", {})
	for item_id: Variant in offer_items:
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(item_id))
		items.append({"name": str(item.item_name) if item else "?", "amount": int(offer_items[item_id])})
	return {"items": items, "gold": int(offer.get("gold", 0))}


func _complete_trade() -> void:
	countdown_until = 0
	var a = seat_players[0]
	var b = seat_players[1]
	var ok: bool = is_instance_valid(a) and is_instance_valid(b) and _try_swap(a, b)

	# Capture what each side RECEIVES (the other's offer) before clearing, for the result toast.
	var received: Array = [_describe_offer(seat_offers[1]), _describe_offer(seat_offers[0])]

	# Clear the table either way; players stay seated and can trade again.
	seat_offers = [_empty_offer(), _empty_offer()]
	seat_accepted = [false, false]

	for i: int in 2:
		var participant = seat_players[i]
		if is_instance_valid(participant):
			var peer_id: int = int(participant.player_resource.current_peer_id)
			if peer_id > 0:
				WorldServer.curr.data_push.rpc_id(peer_id, &"trade.result", {"ok": ok, "received": received[i] if ok else {}})


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

func _spawn_click_area() -> void:
	var area: ClickableArea = ClickableArea.new()
	var collision: CollisionShape2D = CollisionShape2D.new()
	var existing: CollisionShape2D = _find_collision_shape()
	if existing != null and existing.shape != null:
		collision.shape = existing.shape.duplicate() # match the placed table's clickable footprint
		collision.position = existing.position
	else:
		var rect: RectangleShape2D = RectangleShape2D.new()
		rect.size = Vector2(48, 32)
		collision.shape = rect
	area.add_child(collision)
	add_child(area)
	area.clicked.connect(_on_clicked)
	# Hover suppresses the local player's attack so a click opens the table instead of also shooting.
	area.mouse_entered.connect(_set_hover.bind(true))
	area.mouse_exited.connect(_set_hover.bind(false))
	area.tree_exiting.connect(_set_hover.bind(false))


func _find_collision_shape() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D:
			return child as CollisionShape2D
	return null


func _on_clicked() -> void:
	if _player_in_range():
		ClientState.set_viewed_trade(table_id) # view only; claiming a seat is an explicit button
	else:
		Toaster.toast("Too far from the trade table.")


## True when the local player is within seat_range — the same distance the server uses to keep a
## seat — so you can't even open the panel from across the map. Null-safe before the player exists.
func _player_in_range() -> bool:
	var lp: LocalPlayer = ClientState.local_player
	if lp == null or not is_instance_valid(lp):
		return false
	return global_position.distance_to(lp.global_position) <= seat_range


func _set_hover(on: bool) -> void:
	if not GameMode.is_client() or on == _hovered:
		return
	_hovered = on
	ClientState.world_interactables_hovered += 1 if on else -1


func _build_display() -> void:
	# Stack the countdown + both seat offers in a VBox so they AUTO-SPACE. Fixed y-offsets let a tall
	# offer (name + up to 6 items + gold) grow down into the next seat's label and overlap it.
	var box: VBoxContainer = VBoxContainer.new()
	box.position = Vector2(-72.0, -120.0) # above the table; grows downward — tweak per placement
	box.add_theme_constant_override(&"separation", 4)
	add_child(box)
	_countdown_label = Label.new()
	_countdown_label.add_theme_color_override(&"font_color", Color(0.5, 0.9, 0.5))
	box.add_child(_countdown_label)
	for i: int in 2:
		# RichTextLabel so each seat's offer is tinted by its player colour (seat 0 = gold, seat 1 =
		# blue) — so onlookers can tell whose items are whose at a glance.
		var label: RichTextLabel = RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size = Vector2(160.0, 0.0)
		box.add_child(label)
		_seat_labels.append(label)


func _on_table_state(data: Dictionary) -> void:
	if int(data.get("id", 0)) != table_id:
		return
	var seats: Array = data.get("seats", [])
	for i: int in _seat_labels.size():
		_seat_labels[i].text = _format_seat(seats[i], i) if i < seats.size() else ""
	# Countdown ticks down locally (smooth) from the server's start value; a later push with
	# countdown == 0 (un-accept / complete) cancels it — the server stays authoritative.
	var countdown: int = int(data.get("countdown", 0))
	if countdown > 0:
		_run_countdown(countdown)
	else:
		_stop_countdown()


func _format_seat(seat: Dictionary, index: int) -> String:
	var occupant: String = str(seat.get("name", ""))
	if occupant.is_empty():
		return ""
	var text: String = occupant + (" (ready)" if seat.get("accepted", false) else "")
	for item: Dictionary in seat.get("items", []):
		text += "\n  %dx %s" % [int(item.get("amount", 1)), str(item.get("name", ""))]
	var gold: int = int(seat.get("gold", 0))
	if gold > 0:
		text += "\n  %dg" % gold
	return "[color=#%s]%s[/color]" % [SEAT_COLORS[index % SEAT_COLORS.size()], text]


## Smoothly tick the in-world countdown from `seconds` to 0 (restarted on each fresh server value).
func _run_countdown(seconds: int) -> void:
	_stop_countdown()
	_countdown_tween = create_tween()
	_countdown_tween.tween_method(_set_countdown_text, float(seconds), 0.0, float(seconds))


func _set_countdown_text(value: float) -> void:
	_countdown_label.text = "Trading in %d…" % maxi(1, ceili(value))


func _stop_countdown() -> void:
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = null
	_countdown_label.text = ""
