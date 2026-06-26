class_name StatusService
## Pushes a player their own status snapshot (timed buffs, damage-over-time
## debuffs, in-combat flag) for the HUD status strip. Server-side only, called
## once per second from the instance StatusTick — 1 Hz is plenty for icons
## that only ever show whole-second countdowns.
##
## Durations cross the wire as REMAINING SECONDS, never absolute timestamps:
## client and server run separate clocks (Time.get_ticks_msec is per-process),
## so an expires_ms would be meaningless on the other side.


static func sync(player: Player) -> void:
	if player == null or player.player_resource == null:
		return
	var peer_id: int = int(player.player_resource.current_peer_id)
	if peer_id <= 0 or WorldServer.curr == null:
		return

	var now: int = Time.get_ticks_msec()

	var buffs: Array = []
	var debuffs: Array = []
	# A timed stat buff with a NEGATIVE amount is a debuff (Crippling Strike's
	# move_speed slow) — route it to the debuff strip with a friendly id so the
	# HUD shows it red/down, not green/up.
	for buff: Dictionary in player.player_resource.active_buffs:
		var stat: String = String(buff["stat"])
		var remaining: int = int(ceil((int(buff["expires_ms"]) - now) / 1000.0))
		if float(buff["amount"]) < 0.0:
			var debuff_id: String = "slow" if stat == String(Stat.MOVE_SPEED) else stat
			debuffs.append({"id": debuff_id, "remaining": remaining})
		else:
			buffs.append({"id": stat, "remaining": remaining})

	for child: Node in player.get_children():
		if child is DamageOverTime:
			debuffs.append({
				"id": String((child as DamageOverTime).kind),
				"remaining": (child as DamageOverTime).remaining_seconds(),
			})

	WorldServer.curr.data_push.rpc_id(peer_id, &"status.sync", {
		"buffs": buffs,
		"debuffs": debuffs,
		"in_combat": player.is_in_combat(),
	})
