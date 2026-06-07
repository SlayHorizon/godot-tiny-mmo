extends ChatCommand
## Grant a vanity title to a player and auto-equip it if they have none shown.
## Seeds test data for the profile Title selector without completing a quest.


func _init() -> void:
	command_name = "title"
	command_priority = 100 # senior_admin
	command_usage = "/title <self|@account|#id> <name>   (quote multi-word: \"Iron Warden\")"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	# Allow quoted multi-word titles spanning args[2..]: /title @x "Iron Warden".
	var title: String = args[2]
	if title.begins_with("\""):
		var pieces: PackedStringArray = [title.trim_prefix("\"")]
		for i in range(3, args.size()):
			if args[i].ends_with("\""):
				pieces.append(args[i].trim_suffix("\""))
				break
			pieces.append(args[i])
		title = " ".join(pieces)
	if title.is_empty():
		return "Title can't be empty."

	var res: PlayerResource = target.resource
	if not res.titles_unlocked.has(title):
		res.titles_unlocked.append(title)
	# Auto-equip if the player has no banner set, so a fresh test character sees
	# the new title immediately without opening the editor.
	var auto_equipped: bool = false
	if res.display_title.is_empty():
		res.display_title = title
		auto_equipped = true

	return "Granted title '%s' to %s%s." % [
		title, target.label(), " (now displayed)" if auto_equipped else ""
	]
