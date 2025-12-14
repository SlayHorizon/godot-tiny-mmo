class_name WorldClockClient
extends WorldClock


var _pending_time_requests: Array


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
	var request_time: int = Time.get_ticks_msec()
	_pending_time_requests.append(request_time)


	DataSynchronizerClient._self.request_data(
		&"get.server_time",
		_on_request_time_response,
		{"id": request_time}
	)


func _on_request_time_response(args: Dictionary) -> void:
	if args.is_empty(): return

	var sent_time: int = args["request_id"]
	if not sent_time in _pending_time_requests: return

	var receive_time: int = Time.get_ticks_msec()
	var ping = (receive_time - sent_time) / 2.0

	total_elapsed_time = (ping / 1000.0) + args["server_elapsed_time"]
	day_speed = args["server_day_speed"]
	enabled = args["server_time_enabled"]

	_pending_time_requests.erase(sent_time)
