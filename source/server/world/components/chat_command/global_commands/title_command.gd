extends ChatCommand
## Grant a vanity title to a player (testing helper). Adds the title to
## titles_unlocked and auto-equips it as display_title if the player has none
## currently shown. Use to seed test data for the profile Title selector
## without having to complete a quest that grants one.
##
## Usage:
##   /title Newcomer            # grant "Newcomer" to self
##   /title "Iron Warden" 1042  # grant "Iron Warden" to player #1042


func _init() -> void:
	command_name = "title"
	command_priority = 100 # senior_admin


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: /title <name> [player_id]"

	# Allow quoted multi-word titles: /title "Iron Warden" 1042. We splice the
	# args between the first opening quote and its closing quote into one title.
	var title: String = args[1]
	var consumed: int = 2
	if title.begins_with("\""):
		var pieces: PackedStringArray = [title.trim_prefix("\"")]
		for i in range(2, args.size()):
			if args[i].ends_with("\""):
				pieces.append(args[i].trim_suffix("\""))
				consumed = i + 1
				break
			pieces.append(args[i])
			consumed = i + 1
		title = " ".join(pieces)

	if title.is_empty():
		return "Title can't be empty."

	var ws: WorldServer = server_instance.world_server
	var target_peer_id: int = peer_id
	var target: PlayerResource = ws.connected_players.get(peer_id)
	if args.size() > consumed:
		var target_id: int = args[consumed].to_int()
		target_peer_id = ws.player_id_to_peer_id.get(target_id, 0)
		if target_peer_id == 0:
			return "No online player with id %d." % target_id
		target = ws.connected_players.get(target_peer_id)
	if target == null:
		return "Couldn't find a target player."

	if not target.titles_unlocked.has(title):
		target.titles_unlocked.append(title)
	# Auto-equip if the player has no banner set, so a fresh test character
	# sees the new title immediately without opening the editor.
	var auto_equipped: bool = false
	if target.display_title.is_empty():
		target.display_title = title
		auto_equipped = true

	return "Granted title '%s' to %s%s." % [
		title,
		target.display_name,
		" (now displayed)" if auto_equipped else "",
	]
