extends DataRequestHandler
## Sets a category's special-ability loadout: an ORDERED array of owned
## ability-node ids (max 2 — slot POSITION maps to the Q / E inputs; "" marks
## a deliberately empty slot so a pick can sit on E with Q free). An empty
## array clears everything. Works from anywhere — the server is the
## authority, no NPC gatekeeper — EXCEPT mid-spar/duel, where swapping
## abilities would dodge the fight you signed up for.
##
## No capacity check here on purpose: a too-heavy pick is stored but inert
## (MasteryService.effective_special_ids skips it) until the player wields a
## weapon that can channel it. Storing intent beats erroring on it.

const MAX_PICKS: int = 2


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var category: StringName = StringName(str(args.get("category", "")))
	if category.is_empty():
		return {"ok": false}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var resource: PlayerResource = player.player_resource
	if resource.in_match:
		return {"ok": false, "reason": "in_match"}

	var picks_v: Variant = args.get("nodes", [])
	var picks: Array = picks_v if picks_v is Array else []
	if picks.size() > MAX_PICKS:
		return {"ok": false, "reason": "too_many"}

	var tree: MasteryTreeResource = MasteryService.tree_for(category)
	if tree == null:
		return {"ok": false, "reason": "no_tree"}
	var entry: Dictionary = resource.masteries.get(category, {})
	var spent: Dictionary = entry.get("spent", {})

	var validated: Array = []
	var seen_chains: Dictionary = {} # chain root -> true: one tier of a move max
	for pick in picks:
		var node_id: String = str(pick)
		if node_id.is_empty():
			validated.append("") # deliberate hole — keeps later picks on their key
			continue
		if validated.has(node_id):
			return {"ok": false, "reason": "duplicate"}
		var node: MasteryNode = tree.get_node_by_id(StringName(node_id))
		if node == null or node.ability == null:
			return {"ok": false, "reason": "unknown_node"}
		if not spent.has(node_id):
			return {"ok": false, "reason": "not_owned"}
		# A signature move occupies ONE slot — can't slot two tiers of it.
		var root: String = String(MasteryService.chain_root_of(tree, node))
		if seen_chains.has(root):
			return {"ok": false, "reason": "same_chain"}
		seen_chains[root] = true
		# Store the EXACT tier the player chose. They may deliberately channel a
		# lighter tier of a chain to free weapon power for another ability.
		validated.append(node_id)

	# Trailing holes carry no information — trim so "cleared everything"
	# stores as no entry at all.
	while not validated.is_empty() and str(validated[validated.size() - 1]).is_empty():
		validated.pop_back()
	if validated.is_empty():
		resource.ability_loadout.erase(String(category))
	else:
		resource.ability_loadout[String(category)] = validated
	MasteryService.refresh(player)
	return {"ok": true}
