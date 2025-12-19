class_name DataSynchronizerClient
extends Node


@export var instance_manager: InstanceManagerClient

static var _next_data_request_id: int = 0
static var _pending_data_requests: Dictionary[int, DataRequest]
static var _data_subscriptions: Dictionary[StringName, Array]
static var _self: DataSynchronizerClient


func _ready() -> void:
	_self = self


static func subscribe(type: StringName, callable: Callable) -> void:
	if _data_subscriptions.has(type) and not _data_subscriptions[type].has(callable):
		_data_subscriptions[type].append(callable)
	elif not _data_subscriptions.has(type):
		_data_subscriptions[type] = [callable]


static func unsubscribe(type: StringName, callable: Callable) -> void:
	if not _data_subscriptions.has(type): return
	_data_subscriptions[type].erase(callable)


static func cancel_request_data(request_id: int) -> bool:
	return _pending_data_requests.erase(request_id)


## Returns a array containing [Dictionary, DataRequest.Error]
func request_data_await(
	type: StringName,
	args: Dictionary = {},
	instance_id: String = ""
) -> Array:
	var request: DataRequest = request_data(type, Callable(), args, instance_id)
	var result = await request.finished

	return result


func request_data(
	type: StringName,
	callable: Callable,
	args: Dictionary = {},
	instance_id: String = ""
) -> DataRequest:
	var request: DataRequest = DataRequest.new()
	var request_id = _next_data_request_id
	_next_data_request_id += 1

	request.request_id = request_id
	request.callable = callable
	_pending_data_requests[request_id] = request

	_data_request.rpc_id(1,
		request_id,
		type,
		args,
		instance_id
	)

	request.start_timeout(5.0)
	return request


@rpc("any_peer", "call_remote", "reliable", 1)
func _data_request(request_id: int, type: String, args: Dictionary, instance_id: String) -> void:
	# Server side
	pass


@rpc("authority", "call_remote", "reliable", 1)
func _data_response(request_id: int, type: String, data: Dictionary) -> void:
	if not _pending_data_requests.has(request_id): return
	
	var request: DataRequest = _pending_data_requests[request_id]
	_pending_data_requests.erase(request_id)

	if request.callable.is_valid():
		request.callable.call(data)
	request.finish(data)
	data_push(type, data)


@rpc("authority", "call_remote", "reliable", 1)
func data_push(type: String, data: Dictionary) -> void:
	for callable: Callable in _data_subscriptions.get(type, []):
		if callable.is_valid():
			callable.call(data)
		else:
			unsubscribe(type, callable)
