@tool
#@icon("res://addons/property_selection_window/essentials/icon.svg")
## A tool window for selecting and monitoring node properties in the Godot editor.
## Supports filtering, searching, and type-based filtering of properties.
class_name PropertySelectionWindow
extends PopupPanel

signal properties_selected(selected_properties: Array[String])

# Constants
const EXCLUDED_PROPERTIES: Array[String] = [
	"owner", "multiplayer", "script"
]

const HIDDEN_PROPERTIES: Array[String] = [
	"name", "unique_name_in_owner", "scene_file_path",
	"process_mode", "process_priority", "process_physics_priority",
	"process_thread_group", "process_thread_group_order", "process_thread_messages",
	"physics_interpolation_mode", "auto_translate_mode", "editor_description",
	"self_modulate", "show_behind_parent", "top_level",
	"clip_children", "light_mask", "visibility_layer",
	"z_index", "z_as_relative", "y_sort_enabled",
	"texture_filter", "texture_repeat", "material",
	"use_parent_material", "rotation_degrees", "skew",
	"transform", "global_rotation_degrees", "global_skew",
	"global_transform", "resource_local_to_scene", "resource_name",
	"resource_path", "resource_scene_unique_id",]

const WINDOW_SCENE: PackedScene = preload("editor_extend.tscn")
const NO_TARGET_ERROR_MESSAGE: String = "No target node assigned. Please assign a target node."
const SEARCH_DEBOUNCE_TIME: float = 0.05
const SEARCH_ICON_NAME: String = "Search"
const EDITOR_ICON_CATEGORY: String = "EditorIcons"
const EDITOR_FONT_CATEGORY: String = "EditorFonts"
const FILTER_PROPERTY_USAGE_MASK: int = PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_SUBGROUP | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_INTERNAL
const MAX_RECURSION_DEPTH: int = 10

# UI Elements
@onready var properties_tree: Tree = %PropertiesTree
@onready var search_field: LineEdit = %SearchField
@onready var search_debounce_timer: Timer = %DebounceTimer
@onready var type_filter_option: OptionButton = %TypeFilterOption

var _warning_popup: AcceptDialog
var target: Node
var initially_selected_properties: Array = []
var show_hidden_properties: bool = false
var current_type_filter: int = 0
var _on_properties_selected_callback: Callable
var _visited_objects: Dictionary = {}
var _current_recursion_depth: int = 0

enum CUSTOM_PROPERTY_TYPES {
	RESOURCE = 1000,
}

var CUSTOM_TYPE_INFO = {
	CUSTOM_PROPERTY_TYPES.RESOURCE: {
		"name": "Resource",
		"icon": "Resource",
		"check": func(value): return value is Resource
	},
}

var TYPE_FILTER_OPTIONS: Dictionary = {
	0: "All Types",
	TYPE_BOOL: "Boolean",
	TYPE_INT: "Integer",
	TYPE_FLOAT: "Float",
	TYPE_STRING: "String",
	TYPE_VECTOR2: "Vector2",
	TYPE_VECTOR3: "Vector3",
	TYPE_COLOR: "Color",
	TYPE_OBJECT: "Object"
}

# Caching
var _property_cache: Dictionary = {}

static func create_window(target: Node, initially_selected_properties: Array = [], show_hidden_properties: bool = false, type_filter: int = -1, callback: Callable = Callable()) -> void:
	var window = WINDOW_SCENE.instantiate()
	window.theme = EditorInterface.get_editor_theme()
	window.target = target
	window.initially_selected_properties = initially_selected_properties
	window.show_hidden_properties = show_hidden_properties
	window.current_type_filter = type_filter
	window._on_properties_selected_callback = callback
	EditorInterface.popup_dialog_centered(window)


func _ready() -> void:
	for custom_type in CUSTOM_TYPE_INFO:
		TYPE_FILTER_OPTIONS[custom_type] = CUSTOM_TYPE_INFO[custom_type].name
	
	_visited_objects.clear()
	_current_recursion_depth = 0
	_initialize_properties_tree()
	_setup_type_filter()
	_check_target()
	_setup_ui()
	_create_warning_popup()


func _create_warning_popup() -> void:
	_warning_popup = AcceptDialog.new()
	_warning_popup.dialog_text = NO_TARGET_ERROR_MESSAGE
	_warning_popup.title = "No Target Node"
	_warning_popup.confirmed.connect(_warning_popup.queue_free)
	_warning_popup.canceled.connect(_warning_popup.queue_free)
	add_child(_warning_popup)

