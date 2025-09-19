class_name FileUtils


static func get_all_file_at(path: String) -> PackedStringArray:
	var result_files := PackedStringArray()
	var dir := DirAccess.open(path)
	
	if not dir:
		push_error("Failed to open directory: " + path)
		return result_files
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name:
		if file_name.ends_with(".remap"):
			file_name = file_name.trim_suffix(".remap")
		var file_path = path + "/" + file_name
		if dir.current_is_dir():
			result_files += get_all_file_at(file_path)
		else:
			result_files.append(file_path)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return result_files
