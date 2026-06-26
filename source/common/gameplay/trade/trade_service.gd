class_name TradeService
## Server-side helpers for the world trade tables: builds the broadcast state for a table
## and pushes it to every player in the instance (traders + bystanders all see the same).


## Broadcast a table's current state to all peers in the instance.
static func broadcast(instance: Node, table: TradeTable) -> void:
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"trade.table", build_state(table)),
		instance.name
	)


## The networked view of a table: id, both seats (name, player id, accepted flag, offered
## gold + items) and the seconds left on the confirm countdown (0 = none).
static func build_state(table: TradeTable) -> Dictionary:
	var seats: Array = []
	for i: int in 2:
		var occupant = table.seat_players[i]
		if is_instance_valid(occupant):
			seats.append({
				"name": occupant.display_name,
				"id": occupant.player_resource.player_id,
				"accepted": table.seat_accepted[i],
				"gold": int(table.seat_offers[i].get("gold", 0)),
				"items": _items_view(table.seat_offers[i].get("items", {})),
			})
		else:
			seats.append({"name": "", "id": 0, "accepted": false, "gold": 0, "items": []})

	var countdown: int = 0
	if table.countdown_until > 0:
		countdown = maxi(0, int(ceil((table.countdown_until - Time.get_ticks_msec()) / 1000.0)))

	return {"id": table.table_id, "seats": seats, "countdown": countdown, "join_cost": table.join_cost}


static func _items_view(items: Dictionary) -> Array:
	var out: Array = []
	for item_id in items:
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(item_id))
		out.append({
			"id": int(item_id),
			"name": str(item.item_name) if item else "?",
			"amount": int(items[item_id]),
		})
	return out
