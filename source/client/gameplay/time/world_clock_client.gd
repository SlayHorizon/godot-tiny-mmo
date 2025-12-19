class_name WorldClockClient
extends WorldClock


func _ready() -> void:
	get_parent().connection_changed.connect(_on_client_connected)


func _process(delta: float) -> void:
	if not enabled: return
	total_elapsed_time += delta
	total_elapsed_time = fmod(total_elapsed_time, day_speed)


func _on_client_connected(is_connected_to_server: bool) -> void:
	if is_connected_to_server:
		sync_time_with_server()


func sync_time_with_server() -> void:
	var sent_time: int = Time.get_ticks_msec()
	var request_result: Array = await DataSynchronizerClient._self.request_data_await(&"get.server_time")
	if request_result[1] != OK: return

	var data: Dictionary = request_result[0]
	var receive_time: int = Time.get_ticks_msec()
	var latency: float = (receive_time - sent_time) / 2.0

	total_elapsed_time = (latency / 1000) + data["server_elapsed_time"]
	day_speed = data["server_day_speed"]
	enabled = data["server_time_enabled"]