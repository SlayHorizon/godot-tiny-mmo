extends EditorExportPlugin


func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	if features.has("client"):
		return
		
	
	var config := ConfigFile.new()
	var override_content: String = "[autoload]
	Events=null"
	add_file(
		"override.cfg",
		override_content.to_utf8_buffer(),
		true
	)
	print("Server export detected. Removing client autoload...")


func _export_end() -> void:
	pass


func _get_name() -> String:
	return "No Client Autoload"
