class_name NetworkManagerClient
extends Node

@export var instance_manager: InstanceManagerClient

static var _next_data_request_id: int = 0
static var _pending_data_requests: Dictionary[int, Callable]
static var _self: NetworkManagerClient


func _ready() -> void:
    _self = self


func request_data(
    type: StringName,
    callable: Callable,
    args: Dictionary = {},
    instance_id: String = ""
) -> int:
    print("sent on client")
    _next_data_request_id += 1
    _pending_data_requests[_next_data_request_id] = callable

    _data_request.rpc_id(
        1,
        _next_data_request_id,
        type,
        args,
        instance_id
    )

    return _next_data_request_id


@rpc("any_peer", "call_remote", "reliable", 1)
func _data_request(request_id: int, type: String, args: Dictionary, instance_id: String) -> void:
    # Server side
    pass


@rpc("authority", "call_remote", "reliable", 1)
func data_response(request_id: int, type: String, data: Dictionary) -> void:
    var callable: Callable = _pending_data_requests.get(request_id, Callable())
    _pending_data_requests.erase(request_id)
    if callable.is_valid():
        callable.call(data)