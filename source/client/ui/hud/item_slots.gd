extends Control


var item_shortcuts: Array[Item]


func _ready() -> void:
	var i: int = 0
	for button: Button in $VBoxContainer.get_children():
		button.pressed.connect(_on_item_shortcut_pressed.bind(button, i))
		i += 1
	item_shortcuts.resize(i)
	item_shortcuts.fill(null)
	
	for slot_index: int in ClientState.quick_slots.data:
		add_item_to_shorcut(
			slot_index,
			ClientState.quick_slots.data.get(slot_index, null)
		)
	ClientState.quick_slots.data_changed.connect(add_item_to_shorcut)


func _on_item_shortcut_pressed(button: Button, index: int) -> void:
	var item: Item = item_shortcuts[index]
	if not item:
		return
	
	DataSynchronizerClient._self.request_data(
		&"item.equip",
		Callable(),
		{"id": item.get_meta(&"id", -1)},
		InstanceClient.current.name
	)


func add_item_to_shorcut(index: int, item: Item) -> void:
	if not index < item_shortcuts.size():
		return
	
	item_shortcuts[index] = item
	var button: Button = $VBoxContainer.get_child(index)
	button.icon = item.item_icon
	if button.icon:
		button.text = ""
	else:
		button.text = item.item_name