func _setup_ui() -> void:
	search_field.right_icon = _get_theme_icon_safely(SEARCH_ICON_NAME, EDITOR_ICON_CATEGORY)
	search_debounce_timer.wait_time = SEARCH_DEBOUNCE_TIME

func _initialize_properties_tree() -> void:
	properties_tree.clear()
	properties_tree.set_column_expand(0, true)
	properties_tree.set_column_expand(1, true)
	properties_tree.set_column_expand(2, true)
	properties_tree.set_column_expand_ratio(0, 5)
	properties_tree.set_column_expand_ratio(1, 1)
	properties_tree.set_column_expand_ratio(2, 1)
	properties_tree.set_column_title(0, "Property")
	properties_tree.set_column_title(1, "Type")
	properties_tree.set_column_title(2, "Value")
	properties_tree.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
	properties_tree.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)
	properties_tree.set_column_title_alignment(2, HORIZONTAL_ALIGNMENT_LEFT)


func _setup_type_filter() -> void:
	type_filter_option.clear()
	
	for type_value in TYPE_FILTER_OPTIONS:
		type_filter_option.add_item(TYPE_FILTER_OPTIONS[type_value], type_value)
	
	type_filter_option.item_selected.connect(_on_type_filter_changed)

	type_filter_option.select(0)

func _check_target() -> void:
	# Handle null or invalid target
	if not target:
		_display_error_dialog("No Target Node", NO_TARGET_ERROR_MESSAGE)
		return
	
	# Check for self-assignment
	if target == self:
		_display_error_dialog("Invalid Target", "Cannot assign window as its own target. This would create a circular reference.")
		return
	
	# Check for circular references in the parent chain
	var parent_node = get_parent()
	while parent_node:
		if parent_node == target:
			_display_error_dialog("Invalid Target", "Circular reference detected. Target cannot be a parent of this window.")
			return
		parent_node = parent_node.get_parent()
	
	# Check if target is already being observed
	if target in _property_cache:
		# Clear existing cache to prevent stale data
		_property_cache.erase(target)
	
	# Verify target is still valid and in the scene tree
	if not is_instance_valid(target) or not target.is_inside_tree():
		_display_error_dialog("Invalid Target", "Target node is invalid or not in the scene tree.")
		return
	
	# Finally, populate the tree if all checks pass
	_populate_tree(target)

func _display_error_dialog(title: String, message: String) -> void:
	var error_dialog = AcceptDialog.new()
	error_dialog.title = title
	error_dialog.dialog_text = message
	error_dialog.confirmed.connect(error_dialog.queue_free)
	error_dialog.canceled.connect(error_dialog.queue_free)
	add_child(error_dialog)
	error_dialog.popup_centered()

func _populate_tree(node: Object, parent_item: TreeItem = null, filter: String = "", property_name: String = "") -> void:
	if not is_instance_valid(node):
		_handle_tree_error("Invalid node passed to _populate_tree")
		return
		
	# Check recursion depth
	_current_recursion_depth += 1
	if _current_recursion_depth > MAX_RECURSION_DEPTH:
		_handle_tree_error("Maximum recursion depth reached while populating tree")
		_current_recursion_depth -= 1
		return
	
	# Get unique identifier for the object
	var object_id = node.get_instance_id()
	
	# Check for circular reference
	if object_id in _visited_objects:
		var circular_ref_item = _create_tree_item(node, parent_item, property_name)
		circular_ref_item.set_text(2, "[Circular Reference]")
		circular_ref_item.set_custom_color(2, Color.DARK_RED)
		circular_ref_item.set_tooltip_text(2, "Circular reference detected - further expansion stopped")
		_current_recursion_depth -= 1
		return
		
	# Add object to visited set
	_visited_objects[object_id] = true

	var item := _create_tree_item(node, parent_item, property_name)
	var properties := _get_cached_properties(node)
	_add_properties_to_tree(properties, node, item, filter)
	
	# Remove object from visited set when done with this branch
	_visited_objects.erase(object_id)
	_current_recursion_depth -= 1

