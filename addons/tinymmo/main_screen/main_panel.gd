@tool
extends Control


const INDEX_DIR: String = "res://source/common/registry/indexes/"

var file_dialog: EditorFileDialog
var last_dir: String
var last_dir_selected: String = "res://source/common/"

var current_content_index: ContentIndex

@onready var label: Label = $VBoxContainer/Label
@onready var update_button: Button = $VBoxContainer/UpdateButton
@onready var preview_button: Button = $VBoxContainer/PreviewButton
@onready var output_view: CodeEdit = $VBoxContainer/CodeEdit


func _ready() -> void:
	output_view.syntax_highlighter = GDScriptSyntaxHighlighter.new()
	output_view.draw_tabs = true
	output_view.text = "## Hello it's horizon, just to say you can edit / select there like in editor.\n## It supports GDScript Highlighter."


#region preview
func _on_preview_button_pressed() -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.tres", "A ContentIndex resource.")
	if last_dir:
		file_dialog.current_dir = last_dir
	else:
		file_dialog.current_dir = INDEX_DIR
	file_dialog.file_selected.connect(_on_preview_file_dialog_file_selected)
	file_dialog.canceled.connect(_on_preview_file_dialog_canceled)
	add_child(file_dialog)
	file_dialog.popup_file_dialog()


func _on_preview_file_dialog_file_selected(path: String) -> void:
	print_plugin("Selected path: %s" % path)
	
	if file_dialog:
		file_dialog.queue_free()
	
	var resource: ContentIndex = ResourceLoader.load(path) as ContentIndex
	if not resource:
		label.text = "Invalid resource, select a ContentIndex generated one."
		print_plugin( "Invalid resource, select a ContentIndex generated one.")
		return
	
	output_view.clear()
	current_content_index = resource
	
	output_view.text += "## Content Name: %s\n" % current_content_index.content_name
	output_view.text += "## Entries size: %d\n" % current_content_index.entries.size()
	
	var dictionary_as_string: String
	
	# Sort IDs in ascending order.
	current_content_index.entries.sort_custom(func(a, b): return b[&"id"] > a[&"id"])
	
	for entry: Dictionary in current_content_index.entries:
		if not entry.has_all([&"slug", &"id", &"path"]):
			continue
		dictionary_as_string = "{\n"
		var keys: Array[StringName]
		keys.assign(entry.keys())
		keys.reverse()
		for key: StringName in keys:
			dictionary_as_string += "\t" + format_str(key) + ": %s" % format_str(entry[key])
			dictionary_as_string += "\n"
		dictionary_as_string += "}"
		output_view.text += dictionary_as_string + "\n"
		
		dictionary_as_string = ""
	
	label.text = "Current selected content index: %s" % path
	print_plugin("ContentIndex preview generated.")

	last_dir = path.get_base_dir()


func _on_preview_file_dialog_canceled() -> void:
	file_dialog.queue_free()
#endregion


func print_plugin(to_print: String) -> void:
	print_rich(
		"[color=yellow]TinyMMO plugin - [/color]",
		to_print
	)


func format_str(str: Variant) -> String:
	if str is StringName:
		return "&\"%s\"" % str
	elif str is String:
		return "\"%s\"" % str
	return str(str)


#region generate
func _on_generate_button_pressed() -> void:
	const GENERATE_DIALOG = preload("res://addons/tinymmo/main_screen/generate_dialog.tscn")
	
	var generate_dialog: ConfirmationDialog = GENERATE_DIALOG.instantiate()
	generate_dialog.canceled.connect(generate_dialog.queue_free)
	generate_dialog.confirmed.connect(_on_generate_dialog_confirmed.bind(generate_dialog))
	
	EditorInterface.popup_dialog_centered(generate_dialog)


func _on_generate_dialog_confirmed(generate_dialog: ConfirmationDialog) -> void:
	var path: String = generate_dialog.path_edit.text
	var filters: PackedStringArray
	var content_name: String = generate_dialog.content_name_edit.text
	if generate_dialog.filters_edit.text.is_empty():
		filters = ["*.tres", "*.tscn"]
	else:
		filters = generate_dialog.filters_edit.text.split(", ")
	print_debug(filters)
	
	generate_dialog.queue_free()
	
	if path.is_empty() or content_name.is_empty():
		print_plugin("Failed to generate, invalid parameters")
		return
	
	generate_content_index(content_name, path, filters)


