class_name DataRequest
extends RefCounted


enum Error {
	OK,
	TIMEOUT,
	CANCELLED
}

signal finished(result: Dictionary, error: Error)

var request_id: int
var callable: Callable

var _completed: bool = false
var _timer: SceneTreeTimer


func start_timeout(seconds: float = 5.0) -> void:
	if seconds <= 0: return

	_timer = Engine.get_main_loop().create_timer(seconds)
	_timer.timeout.connect(_on_timer_timeout)


func _on_timer_timeout() -> void:
	if _completed: return
	_completed = true

	DataSynchronizerClient.cancel_request_data(request_id)
	finished.emit({}, Error.TIMEOUT)


func finish(data: Dictionary) -> void:
	if _completed: return
	_completed = true
	
	if _timer and _timer.timeout.is_connected(_on_timer_timeout):
		_timer.timeout.disconnect(_on_timer_timeout)

	finished.emit(data, Error.OK)


func cancel() -> void:
	if _completed: return
	_completed = true
	
	if _timer and _timer.timeout.is_connected(_on_timer_timeout):
		_timer.timeout.disconnect(_on_timer_timeout)

	DataSynchronizerClient.cancel_request_data(request_id)
	finished.emit({}, Error.CANCELLED)
