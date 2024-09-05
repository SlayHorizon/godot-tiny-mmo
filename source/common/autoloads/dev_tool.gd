## MADE BY @d-Cadrius contributor.
##
##
extends Node

static var dev_menu_instance : CanvasLayer

@onready var dev_menu : PackedScene = preload("res://source/client/ui/hud/dev_hud.tscn")

var place_holder_message : Label
var msg_container : VBoxContainer
var cmd_box : LineEdit

func _get_args(param : String) -> Array:
	var args : = []
	while param.length() > 0:
		var id : int = param.find(" ")
		if id != -1:
			var isarg : String = param.left(id)
			args.append(isarg)
			param = param.erase(0, isarg.length() + 1)
		else:
			args.append(param)
			param = param.erase(0, param.length() + 1)
			
	return args

func _apply_cmd(cmd : String) -> void:
	_send_messages(cmd)
	
	var id : int = cmd.find(" ")
	if id != -1:
		var iscmd : String = cmd.left(id)
		if cmds.has(iscmd):
			filter_cmd.rpc_id(1, iscmd, _get_args(cmd.erase(0, iscmd.length() + 1)))
			#cmds[iscmd].call( cmd.erase(0, iscmd.length() + 1) )
		
	cmd_box.text = ""

func is_client() -> bool:
	return OS.has_feature("client")
	
func _ready() -> void:
	var new_menu = dev_menu.instantiate()
	add_child(new_menu)

	dev_menu_instance = new_menu
	
	place_holder_message = new_menu.get_node("placeholdermsg")
	msg_container = new_menu.get_node("DevHud/VBoxContainer")
	cmd_box = new_menu.get_node("DevHud/LineEdit")
	cmd_box.text_submitted.connect(_apply_cmd)

var messages := []
func _send_messages(msg : String = "") -> void:
	var new_msg : Label = place_holder_message.duplicate()
	new_msg.text = msg
	new_msg.visible = true
	
	messages.append(new_msg)
	msg_container.add_child(new_msg)
	
	if messages.size() > 13:
		messages[0].queue_free()
		messages.remove_at(0)

var key_debounce : bool = false
func _process(_delta : float) -> void:
	if cmd_box.has_focus():
		return
		
	if Input.is_key_pressed(KEY_0) and not key_debounce:
		dev_menu_instance.visible = !dev_menu_instance.visible 
		key_debounce = true
		
	if not Input.is_key_pressed(KEY_0):
		key_debounce = false
		
func get_main() -> Node:
	return get_tree().root.get_node("InstanceManager")

func get_plr(peer_id) -> Player:
	for ins in get_main().get_children():
		for plr in ins.get_children():
			if plr is CharacterBody2D:
				if plr.name == str(peer_id):
					return plr
					
	return null
	
func get_instance_by_plr(peer_id) -> Player:
	for ins in get_main().get_children():
		for plr in ins.get_children():
			if plr is CharacterBody2D:
				if plr.name == str(peer_id):
					return ins
					
	return null

var cmds : Dictionary = {
	"tp" : func(param : Array, info : Dictionary):
		if not info[1] or not info[2]:
			return
		info[2].update_entity(info[1], {"position": Vector2(float(param[0]), float(param[1]))})
		pass,
	"warp" : func(param : Array, info : Dictionary):
		if not info[1] or not info[2]:
			return
		
		var target_instance: InstanceResource = get_main().get_instance_resource_from_name(param[0])
		info[2].despawn_player(info[0])
		get_main().charge_new_instance.rpc_id(info[0], {
			"instance_name": target_instance.instance_name,
			"map_path": target_instance.map.resource_path
		})
		pass;
}

@rpc("any_peer", "call_remote", "reliable", 1)
func filter_cmd(cmd : String, args : Array) -> void:
	if is_client():
		return
		
	var peer_id := multiplayer.get_remote_sender_id()
	# add checks here for admin only
	cmds[cmd].call(args, {
			0 : peer_id, 
			1 : get_plr(peer_id), 
			2 : get_instance_by_plr(peer_id)
		})
