extends ChatCommand


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var command_list:Array = server_instance.chat_commands.keys()
	var parsed_list: Array[String]
	var list: String
	for command in command_list:
		if not list:
			list += str(command)
		else:
			list += "\n" + str(command)
	return str(list)
