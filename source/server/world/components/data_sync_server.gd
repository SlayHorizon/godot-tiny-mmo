class_name DataSynchronizerServer
extends Node


@export var instance_manager: InstanceManagerServer

static var _self: DataSynchronizerServer

var data_handlers: Dictionary[StringName, DataRequestHandler]


func _ready() -> void:
    _self = self


@rpc("any_peer", "call_remote", "reliable", 1)
func _data_request(
    request_id: int,
    type: StringName,
    args: Dictionary = {},
    instance_id: String = ""
) -> void:
    var peer_id: int = multiplayer.get_remote_sender_id()
    var instance: ServerInstance = instance_manager.get_instance_server_by_id(instance_id)

    if not instance:
        instance = instance_manager.default_instance.charged_instances[0]

    if not data_handlers.has(type):
        var script: GDScript = ContentRegistryHub.load_by_slug(
            &"data_request_handlers",
            type
        )
        if not script: return
        
        var handler = script.new() as DataRequestHandler
        if not handler: return
        data_handlers[type] = handler

    _data_response.rpc_id(
        peer_id,
        request_id,
        type,
        data_handlers[type].data_request_handler(peer_id, instance, args)
    )


@rpc("authority", "call_remote", "reliable", 1)
func _data_response(request_id: int, type: String, data: Dictionary) -> void:
    # Client only
    pass


@rpc("authority", "call_remote", "reliable", 1)
func data_push(instance_id: String, type: StringName, data: Dictionary) -> void:
    # Client only
    pass