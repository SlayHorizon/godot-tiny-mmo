extends ChatCommand


func execute(_args: PackedStringArray, _peer_id: int, server_instance: ServerInstance) -> String:
	var command_list:Array = server_instance.chat_commands.keys()
	var parsed_list: String = "\n".join(command_list)
	if not server_instance.local_chat_commands.is_empty():
		parsed_list += "\n".join(server_instance.local_chat_commands.keys())
	return parsed_list
