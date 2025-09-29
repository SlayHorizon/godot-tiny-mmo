# No Used, for now we use ConfigFileUtils

#static func load_endpoint_configuration(section: String, default_config_path: String = "") -> Dictionary:
	#var parsed_arguments: Dictionary = CmdlineUtils.get_parsed_args()
	#
	#var config_path: String = parsed_arguments.get("config", default_config_path)
	#var config_file := ConfigFile.new()
	#var error: Error = config_file.load(config_path)
	#if error != OK:
		#printerr("Failed to load config at %s, error: %s" % [config_path, error_string(error)])
		#return {"error": error}
	#
	#var configuration: Dictionary
	#for section_key: String in config_file.get_section_keys(section):
		#configuration[section_key] = config_file.get_value(section_key, section_key)
	#
	#return configuration
