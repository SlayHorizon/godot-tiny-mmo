extends Control


var item_shortcuts: Array[Item]


func _ready() -> void:
	var i: int = 0
	for button: Button in $VBoxContainer.get_children():
		button.pressed.connect(_on_item_shortcut_pressed.bind(button, i))
		i += 1
	item_shortcuts.resize(i)
	item_shortcuts.fill(null)
	
	if Events.cache_data.has(&"hotkey"):
		#add_item_to_shorcut(ContentRegistryHub.load_by_id(&"items", 1), 0)
		#add_item_to_shorcut(ContentRegistryHub.load_by_id(&"items", 5), 1)
		pass
		
	Events.item_shortcut_added.connect(add_item_to_shorcut)
	


func _on_item_shortcut_pressed(button: Button, index: int) -> void:
	var item: Item = item_shortcuts[index]
	if not item:
		return
	
	InstanceClient.current.request_data(
		&"item.equip",
		Callable(),
		{"id": item.get_meta(&"id", -1)}
	)


func add_item_to_shorcut(item: Item, index: int) -> void:
	if not index < item_shortcuts.size():
		return
	
	item_shortcuts[index] = item
	var button: Button = $VBoxContainer.get_child(index)
	button.icon = item.item_icon
	if button.icon:
		button.text = ""
	else:
		button.text = item.item_name
