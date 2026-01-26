class_name CmdlineUtils


static func get_parsed_args() -> Dictionary:
	var arguments: Dictionary = {}
	for argument: String in OS.get_cmdline_args():
		if argument.contains("="):
			var key_value := argument.split("=")
			arguments[key_value[0].trim_prefix("--")] = key_value[1]
		else:
			# Options without an argument will be present in the dictionary,
			# with the value set to an empty string.
			arguments[argument.trim_prefix("--")] = ""
	return arguments
