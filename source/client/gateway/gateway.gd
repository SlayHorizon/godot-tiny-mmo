extends Control


var pending_requests
var handler: Callable
var world_info_: Dictionary
var _account_id: int
var _account_name: String
var token: int = randi()

@onready var world_server: WorldClient = $"../WorldClient"

@onready var main_panel: PanelContainer = $MainPanel
@onready var login_panel: PanelContainer = $LoginPanel

@onready var http_request: HTTPRequest = $HTTPRequest


func _ready() -> void:
	$SwapButton.pressed.connect(func():
		$Desert.visible = not $Desert.visible
		$FairyForest.visible = not $FairyForest.visible
	)


func do_request(
	method: HTTPClient.Method,
	path: String,
	payload: Dictionary,
) -> Dictionary:
	var headers: PackedStringArray
	headers.append("Content-Type: application/json")

	#http_request.request_completed.connect(_on_request_completed)
	var error: Error = http_request.request(
		path,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	
	if error != OK:
		push_error("An error occurred in the HTTP request.")
		return {ok=false, error="request_error", code=error}
	return {}


func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print_debug("result = ", result, " code = ", response_code, " header = ", headers)
	if result != OK:
		print("ERROR?")
		return
	var data = JSON.parse_string(body.get_string_from_ascii())
	print_debug(data)
	if data is Dictionary:
		handler.call(data)


func _on_login_button_pressed() -> void:
	main_panel.hide()
	login_panel.show()
	# Test
	#do_request(
		#HTTPClient.Method.METHOD_POST,
		#"http://127.0.0.1:8088/v1/login",
		#{"u": "username", "p": "password"}
	#)


func _on_login_login_button_pressed() -> void:
	var account_name_edit: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer/LineEdit
	var password_edit: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	
	var account_name: String = account_name_edit.text
	var password: String = password_edit.text
	
	var login_button: Button = $LoginPanel/VBoxContainer/VBoxContainer/LoginButton
	login_button.disabled = true
	 # More checks can be done with specific message
	if (
		account_name.length() > 3 and account_name.length() < 12
		and password.length() > 5 and password.length() < 20
	):
		var world_selection: PanelContainer = $WorldSelection
		handler = func(d: Dictionary) -> void:
			if not d.has("error"):
				login_panel.hide()
				world_selection.show()
			else:
				login_button.disabled = false
		handler = Callable()
		do_request(
			HTTPClient.Method.METHOD_POST,
			"http://127.0.0.1:8088/v1/login",
			{"u": account_name, "p": password, "t-id": token}
		)


func _on_guest_button_pressed() -> void:
	handler = func(d: Dictionary) -> void:
		if d.has("error"):
			return
		main_panel.hide()
		var container: HBoxContainer = $WorldSelection/VBoxContainer/HBoxContainer
		for child: Node in container.get_children():
			child.queue_free()
		var world_info: Dictionary = d.get("w", {})
		
		_account_id = d["a"]["id"]
		_account_name = d["a"]["name"]
		
		for world_id: String in world_info:
			var new_button: Button = Button.new()
			new_button.custom_minimum_size = Vector2(150, 250)
			new_button.clip_text = true
			new_button.text = "%s\n\n%s\n\n%s" % [
				world_info[world_id].get("name", "name"),
				" \n".join(str(world_info[world_id]["info"]).split(", ")),
				"t"
			]
			
			new_button.pressed.connect(_on_world_selected.bind(world_id.to_int()))
			container.add_child(new_button)
		world_info_ = d["w"]
		$WorldSelection.show()
	do_request(
		HTTPClient.Method.METHOD_POST,
		"http://127.0.0.1:8088/v1/guest",
		{"t-id": token}
	)


func _on_world_selected(world_id: int) -> void:
	handler = func(d: Dictionary) -> void:
		print_debug(d)
		if d.has("error"):
			return
		var container: HBoxContainer = $CharacterSelection/VBoxContainer/HBoxContainer
		for child: Node in container.get_children():
			child.queue_free()
		for character_id: String in d.get("data", {}):
			var new_button: Button = Button.new()
			new_button.custom_minimum_size = Vector2(150, 250)
			new_button.text = "%s\nClass: %s\nLevel: %d" % [
				d[character_id]["name"],
				d[character_id]["class"],
				d[character_id]["level"],
			]
			new_button.pressed.connect(_on_character_selected.bind(world_id, character_id.to_int()))
			add_child(new_button)
		await get_tree().process_frame
		var child_count: int = container.get_child_count()
		print_debug(child_count)
		while child_count < 3:
			var new_button: Button = Button.new()
			new_button.custom_minimum_size = Vector2(150, 250)
			new_button.text = "Create New Character"
			container.add_child(new_button)
			new_button.pressed.connect(_on_character_selected.bind(world_id, -1))
			child_count += 1
		$WorldSelection.hide()
		$CharacterSelection.show()
	do_request(
		HTTPClient.Method.METHOD_POST,
		"http://127.0.0.1:8088/v1/world/characters",
		{"w-id": world_id, "a-id": _account_id, "a-u": _account_name, "t-id": token}
	)

var current_world_id: int
func _on_character_selected(world_id: int, character_id: int) -> void:
	current_world_id = world_id
	if character_id == -1:
		$CharacterSelection.hide()
		$CharacterCreation.show()
		return
	$CharacterSelection.hide()
	handler = func(d: Dictionary) -> void:
		if d.has("error"):
			return
		world_server.authentication_token = d["token"]
		world_server.connect_to_server(d["adress"], d["port"])
		queue_free.call_deferred()
	do_request(
		HTTPClient.Method.METHOD_POST,
		"http://127.0.0.1:8088/v1/world/enter",
		{"w-id": world_id, "c-id": character_id}
	)


func _on_create_character_button_pressed() -> void:
	var username_edit: LineEdit = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer2/HBoxContainer/LineEdit

	var create_button: Button = $CharacterCreation/VBoxContainer/VBoxContainer/CreateButton
	create_button.disabled = true
	handler = func(d: Dictionary) -> void:
		if d.has("error"):
			return
		world_server.authentication_token = d["data"]["auth-token"]
		world_server.connect_to_server(d["data"]["address"], d["data"]["port"])
		queue_free.call_deferred()
	do_request(
		HTTPClient.Method.METHOD_POST,
		"http://127.0.0.1:8088/v1/world/character/create",
		{
			"t-id": token,
			"data": {
				"name": username_edit.text,
				"class": "knight",
				
			},
			"a-u": _account_name,
			#"class": selected_character_class.character_name.to_lower(),
			"w-id": current_world_id
		}
	)
