class_name Utils
extends Node

static  func get_all_file_at(path: String) -> Array[String]:  
	var file_paths: Array[String] = []  
	var dir := DirAccess.open(path)  
	dir.list_dir_begin()  
	var file_name: String = dir.get_next()  
	while file_name != "":
		if '.tres.remap' in file_name:
			file_name = file_name.trim_suffix('.remap')
		var file_path = path + "/" + file_name  
		if dir.current_is_dir():  
			file_paths += get_all_file_at(file_path)  
		else:  
			file_paths.append(file_path)  
		file_name = dir.get_next()  
	return file_paths
