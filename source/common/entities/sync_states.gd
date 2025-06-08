@tool
extends Node


@export_tool_button("Open SyncStates Menu", "MultiplayerSynchronizer") var callback = foo
@export var ff: NodePath
@export var dict: Dictionary[NodePath, Variant] = {}


func foo() -> void:
	return
	var node = ScriptCreateDialog.new()
	add_child(node)
	node.owner = get_tree().edited_scene_root
	return
	PropertySelectionWindow.create_window(owner)
	return
	if not Engine.is_editor_hint():
		return
	EditorInterface.popup_node_selector(_on_node_selected)


func _on_node_selected(node_path: NodePath) -> void:
	if node_path.is_empty():
		return
	var root: Node = EditorInterface.get_edited_scene_root()
	var node: Node = root.get_node_or_null(node_path)
	if node:
		EditorInterface.popup_property_selector(node, _on_property_selected.bind(node_path))


func _on_property_selected(property_path: NodePath, node_path: NodePath) -> void:
	if property_path.is_empty():
		return
	var path: NodePath = NodePath(node_path as String + (property_path as String))
	print(path)
