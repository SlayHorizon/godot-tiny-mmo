extends Control


var item_shortcuts: Array[Item]


func _ready() -> void:
	var i: int = 0
	for button: Button in $VBoxContainer.get_children():
		button.pressed.connect(_on_item_shortcut_pressed.bind(button, i))
		i += 1
	item_shortcuts.resize(i)
	item_shortcuts.fill(null)
	
	# Temporary for fast debug
	add_item_to_shorcut(ContentRegistryHub.load_by_id(&"gears", 2), 0)
	add_item_to_shorcut(ContentRegistryHub.load_by_id(&"gears", 3), 1)


func _on_item_shortcut_pressed(button: Button, index: int) -> void:
	var item: Item = item_shortcuts[index]
	if not item:
		return
	
	InstanceClient.current.try_to_equip_item.rpc_id(1, item.get_meta(&"id", -1), 0)


func add_item_to_shorcut(item: Item, index: int) -> void:
	item_shortcuts[index] = item
	$VBoxContainer.get_child(index).icon = item.item_icon
