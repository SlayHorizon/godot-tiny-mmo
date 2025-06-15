@tool
extends ConfirmationDialog


const GetPropertyHint: GDScript = preload("res://addons/tinymmo/popup/get_property_hint.gd")

var source: Node
var property_editor: EditorProperty
var edited_dict: Dictionary[NodePath, Variant]

@onready var tree: Tree = $MarginContainer/VBoxContainer/Tree
@onready var add_button: Button = get_ok_button()


func _init() -> void:
	title = "Set spawn state"
	ok_button_text = "Add Property Path"
	dialog_hide_on_ok = false
	cancel_button_text = "Ok"


func _ready() -> void:
	close_requested.connect(queue_free)
	add_button.pressed.connect(_on_add_button_pressed)
	tree.property_item_deleted.connect(
		func(path: NodePath) -> void:
			edited_dict.erase(path)
			property_editor.change_property(edited_dict)
	)
	tree.property_item_edited.connect(
		func(path: NodePath) -> void:
			var dialog := AcceptDialog.new()
			dialog.add_child(create_property_editor(path))
			dialog.transient = true
			dialog.exclusive = true
			add_child(dialog)
			dialog.popup_centered()
			dialog.confirmed.connect(func():pass)
	)


func _on_add_button_pressed() -> void:
	#set_unparent_when_invisible(true)
	#exclusive = false
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
	var node: Node = source.get_node_or_null(node_path)
	if not node:
		return
	var property: Variant = node.get_indexed(property_path)
	tree.add_property(path)
	edited_dict[path] = property


func open(_source: Node, _property_editor: EditorProperty) -> void:
	source = _source
	property_editor = _property_editor
	edited_dict.assign(
		source.get(property_editor.get_edited_property())
	)
	print(edited_dict)
	edited_dict[^"Salade"] = 2
	print(edited_dict)
	property_editor.change_property(edited_dict)
	tree.add_dict(edited_dict)
	#popuplate_tree(_source)


func create_property_editor(path: NodePath) -> EditorProperty:
	var new_property_editor: EditorProperty
	
	var node: Node = source.get_node_or_null(TinyNodePath.get_path_to_node(path))
	if not node:
		return
	var property: Variant = node.get_indexed(TinyNodePath.get_path_to_property(path))
	print("property: ", property)
	var property_type: Variant.Type = typeof(property)
	var property_hint: PropertyHint = GetPropertyHint.get_property_hint(property_type)
	new_property_editor = EditorInspector.instantiate_property_editor(
		node, property_type,
		TinyNodePath.get_path_to_property(path), property_hint,
		"Suprise", PROPERTY_USAGE_DEFAULT,
	)
	new_property_editor.label = path.slice(path.get_name_count() + path.get_subname_count() - 1)
	new_property_editor.set_object_and_property(node, path.get_subname(0))
	print(new_property_editor.get_edited_property())
	new_property_editor.update_property()
	return new_property_editor
