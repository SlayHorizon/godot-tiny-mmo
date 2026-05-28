extends ChatCommand
## Re-read the admin config file (server_admins.cfg) without restarting the server,
## so edits to the owner admin list take effect immediately.


func _init() -> void:
	command_name = "reloadadmins"
	command_priority = 100 # senior_admin


func execute(_args: PackedStringArray, _peer_id: int, _server_instance: ServerInstance) -> String:
	AdminConfig.reload()
	return "Admin config reloaded."
