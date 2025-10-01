class_name FileUtils


const IGNORED_EXTENSIONS: Array = [
	".remap",
	".uid"
]


static func get_all_file_at(path: String) -> PackedStringArray:
	var result_files := PackedStringArray()
	var dir := DirAccess.open(path)
	
	if not dir:
		push_error("Failed to open directory: " + path)
		return result_files
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name:
		file_name = replace_ignored_extensions(file_name)

		var file_path = path + "/" + file_name
		if dir.current_is_dir():
			result_files += get_all_file_at(file_path)
		elif not result_files.has(file_path): # prevent duplications
			result_files.append(file_path)
		
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return result_files


static func replace_ignored_extensions(file_name: String) -> String:
	var new_file_name: String = file_name
	for extension in IGNORED_EXTENSIONS:
		new_file_name = file_name.trim_suffix(extension)

	return new_file_name