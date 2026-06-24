extends ChatCommand
## GM mailbox sender (docs/mailbox.md). Thin wrapper over MailSender — pipe-splits
## the chat line into target | subject | body | extras, then delegates. For
## LONG-FORM mail (patch notes etc.) use the in-game compose menu instead; chat
## caps message length.
##
## /mail <target> | <subject> | <body> [| <attachments>]
##   target:      #<id> (online/offline) · @account (online) · self · all · online
##   attachments: comma-separated  gold:100, item:1x3, skin:24, title:Ember Founder, xp:500, from:Sender


func _init() -> void:
	command_name = "mail"
	command_priority = 100 # senior_admin — can grant rewards (matches /give, /gold, /grant)
	command_usage = "/mail <#id|@acc|self|all|online> | <subject> | <body> [| gold:100, item:1x3, skin:24, title:Name, xp:500, from:Sender]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	# Chat splits the message on spaces, so rebuild the remainder and split on '|'.
	var parts: PackedStringArray = " ".join(args.slice(1)).split("|")
	if parts.size() < 3:
		return "Usage: " + command_usage
	var extras: String = parts[3].strip_edges() if parts.size() >= 4 else ""
	var result: Dictionary = MailSender.compose(
		parts[0].strip_edges(), parts[1].strip_edges(), parts[2].strip_edges(),
		extras, peer_id, server_instance
	)
	return str(result.get("message", "Done."))