func _create_tree_item(node: Object, parent_item: TreeItem, property_name: String = "") -> TreeItem:
	var item: TreeItem = parent_item if parent_item != null else properties_tree.create_item()
	
	if property_name:
		item.set_text(0, property_name)
	else:
		item.set_text(0, node.name if node.has_method("get_name") else "Unknown")
	
	item.set_custom_font(0, _get_theme_font_safely("bold", EDITOR_FONT_CATEGORY))
	item.set_icon(0, _get_theme_icon_safely(node.get_class(), EDITOR_ICON_CATEGORY))

	return item

func _get_cached_properties(node: Object) -> Array[Dictionary]:
	if node in _property_cache:
		return _property_cache[node]
		
	var properties = _get_filtered_properties(node)
	_property_cache[node] = properties
	return properties

func _get_filtered_properties(node: Object) -> Array[Dictionary]:
	if not is_instance_valid(node):
		_handle_tree_error("Invalid node passed to _get_filtered_properties")
		return []

	var properties := node.get_property_list()
	properties = properties.filter(func(p): 
		return _is_property_valid(p) and _passes_type_filter(p))
	properties.sort_custom(_sort_properties_by_name)

	return properties

func _passes_type_filter(property: Dictionary) -> bool:
	if current_type_filter in [-1, 0]:  # No filter
		return true
		
	# Check if it's a custom type filter
	if current_type_filter in CUSTOM_TYPE_INFO:
		var value = _get_property_safely(target, property.name)
		return CUSTOM_TYPE_INFO[current_type_filter].check.call(value)
		
	return property.type == current_type_filter

func _add_properties_to_tree(properties: Array[Dictionary], node: Object, item: TreeItem, filter: String) -> void:
	if not is_instance_valid(node) or not is_instance_valid(item):
		_handle_tree_error("Invalid node or item passed to _add_properties_to_tree")
		return

	for property in properties:
		if _is_property_valid(property):
			var property_name = property.name
			if property_name not in EXCLUDED_PROPERTIES:
				# Safely get property value with error handling
				var property_value = _get_property_safely(node, property_name)
				var child_item = _create_property_tree_item(property_name, property_value, property.type, item)
				
				if typeof(property_value) == TYPE_OBJECT and property_value != null:
					# Check if this would create a circular reference
					if property_value.get_instance_id() in _visited_objects:
						child_item.set_text(2, "[Circular Reference]")
						child_item.set_custom_color(2, Color.DARK_RED)
						child_item.set_tooltip_text(2, "Circular reference detected - further expansion stopped")
					else:
						child_item.collapsed = true
						_populate_tree(property_value, child_item, filter, property_name)
						
				if property_name in HIDDEN_PROPERTIES and not show_hidden_properties:
					child_item.visible = false
				_check_initially_selected_property(child_item, property_name)

func _get_property_safely(node: Object, property_name: String) -> Variant:
	if not is_instance_valid(node):
		push_warning("Attempted to get property from invalid node: " + property_name)
		return null
		
	if node.has_method("get"):
		# Direct property access with error handling
		var result = null
		
		# Use get_indexed to safely access properties
		if "." in property_name:
			var parts = property_name.split(".")
			var current = node
			
			for part in parts:
				if is_instance_valid(current) and current.has_method("get"):
					current = current.get(part)
				else:
					return null
			
			result = current
		else:
			result = node.get(property_name)
			
		return result
	
	push_warning("Unable to get property: " + property_name)
	return null

func _resolve_custom_class_name(property_value: Object) -> String:
	if not is_instance_valid(property_value):
		return "Invalid Object"

	var script = property_value.get_script()
	if not script:
		return property_value.get_class()

	var global_class_name = script.get_global_name()

	if global_class_name == "":
		return property_value.get_class()
	
	return global_class_name

