extends Node


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Master Server")


## Best-effort "offline" ping. WM_CLOSE_REQUEST fires on a graceful window
## close; headless / kill -9 won't trigger it. The HTTPRequest is async, so
## we await briefly before letting the process exit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		DiscordNotifier.notify_master_offline()
		await get_tree().create_timer(0.5).timeout
		get_tree().quit()
