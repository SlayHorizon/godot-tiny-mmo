extends DataRequestHandler
## Returns one territory flag's current state so a client entering the instance
## can pull it on _ready. The one-shot flag.update broadcast may have fired before
## the client joined (especially on warp re-entry), leaving the flag "unclaimed"
## client-side until the next capture — this lets the client fetch the truth.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var flag_id: int = int(args.get("flag_id", -1))
	if flag_id < 0 or instance.instance_map == null:
		return {}
	var flag: TerritoryFlag = instance.instance_map.territory_flags.get(flag_id)
	if flag == null:
		return {}
	return flag.get_state_payload()