func _create_property_tree_item(property_name: String, property_value: Variant, property_type: int, parent_item: TreeItem) -> TreeItem:
	var child_item = properties_tree.create_item(parent_item)
	var child_type: String
	var child_icon: Texture2D
	
	# Check for Object types (including custom types and resources)
	if property_type == TYPE_OBJECT and property_value != null:
		# Resolve the actual class name for any object type
		child_type = _resolve_custom_class_name(property_value)
		
		# Try to get icon for the resolved class name first
		child_icon = _get_theme_icon_safely(child_type, EDITOR_ICON_CATEGORY)
		
		# Fall back to base class icon if needed
		if child_icon == null:
			var base_class = property_value.get_class()
			child_icon = _get_theme_icon_safely(base_class, EDITOR_ICON_CATEGORY)
			
		# Check custom type info for additional processing
		for type_id in CUSTOM_TYPE_INFO:
			if CUSTOM_TYPE_INFO[type_id].check.call(property_value):
				# Use the resolved class name but keep custom type handling
				if child_icon == null:
					child_icon = _get_theme_icon_safely(CUSTOM_TYPE_INFO[type_id].icon, EDITOR_ICON_CATEGORY)
				break
	else:
		# Handle non-object types as before
		child_type = type_string(property_type)
		child_icon = _get_theme_icon_safely(child_type, EDITOR_ICON_CATEGORY)

	# Set up the tree item
	child_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	child_item.set_editable(0, true)
	child_item.set_text(0, property_name)
	child_item.set_tooltip_text(0, _get_full_property_name(child_item))
	child_item.set_icon(0, child_icon)
	child_item.set_text(1, child_type)
	child_item.set_text(2, _format_property_value(property_value, property_type))
	child_item.set_editable(2, true)

	return child_item

func _format_property_value(value: Variant, type: int) -> String:
	match type:
		TYPE_BOOL:
			return str(value)
		TYPE_INT, TYPE_FLOAT:
			return str(value)
		TYPE_STRING:
			return "\"" + value + "\""
		TYPE_VECTOR2:
			return "(%s, %s)" % [value.x, value.y]
		TYPE_VECTOR3:
			return "(%s, %s, %s)" % [value.x, value.y, value.z]
		TYPE_COLOR:
			return "#%s" % value.to_html(true)
		TYPE_OBJECT:
			if value == null:
				return "null"
			# Use the resolved class name for object types
			var custom_class_name = _resolve_custom_class_name(value) if value is Object else value.get_class()
			return "[%s:%s]" % [custom_class_name, value.get_instance_id()]
		_:
			return str(value)

func _check_initially_selected_property(child_item: TreeItem, property_name: String) -> void:
	var full_property_name = _get_full_property_name(child_item)
	child_item.set_checked(0, full_property_name in initially_selected_properties)

func _get_full_property_name(item: TreeItem) -> String:
	if not is_instance_valid(item):
		_handle_tree_error("Invalid item passed to _get_full_property_name")
		return ""
	
	var names = []
	var current_item = item

	while current_item:
		if current_item.get_text(0) == properties_tree.get_root().get_text(0):
			break
		names.insert(0, current_item.get_text(0))
		current_item = current_item.get_parent()

	return ".".join(names)

func _is_property_valid(property: Dictionary) -> bool:
	return not (property.usage & FILTER_PROPERTY_USAGE_MASK)

func _sort_properties_by_name(a: Dictionary, b: Dictionary) -> bool:
	return a.name.nocasecmp_to(b.name) < 0

func _on_search_text_changed(new_text: String) -> void:
	if not search_debounce_timer.is_stopped():
		search_debounce_timer.stop()

	search_debounce_timer.start()

	await search_debounce_timer.timeout
	var previous_checked_states = _get_current_checked_states()
	_filter_tree(new_text)
	_restore_checked_states(previous_checked_states)

func _filter_tree(filter: String) -> void:
	var root_item = properties_tree.get_root()
	if not is_instance_valid(root_item):
		_handle_tree_error("Invalid root item in _filter_tree")
		return

	var current_item = root_item.get_first_child()

	while current_item:
		var full_property_name = _get_full_property_name(current_item)
		_update_item_visibility(current_item, full_property_name, filter, root_item)
		current_item = current_item.get_next_in_tree()

func _update_item_visibility(current_item: TreeItem, full_property_name: String, filter: String, root_item: TreeItem) -> void:
	if not is_instance_valid(current_item):
		_handle_tree_error("Invalid item passed to _update_item_visibility")
		return

	if not show_hidden_properties and current_item.get_text(0) in HIDDEN_PROPERTIES:
		return

	if filter.is_empty() or filter.to_lower() in full_property_name.to_lower():
		_set_item_and_parents_visible(current_item, root_item, true)
	else:
		current_item.collapsed = true
		current_item.visible = false

func _set_item_and_parents_visible(item: TreeItem, root_item: TreeItem, visibility: bool) -> void:
	if not is_instance_valid(item) or not is_instance_valid(root_item):
		_handle_tree_error("Invalid item or root_item passed to _set_item_and_parents_visible")
		return

	var parent = item.get_parent()
	while parent and parent != root_item:
		parent.set_collapsed(not visibility)
		parent.visible = visibility
		parent = parent.get_parent()
	item.collapsed = not visibility
	item.visible = visibility

