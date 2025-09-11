@tool
extends ConfirmationDialog


const DEFAULT_DIR: String = "res://source/common/gameplay/"

var file_dialog: EditorFileDialog
var last_dir_selected: String

@onready var content_name_edit: LineEdit = $VBoxContainer/HBoxContainer4/LineEdit
@onready var path_edit: LineEdit = $VBoxContainer/HBoxContainer2/LineEdit
@onready var filters_edit: LineEdit = $VBoxContainer/HBoxContainer/LineEdit

@onready var folder_button: Button = $VBoxContainer/HBoxContainer2/FolderButton


func _ready() -> void:
	folder_button.icon = EditorInterface.get_editor_theme().get_icon(&"Folder", &"EditorIcons")
	title = "Generate Content Index"


func _on_folder_button_pressed() -> void:
	file_dialog = EditorFileDialog.new()
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	
	if last_dir_selected:
		file_dialog.current_dir = last_dir_selected
	else:
		file_dialog.current_dir = DEFAULT_DIR
	
	file_dialog.dir_selected.connect(_on_file_dialog_dir_selected)
	file_dialog.canceled.connect(_on_file_dialog_canceled)
	
	add_child(file_dialog)
	file_dialog.popup_file_dialog()


func _on_file_dialog_canceled() -> void:
	file_dialog.queue_free()


func _on_file_dialog_dir_selected(dir: String) -> void:
	var content_name: StringName = dir.trim_prefix("res://")
	content_name = content_name.get_slice("/", content_name.get_slice_count("/") - 1)
	content_name_edit.text = content_name
	
	path_edit.text = dir
