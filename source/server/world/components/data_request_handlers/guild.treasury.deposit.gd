extends DataRequestHandler

## A member deposits gold into their guild treasury. Gold converts to treasury
## (the abstract guild currency) and is NOT transferable back to players. Any
## member may donate to a guild they belong to. Conversion is 1:1 for now —
## tune via the rate below if gold deposits start trivializing territory income.
const GOLD_PER_TREASURY: int = 1
const MIN_DEPOSIT: int = 1


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var world_server: WorldServer = instance.world_server
	var store: WorldStoreSqlite = world_server.database.store

	var player: PlayerResource = world_server.connected_players.get(peer_id)
	if player == null:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}

	var amount: int = int(args.get("amount", 0))
	if amount < MIN_DEPOSIT:
		return {"error": 1, "ok": false, "message": "Invalid amount."}

	var guild_id: int = int(args.get("id", player.active_guild_id))
	if guild_id <= 0 or not player.joined_guild_ids.has(guild_id):
		return {"error": 1, "ok": false, "message": "You're not a member of that guild."}

	# Cost is in gold; what the guild gains is the converted treasury.
	@warning_ignore("integer_division")
	var gained: int = amount / GOLD_PER_TREASURY
	if gained <= 0:
		return {"error": 1, "ok": false, "message": "Deposit too small."}
	var cost: int = gained * GOLD_PER_TREASURY

	var gold_id: int = Economy.gold_id()
	if Inventory.count(player.inventory, gold_id) < cost:
		return {"error": 1, "ok": false, "message": "Not enough gold."}

	var guild: Guild = store.get_guild(guild_id)
	if guild == null:
		return {"error": 1, "ok": false, "message": "Guild not found."}

	store.begin()
	Inventory.remove_amount_by_id(player.inventory, gold_id, cost)
	guild.treasury += gained
	store.save_guild(guild)
	store.save_player(player)
	store.commit()

	return {"ok": true, "treasury": guild.treasury, "deposited": gained}
