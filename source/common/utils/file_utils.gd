class_name FileUtils


static func get_all_file_at(
	path: String,
	pattern: String = "*",
	recursive: bool = true
) -> PackedStringArray:
	var result_files: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(path)
	
	if not dir:
		push_error("Failed to open directory at %s with error %s" % [
			path, error_string(DirAccess.get_open_error())
		])
		return result_files
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name:
		var full_path: String = path.path_join(file_name)
		if dir.current_is_dir() and recursive:
			result_files += get_all_file_at(full_path)
		elif file_name.match(pattern):
			result_files.append(full_path)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return result_files
