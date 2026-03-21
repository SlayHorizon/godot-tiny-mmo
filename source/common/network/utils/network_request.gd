class_name NetRequest
extends RefCounted


signal completed(content: Dictionary)

var token_id: int
var response: Dictionary
var is_done: bool = false


func resolve(value: Dictionary) -> void:
	if is_done:
		return
	is_done = true
	response = value
	#response.merge({GatewayAPI.KEY_TOKEN_ID: token_id})
	completed.emit(response)
