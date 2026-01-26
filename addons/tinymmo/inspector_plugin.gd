extends EditorInspectorPlugin


var property_editor: GDScript = preload("property_editor.gd")


func _can_handle(object: Object):
	return true


func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	if type == TYPE_DICTIONARY:
		#printt(object, type, name, hint_type, hint_string, usage_flags, wide)
		var dict: Dictionary = EditorInterface.get_inspector().get_edited_object()[name]
		if dict.get_typed_key_builtin() == TYPE_NODE_PATH:
			add_property_editor(name, property_editor.new(), true)
			return false
	return false
