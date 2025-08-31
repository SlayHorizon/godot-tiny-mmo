## res://tools/build_content_index.gd
@tool
#class_name ContentIndexBuilder
extends EditorScript


func _run() -> void:
	var content_name: StringName = &"combat"
	var content_dir: String = "res://source/common/combat"
	var paths: PackedStringArray = get_resource_file_paths(content_dir)
	
	var content_index: ContentIndex
	if ResourceLoader.exists("res://source/common/registry/" + content_name + "_registry.tres"):
		content_index = ResourceLoader.load("res://source/common/registry/" + content_name + "_registry.tres")
	else:
		content_index = ContentIndex.new()
		content_index.content_name = content_name
	content_index.version = int(Time.get_unix_time_from_system())
	var id: int = content_index.next_id
	var entries: Array[Dictionary]
	for path: String in paths:
		var slug: StringName = path.get_file().get_basename()
		id = get_slug_id(content_index, slug)
		print(id)
		entries.append({
			&"id": id,
			&"slug": slug,
			&"path": path,
			&"hash": FileAccess.get_sha256(path)
		})
		if id == content_index.next_id:
			content_index.next_id += 1

	content_index.entries = entries
	print(content_index.entries)
	ResourceSaver.save(content_index, "res://source/common/registry/" + content_name + "_registry.tres")

func get_resource_file_paths(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path)
	var file_paths := PackedStringArray()
	dir.list_dir_begin()
	var file_path: String = dir.get_next()
	
	while file_path:
		if dir.current_is_dir():
			file_paths.append_array(get_resource_file_paths(path + "/" + file_path))
		else:
			if file_path.ends_with(".tres") or file_path.ends_with(".tscn"):
				file_paths.append(path + "/" + file_path)
		file_path = dir.get_next()
	
	dir.list_dir_end()
	return file_paths


func get_slug_id(content_index: ContentIndex, slug: StringName) -> int:
	var entry: Dictionary
	var entry_index: int = content_index.entries.find_custom(
		func(d: Dictionary):
			return d[&"slug"] == slug
	)
	if entry_index == -1:
		return content_index.next_id
	else:
		return content_index.entries[entry_index][&"id"]