func _get_current_checked_states() -> Dictionary:
	var checked_states = {}
	var root_item = properties_tree.get_root()

	if is_instance_valid(root_item):
		var child_item = root_item.get_first_child()
		while child_item:
			if child_item.is_checked(0):
				checked_states[_get_full_property_name(child_item)] = true
			child_item = child_item.get_next_in_tree()

	return checked_states

func _restore_checked_states(checked_states: Dictionary) -> void:
	var root_item = properties_tree.get_root()

	if is_instance_valid(root_item):
		var child_item = root_item.get_first_child()
		while child_item:
			var full_property_name = _get_full_property_name(child_item)
			if full_property_name in checked_states:
				child_item.set_checked(0, true)
			child_item = child_item.get_next_in_tree()

func _on_show_all_toggled(toggled_on: bool) -> void:
	show_hidden_properties = toggled_on
	_repopulate_tree()

func _on_type_filter_changed(index: int) -> void:
	current_type_filter = type_filter_option.get_item_id(index)
	_clear_property_cache()
	_repopulate_tree()

func _repopulate_tree() -> void:
	var previous_checked_states = _get_current_checked_states()
	_initialize_properties_tree()
	_populate_tree(target)
	_restore_checked_states(previous_checked_states)

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		queue_free()

func _on_cancel_pressed() -> void:
	queue_free()

func _on_confirm_pressed() -> void:
	var selected_properties = _get_selected_properties()
	properties_selected.emit(selected_properties)
	if _on_properties_selected_callback.is_valid():
		_on_properties_selected_callback.call(selected_properties)
	queue_free()

func _on_close_requested() -> void:
	queue_free()

func _get_selected_properties() -> Array[String]:
	var selected_properties: Array[String] = []
	var root_item = properties_tree.get_root()

	if is_instance_valid(root_item):
		var child_item = root_item.get_first_child()
		while child_item:
			if child_item.is_checked(0):
				selected_properties.append(_get_full_property_name(child_item))
			child_item = child_item.get_next_in_tree()

	return selected_properties

# Public method to set the target node
func set_target(new_target: Node) -> void:
	target = new_target
	_clear_property_cache()
	_check_target()

# Public method to set initially selected properties
func set_initially_selected_properties(properties: Array[String]) -> void:
	initially_selected_properties = properties
	if properties_tree.get_root():
		_update_initially_selected_properties()

func _update_initially_selected_properties() -> void:
	var root_item = properties_tree.get_root()
	if not is_instance_valid(root_item):
		_handle_tree_error("Invalid root item in _update_initially_selected_properties")
		return

	var stack: Array[TreeItem] = [root_item]
	while not stack.is_empty():
		var item = stack.pop_back()
		var full_property_name = _get_full_property_name(item)
		item.set_checked(0, full_property_name in initially_selected_properties)
		
		var child = item.get_first_child()
		while child:
			stack.push_back(child)
			child = child.get_next()

# Helper method to safely get theme icon
func _get_theme_icon_safely(icon_name: String, theme_type: String) -> Texture2D:
	var icon = get_theme_icon(icon_name, theme_type)
	if not icon:
		push_warning("Failed to get theme icon: " + icon_name)
		return null
	return icon

# Helper method to safely get theme font
func _get_theme_font_safely(font_name: String, theme_type: String) -> Font:
	var font = get_theme_font(font_name, theme_type)
	if not font:
		push_warning("Failed to get theme font: " + font_name)
		return null
	return font

# Override _notification to handle theme changes
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_THEME_CHANGED:
			_update_theme()

func _update_theme() -> void:
	if is_instance_valid(search_field):
		search_field.right_icon = _get_theme_icon_safely(SEARCH_ICON_NAME, EDITOR_ICON_CATEGORY)
	
	if is_instance_valid(properties_tree):
		_update_tree_icons()

func _update_tree_icons() -> void:
	var root_item = properties_tree.get_root()
	if not is_instance_valid(root_item):
		return

	var stack: Array[TreeItem] = [root_item]
	while not stack.is_empty():
		var item = stack.pop_back()
		var icon_type = type_string(typeof(_get_property_safely(target, item.get_text(0))))
		item.set_icon(0, _get_theme_icon_safely(icon_type, EDITOR_ICON_CATEGORY))
		
		var child = item.get_first_child()
		while child:
			stack.push_back(child)
			child = child.get_next()