func generate_content_index(
	content_name: String,
	path: String,
	filters: PackedStringArray
) -> void:
	var content_index: ContentIndex
	var content_index_path: String = INDEX_DIR + content_name + "_index.tres"
	var resource_paths: PackedStringArray = get_resource_file_paths(path, filters)
	
	if ResourceLoader.exists(content_index_path):
		content_index = ResourceLoader.load(content_index_path)
	else:
		content_index = ContentIndex.new()
	content_index.content_name = content_name
	content_index.version = int(Time.get_unix_time_from_system())
	
	var entries: Array[Dictionary]
	for resource_path: String in resource_paths:
		var resource: Resource = ResourceLoader.load(resource_path)
		if not resource:
			continue
		
		var slug: StringName = resource_path.get_file().get_basename()
		var id: int = get_slug_id(content_index, slug)
		
		resource.set_meta(&"slug", slug)
		resource.set_meta(&"id", id)
		ResourceSaver.save(resource, resource_path)
		
		entries.append({
			&"id": id,
			&"slug": slug,
			&"path": resource_path,
			&"hash": FileAccess.get_sha256(resource_path)
		})
		if id == content_index.next_id:
			content_index.next_id += 1
	
	content_index.entries = entries
	
	var error: Error = ResourceSaver.save(content_index, content_index_path)
	if error:
		printerr(error_string(error))
	else:
		var accept_dialog: AcceptDialog = AcceptDialog.new()
		accept_dialog.canceled.connect(accept_dialog.queue_free)
		accept_dialog.confirmed.connect(func():
			accept_dialog.queue_free()
			_on_preview_file_dialog_file_selected(content_index_path)
			)
		accept_dialog.dialog_text = "Content index: %s generated at %s\nWant to preview it ?" % [content_name, content_index_path]
		EditorInterface.popup_dialog_centered(accept_dialog)
#endregion


func get_resource_file_paths(
	path: String,
	filters: PackedStringArray
) -> PackedStringArray:
	var dir := DirAccess.open(path)
	if not dir:
		printerr(error_string(DirAccess.get_open_error()))
	var file_paths := PackedStringArray()
	dir.list_dir_begin()
	var file_path: String = dir.get_next()
	
	while file_path:
		if dir.current_is_dir():
			file_paths.append_array(get_resource_file_paths(path + "/" + file_path, filters))
		else:
			var full_path: String = path + "/" + file_path
			for filter: String in filters:
				if full_path.match(filter):
					file_paths.append(full_path)
					break
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


func _on_clear_button_pressed() -> void:
	output_view.clear()
	output_view.text = "## Just to say you can edit / select there like in editor.\n## It supports GDScript Highlighter."


#region update
func _on_update_button_pressed() -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.tres", "A ContentIndex resource.")
	
	file_dialog.current_dir = INDEX_DIR
	
	file_dialog.file_selected.connect(_on_update_file_dialog_file_selected)
	file_dialog.canceled.connect(_on_update_file_dialog_canceled)
	
	add_child(file_dialog)
	file_dialog.popup_file_dialog()


func _on_update_file_dialog_file_selected(path: String) -> void:
	var content_index: ContentIndex = ResourceLoader.load(path) as ContentIndex
	if not content_index:
		print_plugin("No ContentIndex selected.")
		return

	if content_index.scan_path.is_empty():
		print_plugin("Scan path of content index empty.")
		return
	
	print_plugin("Update content index not implemented yet.")
	#var resource_paths: PackedStringArray = get_resource_file_paths(
		#content_index.scan_path, content_index.filters
	#)
	#var entries: Array[Dictionary] = content_index.entries
	#var used_paths: PackedStringArray = entries.map(func(d): return d[&"path"])
	#
	#
	#for resource_path: String in resource_paths:
		#var resource: Resource = ResourceLoader.load(resource_path)
		#if not resource:
			#continue
		#
		#var entry_index: int = content_index.entries.find_custom(
			#func(d: Dictionary):
				#return d[&"slug"] == slug
		#)
		#
		#var slug: StringName = resource_path.get_file().get_basename()
		#var id: int = get_slug_id(content_index, slug)
		#
		#resource.set_meta(&"slug", slug)
		#resource.set_meta(&"id", id)
		#ResourceSaver.save(resource, resource_path)
		#
		#entries.append({
			#&"id": id,
			#&"slug": slug,
			#&"path": resource_path,
			#&"hash": FileAccess.get_sha256(resource_path)
		#})
		#if id == content_index.next_id:
			#content_index.next_id += 1
	#
	#content_index.entries = entries
	#
	#var error: Error = ResourceSaver.save(content_index, content_index_path)
	#if error:
		#printerr(error_string(error))
	#else:
		#var accept_dialog: AcceptDialog = AcceptDialog.new()
		#accept_dialog.canceled.connect(accept_dialog.queue_free)
		#accept_dialog.confirmed.connect(func():
			#accept_dialog.queue_free()
			#_on_file_dialog_file_selected(content_index_path)
			#)
		#accept_dialog.dialog_text = "%s generated at %s\nWant to preview it ?" % [content_name, content_index_path]
		#EditorInterface.popup_dialog_centered(accept_dialog)


func _on_update_file_dialog_canceled() -> void:
	file_dialog.queue_free()
#endregion
