class_name SceneRegistry
extends Node

static var _id_to_path: Dictionary[int, String] = {}
static var _path_to_id: Dictionary[String, int] = {}
static var _next_id: int = 1
static var _version: int = 1

static func register_scene(path: String) -> int:
	var id: int = _path_to_id.get(path, 0)
	if id != 0:
		return id
	id = _next_id; _next_id += 1
	_path_to_id[path] = id
	_id_to_path[id] = path
	_version += 1
	return id

static func id_of(path: String) -> int:
	return _path_to_id.get(path, 0)

static func path_of(id: int) -> String:
	return _id_to_path.get(id, "")