# Error handling for tree operations
func _handle_tree_error(message: String) -> void:
	push_error(message)
	var error_dialog = AcceptDialog.new()
	error_dialog.dialog_text = "An error occurred: " + message
	error_dialog.dialog_autowrap = true
	add_child(error_dialog)
	error_dialog.popup_centered()

# Clear cache when necessary
func _clear_property_cache() -> void:
	_property_cache.clear()

# Override _exit_tree to clean up
func _exit_tree() -> void:
	print("exit tree")
	if _warning_popup:
		_warning_popup.queue_free()
	_clear_property_cache()
	_visited_objects.clear()
	_current_recursion_depth = 0

# New method to refresh the tree
func refresh_tree() -> void:
	_clear_property_cache()
	_visited_objects.clear()
	_current_recursion_depth = 0
	_repopulate_tree()

# New method to get the current filter text
func get_current_filter() -> String:
	return search_field.text

# New method to programmatically set the filter
func set_filter(filter_text: String) -> void:
	search_field.text = filter_text
	_on_search_text_changed(filter_text)

# New method to expand all tree items
func expand_all() -> void:
	var root_item = properties_tree.get_root()
	if is_instance_valid(root_item):
		_expand_item_and_children(root_item)

# Helper method for expand_all
func _expand_item_and_children(item: TreeItem) -> void:
	item.collapsed = false
	var child = item.get_first_child()
	while child:
		_expand_item_and_children(child)
		child = child.get_next()

# New method to collapse all tree items
func collapse_all() -> void:
	var root_item = properties_tree.get_root()
	if is_instance_valid(root_item):
		_collapse_item_and_children(root_item)

# Helper method for collapse_all
func _collapse_item_and_children(item: TreeItem) -> void:
	item.collapsed = true
	var child = item.get_first_child()
	while child:
		_collapse_item_and_children(child)
		child = child.get_next()

# New method to get the current type filter
func get_current_type_filter() -> int:
	return current_type_filter

# New method to programmatically set the type filter
func set_type_filter(filter: int) -> void:
	var index = type_filter_option.get_item_index(filter)
	if index != -1:
		type_filter_option.selected = index
		_on_type_filter_changed(index)

# New method to toggle visibility of hidden properties
func toggle_hidden_properties(show: bool) -> void:
	show_hidden_properties = show
	_repopulate_tree()

# New method to get all available properties
func get_all_properties() -> Array[String]:
	var all_properties: Array[String] = []
	var root_item = properties_tree.get_root()

	if is_instance_valid(root_item):
		var stack: Array[TreeItem] = [root_item]
		while not stack.is_empty():
			var item = stack.pop_back()
			all_properties.append(_get_full_property_name(item))
			
			var child = item.get_first_child()
			while child:
				stack.push_back(child)
				child = child.get_next()

	return all_properties

# New method to check if a property exists
func property_exists(property_name: String) -> bool:
	return property_name in get_all_properties()

# New method to get property type
func get_property_type(property_name: String) -> int:
	var properties = _get_cached_properties(target)
	for property in properties:
		if property.name == property_name:
			return property.type
	return TYPE_NIL

# New method to get property value
func get_property_value(property_name: String) -> Variant:
	return _get_property_safely(target, property_name)

# New method to set property value
func set_property_value(property_name: String, value: Variant) -> void:
	if target.has_method("set"):
		target.set(property_name, value)
	else:
		push_warning("Unable to set property: " + property_name)

# New method to connect to tree item selection changed
func connect_to_item_selected(callable: Callable) -> void:
	properties_tree.item_selected.connect(callable)

# New method to disconnect from tree item selection changed
func disconnect_from_item_selected(callable: Callable) -> void:
	if properties_tree.item_selected.is_connected(callable):
		properties_tree.item_selected.disconnect(callable)

# New method to get the currently selected tree item
func get_selected_tree_item() -> TreeItem:
	return properties_tree.get_selected()

# New method to set the selected tree item
func set_selected_tree_item(item: TreeItem) -> void:
	item.select(0)

func _would_create_circular_reference(object: Object) -> bool:
	return object != null and object.get_instance_id() in _visited_objects
