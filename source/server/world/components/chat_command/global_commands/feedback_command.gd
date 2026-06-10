extends ChatCommand
## Lets any player send a bug report or suggestion straight from chat, without
## leaving the game. The message is logged server-side (tagged [FEEDBACK] for an
## easy grep) and, if a Discord webhook is configured, posted there too — so the
## alpha's reports collect in one inbox. Rate-limited to curb spam/flooding.
##
## Context is auto-attached (who/where/version) so a report is actionable even
## when the player only types "the flag is broken".


## Longer messages are truncated (Discord-friendly + anti-abuse).
const MAX_LEN: int = 500
## Anti-flood: at most MAX_PER_WINDOW well-formed reports per WINDOW_MS, per peer.
const MAX_PER_WINDOW: int = 3
const WINDOW_MS: int = 60_000
## Shown in the reply so players know where to send screenshots/clips (chat can't
## carry attachments). Hardcoded on purpose — no config lookup.
const DISCORD_INVITE: String = "https://discord.gg/QE5JwpFzgK"


func _init() -> void:
	command_name = "feedback"
	command_alias = ["bug", "report"]
	command_priority = 0 # everyone
	command_usage = "/feedback <your message>   (bug report or suggestion — context is attached automatically)"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2:
		return "Usage: " + command_usage

	var message: String = " ".join(args.slice(1)).strip_edges()
	if message.is_empty():
		return "Usage: " + command_usage
	var truncated: bool = message.length() > MAX_LEN
	if truncated:
		message = message.substr(0, MAX_LEN).strip_edges()

	# Rate-limit only well-formed reports, so a malformed call doesn't burn budget.
	if not RateLimiter.check(peer_id, &"chat.feedback", MAX_PER_WINDOW, WINDOW_MS):
		return "You're sending feedback very fast — give it a moment, then try again. Thanks!"

	var ws: WorldServer = server_instance.world_server
	var player: PlayerResource = ws.connected_players.get(peer_id)
	var who: String = player.display_name if player != null else "unknown"
	# Account names are prefixed "@" project-wide to distinguish them from
	# display/character names.
	var account: String = ("@" + player.account_name) if player != null else "@?"
	var char_id: int = player.player_id if player != null else 0

	# Where are they? instance/map + position — handy context for bug reports.
	var instance_name: String = "?"
	var position: String = "?"
	var inst: ServerInstance = ws.instance_manager.find_instance_for_peer(peer_id)
	if inst != null:
		instance_name = inst.instance_resource.instance_name
		var p: Player = inst.get_player(peer_id)
		if p != null:
			position = "(%d, %d)" % [int(p.global_position.x), int(p.global_position.y)]

	var version: String = GatewayAPI.game_version()

	# Server log — one compact line for an easy grep.
	ServerLog.info("[FEEDBACK] %s (%s, char #%d) v%s @ %s %s: %s" % [
		who, account, char_id, version, instance_name, position, message
	])

	# Discord — fire-and-forget; silently no-ops if this process has no webhook.
	# Labeled metadata, then the message in a blockquote so it visually stands
	# apart from the context. "…(truncated)" flags a clipped report.
	var trunc_note: String = "  …*(truncated)*" if truncated else ""
	DiscordNotifier.notify(
		"📝 Player feedback",
		"**Player:** %s  (%s · #%d)\n**Version:** v%s\n**Instance:** %s\n**Position:** %s\n\n> %s%s" % [
			who, account, char_id, version, instance_name, position, message, trunc_note
		],
		DiscordNotifier.COLOR_INFO
	)

	var reply: String = "Thanks! Your feedback was sent to the devs. 🙏\nGot a screenshot or clip? Share it on Discord: %s" % DISCORD_INVITE
	if truncated:
		reply += "\nNote: your message was long, so only the first %d characters were sent." % MAX_LEN
	return reply
