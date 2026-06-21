class_name ContentRegistry
extends RefCounted


var _id_to_path: Dictionary[int, StringName]
var _slug_to_id: Dictionary[StringName, int]
var _id_to_slug: Dictionary[int, StringName]


func _init(content_index: ContentIndex) -> void:
	load_content_index(content_index)


func load_content_index(content_index: ContentIndex) -> void:
	for entry: Dictionary in content_index.entries:
		if not entry.has_all([&"id", &"slug", &"path"]):
			continue
		var id: int = entry[&"id"]
		_id_to_path[id] = entry[&"path"]
		_slug_to_id[entry[&"slug"]] = id
		_id_to_slug[id] = entry[&"slug"]


func id_from_slug(slug: StringName) -> int:
	return _slug_to_id.get(slug, 0)


## Every content id in this registry (unordered — sort at the call site if needed).
func all_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _id_to_path:
		out.append(id)
	return out


## Slug for an id (&"" if unknown) — the inverse of id_from_slug, for display names.
func slug_from_id(id: int) -> StringName:
	return _id_to_slug.get(id, &"")


func path_from_id(id: int) -> StringName:
	return _id_to_path.get(id, &"")


func path_from_slug(slug: StringName) -> StringName:
	return path_from_id(id_from_slug(slug))


func has_id(id: int) -> bool:
	return _id_to_path.has(id)


func has_slug(slug: StringName) -> bool:
	return _slug_to_id.has(slug)
