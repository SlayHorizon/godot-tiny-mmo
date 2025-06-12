@tool
extends ConfirmationDialog


@onready var tree: Tree = $MarginContainer/VBoxContainer/Tree
@onready var add_button: Button = $MarginContainer/VBoxContainer/HBoxContainer2/AddButton


func _ready() -> void:
	confirmed.connect(queue_free)
	close_requested.connect(queue_free)
	add_button.pressed.connect(_on_add_button_pressed)
	tree.custom_item_clicked.connect(
		func(mouse_button_index: int):
			print("tree.custom_item_clicked: ", mouse_button_index)
	)


func _on_add_button_pressed() -> void:
	#set_unparent_when_invisible(true)
	exclusive = false
	EditorInterface.popup_node_selector(_on_node_selected)
	#hide()


func _on_node_selected(node_path: NodePath) -> void:
	if node_path.is_empty():
		EditorInterface.popup_dialog_centered(self)
		return
	var node: Node = EditorInterface.get_edited_scene_root().get_node_or_null(node_path)
	if node:
		EditorInterface.popup_property_selector(node, _on_property_selected.bind(node_path))


func _on_property_selected(property_path: NodePath, node_path: NodePath) -> void:
	if property_path.is_empty():
		EditorInterface.popup_dialog_centered(self)
		return
	var path: NodePath = NodePath(node_path as String + (property_path as String))
	tree.add_property(path)
	EditorInterface.popup_dialog_centered(self)


var source: Node
func open(_source: Node, dict: Dictionary) -> void:
	source = _source
	show()
	tree.add_dict(dict)
	#popuplate_tree(_source)
