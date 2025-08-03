extends ChatCommand


func execute(_args: PackedStringArray, _peer_id: int, server_instance: ServerInstance) -> String:
	var command_list:Array = server_instance.chat_commands.keys()
	var parsed_list: String = ""
	for command in command_list:
		if not parsed_list:
			parsed_list += str(command)
		else:
			parsed_list += "\n" + str(command)
	return str(parsed_list)
