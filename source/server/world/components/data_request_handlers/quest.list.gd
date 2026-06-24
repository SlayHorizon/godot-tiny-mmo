extends DataRequestHandler
## Returns quest views. With {"giver": id} -> the quests that giver offers (with the
## player's state on each). Without it -> the player's own quests (for a quest log).


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}

	var resource: PlayerResource = player.player_resource
	var inventory: Dictionary = resource.inventory

	# Build {quest_id -> QuestResource} from the giver directly. This bypasses
	# the content registry, so newly-authored quests render correctly at their
	# giver even before the TinyMMO plugin's content index has been
	# regenerated. (Regeneration is still needed for the player's quest log
	# view, which only has IDs to work with.)
	var quest_ids: Array = []
	var resources_by_id: Dictionary = {}
	var giver_id: int = int(args.get("giver", 0))
	var giver_name: String = ""
	if giver_id > 0:
		# Opening the menu at a giver is "visiting" them — advance any matching
		# VISIT objectives BEFORE building the view so the player sees the
		# just-advanced count in the same response. Also push quest.update so
		# the HUD tracker refreshes immediately (same pattern as kill/craft).
		var visit_updates: Array = QuestService.on_visit(resource, giver_id, peer_id, instance)
		if not visit_updates.is_empty():
			WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": visit_updates})
		var giver: Object = instance.instance_map.get_quest_giver(giver_id)
		if giver:
			giver_name = str(giver.get(&"giver_name"))
			for quest: QuestResource in giver.get(&"quests"):
				if quest:
					var qid: int = int(quest.get_meta(&"id", 0))
					resources_by_id[qid] = quest
					quest_ids.append(qid)
			# Pending turn-ins: active quests whose turn_in_giver_id points at
			# this giver (delivery quests).
			for active_quest_id: int in resource.quests.keys():
				if quest_ids.has(active_quest_id):
					continue
				if resource.quest_state(active_quest_id) != &"active":
					continue
				var quest: QuestResource = QuestResource.load_quest(active_quest_id)
				if quest and quest.turn_in_giver_id == giver_id:
					resources_by_id[active_quest_id] = quest
					quest_ids.append(active_quest_id)
	else:
		quest_ids = resource.quests.keys()

	var out: Array = []
	for quest_id: int in quest_ids:
		out.append(_quest_view(resource, int(quest_id), resources_by_id.get(quest_id), inventory))

	# Toast any quest that just became turn-in-able via a passive COLLECT fill
	# (inventory changes fire no advance event). Latches so it only toasts once.
	QuestService.notify_passive_ready(resource, peer_id)
	return {"giver": giver_id, "giver_name": giver_name, "quests": out}


func _quest_view(resource: PlayerResource, quest_id: int, quest_ref: QuestResource, inventory: Dictionary) -> Dictionary:
	# Prefer the direct reference (from the giver) over the registry lookup —
	# avoids "?" names when the content index is stale.
	var quest: QuestResource = quest_ref if quest_ref != null else QuestResource.load_quest(quest_id)
	if quest == null:
		return {"id": quest_id, "name": "?", "objectives": []}

	# A turned-in quest is locked done — for COLLECT, don't recompute the count from
	# live inventory (items were consumed at turn-in), which would otherwise read e.g.
	# "8/10" after the player spends the leftover stack. Show every objective met.
	var turned_in: bool = resource.quest_state(quest_id) == &"turned_in"

	var objectives: Array = []
	for i: int in quest.objectives.size():
		var objective: QuestObjective = quest.objectives[i]
		objectives.append({
			"desc": objective.describe(),
			"count": objective.required_amount if turned_in else QuestService.objective_count(resource, quest_id, i, objective, inventory),
			"required": objective.required_amount,
			# VISIT objectives are single-fire; the "(0/1)" counter reads clumsily,
			# so the client hides it on non-countable (VISIT) rows.
			"countable": objective.type != QuestObjective.Type.VISIT,
		})

	return {
		"id": quest_id,
		"name": quest.quest_name,
		"description": quest.description,
		"state": String(resource.quest_state(quest_id)), # "" / "active" / "turned_in"
		"complete": turned_in or QuestService.is_complete(resource, quest_id, inventory),
		"objectives": objectives,
		"reward_xp": quest.reward_xp,
		"reward_gold": quest.reward_gold,
		# Level-gate info so the client can swap the Accept button for a
		# "Requires level N" label on quests the player isn't ready for.
		"min_level": quest.min_level,
		"meets_level": resource.level >= quest.min_level,
		# 0 = ALL objectives required, 1 = ANY single objective is enough. Lets
		# the client tweak the objective list label ("Speak with any of these…").
		"completion": int(quest.completion),
	}
