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


func _on_preview_button_pressed() -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.tres", "A ContentIndex resource.")
	if last_dir:
		file_dialog.current_dir = last_dir
	file_dialog.file_selected.connect(_on_file_dialog_file_selected)
	file_dialog.canceled.connect(_on_file_dialog_canceled)
	add_child(file_dialog)
	file_dialog.popup_file_dialog()


func _on_file_dialog_file_selected(path: String) -> void:
	print_plugin("Selected path: %s" % path)
	var resource: Resource = ResourceLoader.load(path)
	if resource and resource is ContentIndex:
		output_view.clear()
		current_content_index = resource
		
		output_view.text += "## Content Name: %s\n" % current_content_index.content_name
		output_view.text += "## Entries size: %d\n" % current_content_index.entries.size()
		
		var dictionary_as_string: String
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
	else:
		label.text = "Invalid resource, select a ContentIndex generated one."
		print_plugin( "Invalid resource, select a ContentIndex generated one.")
	last_dir = path.get_base_dir()
	if file_dialog:
		file_dialog.queue_free()


func _on_file_dialog_canceled() -> void:
	file_dialog.queue_free()


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


func _on_generate_button_pressed() -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	#file_dialog.add_filter("*.tres", "A ContentIndex resource.")
	if last_dir_selected:
		file_dialog.current_dir = last_dir_selected
	file_dialog.dir_selected.connect(_on_file_dialog_dir_selected)
	file_dialog.canceled.connect(_on_file_dialog_canceled)
	add_child(file_dialog)
	file_dialog.popup_file_dialog()



func _on_file_dialog_dir_selected(dir: String) -> void:
	var content_name: StringName = dir.trim_prefix("res://")
	content_name = content_name.get_slice("/", content_name.get_slice_count("/") - 1)
	print_plugin("Selected dir: %s" % dir)
	print_plugin("Start generation of content name: %s" % content_name)
	if content_name.is_empty() or not dir.is_absolute_path():
		return
	file_dialog.queue_free()
	last_dir_selected = dir
	var resource_paths: PackedStringArray = get_resource_file_paths(dir)
	
	var content_index: ContentIndex
	var content_index_path: String = INDEX_DIR + content_name + "_index.tres"
	if ResourceLoader.exists(content_index_path):
		content_index = ResourceLoader.load(content_index_path)
	else:
		content_index = ContentIndex.new()
	content_index.content_name = content_name
	content_index.version = int(Time.get_unix_time_from_system())
	
	var entries: Array[Dictionary]
	for resource_path: String in resource_paths:
		var slug: StringName = resource_path.get_file().get_basename()
		var id: int = get_slug_id(content_index, slug)
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
			_on_file_dialog_file_selected(content_index_path)
			)
		accept_dialog.dialog_text = "%s generated at %s\nWant to preview it ?" % [content_name, content_index_path]
		EditorInterface.popup_dialog_centered(accept_dialog)


func get_resource_file_paths(path: String) -> PackedStringArray:
	var dir := DirAccess.open(path)
	if not dir:
		printerr(error_string(DirAccess.get_open_error()))
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


func _on_clear_button_pressed() -> void:
	output_view.clear()
	output_view.text = "## Hello it's horizon, just to say you can edit / select there like in editor.\n## It supports GDScript Highlighter."
