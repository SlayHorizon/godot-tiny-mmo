@tool
extends Tree


signal property_item_edited(path: NodePath)
signal property_item_deleted(path: NodePath)

const EDITOR_FONT_CATEGORY: String = "EditorFonts"
const EDITOR_ICON_CATEGORY: String = "EditorIcons"

var tree_items: Dictionary[TreeItem, TreeItemData]


func _ready() -> void:
	button_clicked.connect(_on_button_clicked)
	
	clear()
	columns = 3
	for column_id: int in columns:
		set_column_expand(column_id, true)
		set_column_title_alignment(column_id, HORIZONTAL_ALIGNMENT_LEFT)
		
	
	set_column_expand_ratio(0, 4)
	set_column_expand_ratio(1, 1)
	set_column_expand_ratio(2, 1)
	
	set_column_title(0, "Property")
	set_column_title(1, "Type")
	set_column_title(2, "Value")
	
	create_item(null)


func add_dict(dict: Dictionary[NodePath, Variant]) -> void:
	for path: NodePath in dict:
		create_property_item(path, dict[path])


func add_property(path: NodePath) -> void:
	var node: Node = EditorInterface.get_edited_scene_root().get_node_or_null(
		TinyNodePath.get_path_to_node(path)
	)
	var value: Variant = node.get_indexed(TinyNodePath.get_path_to_property(path))
	create_property_item(path, value)


func create_property_item(path: NodePath, value: Variant) -> void:
	var property_type: String = type_string(typeof(value))
	var property_icon: Texture2D = _get_theme_icon_safely(property_type, EDITOR_ICON_CATEGORY)
	
	var property_item: TreeItem = create_item()
	property_item.set_text(0, path)
	property_item.set_icon(0, property_icon)
	
	property_item.set_text(1, property_type)
	
	property_item.set_text(2, str(value).left(10))
	
	property_item.add_button(2, _get_theme_icon_safely("Edit", EDITOR_ICON_CATEGORY))
	property_item.add_button(2, _get_theme_icon_safely("Remove", EDITOR_ICON_CATEGORY))
	
	tree_items.set(property_item, TreeItemData.new(path, value))


func _on_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button_index: int) -> void:
	if id == 0:
		set_selected(item, 0)
		property_item_edited.emit(tree_items.get(item).path)
	elif id == 1:
		property_item_deleted.emit(tree_items.get(item).path)
		tree_items.erase(item)
		item.free()


# Helper method to safely get theme icon
func _get_theme_icon_safely(icon_name: String, theme_type: String) -> Texture2D:
	var icon: Texture2D = get_theme_icon(icon_name, theme_type)
	if not icon:
		push_warning("Failed to get theme icon: " + icon_name)
		return null
	return icon


# Helper method to safely get theme font
func _get_theme_font_safely(font_name: String, theme_type: String) -> Font:
	var font: Font = get_theme_font(font_name, theme_type)
	if not font:
		push_warning("Failed to get theme font: " + font_name)
		return null
	return font


class TreeItemData:
	var path: NodePath
	var value: Variant
	
	func _init(_path: NodePath, _value: Variant) -> void:
		path = _path
		value = _value
