class_name ConfigFileUtils


static func load_file_with_defaults(config_path: String, defaults: Dictionary) -> Dictionary:
	var config_file: ConfigFile = ConfigFile.new()
	config_file.load(config_path)
	
	var config: Dictionary = defaults.duplicate(true)

	for section: String in config_file.get_sections():
		var section_data: Dictionary = {}
		for key: String in config_file.get_section_keys(section):
			section_data[key] = config_file.get_value(section, key, defaults.get(key))

		config[section] = section_data

	return config


static func load_section(section: String, config_path: String) -> Dictionary:
	var config_file: ConfigFile = ConfigFile.new()
	var error: Error = config_file.load(config_path)
	if error != OK:
		printerr("Failed to load config at %s, error: %s" % [config_path, error_string(error)])
		return {"error": error, "config_path": config_path}
	
	var configuration: Dictionary = {}
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
	
	var configuration: Dictionary = {}
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


static func save_section_key(section: String, key: String, value: Variant, config_path: String) -> Error:
	var config_file: ConfigFile = ConfigFile.new()
	config_file.load(config_path)
	
	config_file.set_value(section, key, value)
	return config_file.save(config_path)


static func save_sections(sections: Dictionary, config_path: String) -> Error:
	var config_file: ConfigFile = ConfigFile.new()
	config_file.load(config_path)
	
	for section_name: String in sections:
		var values: Dictionary = sections[section_name]
		for key: String in values:
			config_file.set_value(section_name, key, values[key])
	
	return config_file.save(config_path)
