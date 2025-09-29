class_name ConfigFileUtils


static func load_section(section: String, config_path: String) -> Dictionary:
	var config_file: ConfigFile = ConfigFile.new()
	var error: Error = config_file.load(config_path)
	if error != OK:
		printerr("Failed to load config at %s, error: %s" % [config_path, error_string(error)])
		return {"error": error, "config_path": config_path}
	
	var configuration: Dictionary
	for key: String in config_file.get_section_keys(section):
		configuration[key] = config_file.get_value(section, key)
	
	return configuration


static func load_section_safe(section: String, config_path: String, required: PackedStringArray) -> Dictionary:
	var config_file: ConfigFile = ConfigFile.new()
	var error: Error = config_file.load(config_path)
	if error != OK:
		printerr("Failed to load config at %s, error: %s" % [config_path, error_string(error)])
		return {"error": error, "config_path": config_path}
	
	assert(config_file.has_section(section))
	
	var configuration: Dictionary
	for key: String in config_file.get_section_keys(section):
		configuration[key] = config_file.get_value(section, key)
	
	
	for r: String in required:
		assert(configuration.has(r), "Missing required key '%s' in section [%s]" % [r, section])
	
	return configuration


static func load_section_with_defaults(section: String, config_path: String, defaults: Dictionary) -> Dictionary:
	var config_file: ConfigFile = ConfigFile.new()
	var error: Error = config_file.load(config_path)
	if error != OK:
		printerr("Failed to load config at %s, error: %s" % [config_path, error_string(error)])
		return {"error": error, "config_path": config_path}
	
	assert(config_file.has_section(section))
	
	var configuration: Dictionary = defaults.duplicate(true)
	
	for key: String in config_file.get_section_keys(section):
		configuration[key] = config_file.get_value(section, key, defaults.get(key))

	return configuration
