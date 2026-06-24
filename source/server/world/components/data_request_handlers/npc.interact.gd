extends DataRequestHandler
## Fired when a player opens an NPC's interactions (i.e. talks to it). Advances any
## VISIT quest objective that targets this giver, so a "talk to NPC X" quest
## completes on conversation — not only when the player drills into the Quests
## sub-menu. No-op (still ok) for NPCs that aren't quest givers in this map.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var npc_id: int = int(args.get("npc", 0))
	if npc_id <= 0:
		return {"ok": false}

	# Only count it as a visit if this NPC is actually a quest giver here.
	if instance.instance_map.get_quest_giver(npc_id) == null:
		return {"ok": true}

	# Mirrors quest.list's giver branch: on_visit advances VISIT objectives (and
	# auto-completes/­toasts as needed); push quest.update so the HUD reflects it.
	var visit_updates: Array = QuestService.on_visit(player.player_resource, npc_id, peer_id, instance)
	if not visit_updates.is_empty():
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": visit_updates})
	return {"ok": true}
