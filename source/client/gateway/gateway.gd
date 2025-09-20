extends Control


# Helper class
const CredentialsUtils = preload("res://source/common/utils/credentials_utils.gd")
const GatewayApi = preload("res://source/common/network/gateway_api.gd")

@export var world_server: WorldClient

var account_id: int
var account_name: String
var token: int = randi()

var current_world_id: int
var selected_skin: String = "rogue"

@onready var main_panel: PanelContainer = $MainPanel
@onready var login_panel: PanelContainer = $LoginPanel
@onready var popup_panel: PanelContainer = $PopupPanel

@onready var http_request: HTTPRequest = $HTTPRequest


func _ready() -> void:
	$SwapButton.pressed.connect(func():
		if not $AudioStreamPlayer.playing:
			$AudioStreamPlayer.play()
		$Desert.visible = not $Desert.visible
		$FairyForest.visible = not $FairyForest.visible
	)


func do_request(
	method: HTTPClient.Method,
	path: String,
	payload: Dictionary,
) -> Dictionary:
	if http_request.get_http_client_status() == HTTPClient.Status.STATUS_CONNECTED:
		return {"error": ""}
	
	var custom_headers: PackedStringArray
	custom_headers.append("Content-Type: application/json")
	
	var error: Error = http_request.request(
		path,
		custom_headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)

	if error != OK:
		push_error("An error occurred in the HTTP request.")
		return {ok=false, error="request_error", code=error}
	
	var args: Array = await http_request.request_completed
	var result: int = args[0]
	if result != OK:
		print("ERROR?, TIMEOUT?")
		return {"error": 1}
	
	var response_code: int = args[1]
	var headers: PackedStringArray = args[2]
	var body: PackedByteArray = args[3]
	
	var data = JSON.parse_string(body.get_string_from_ascii())
	if data is Dictionary:
		return data
	return {"error": 1}


func _on_login_button_pressed() -> void:
	main_panel.hide()
	login_panel.show()


func _on_login_login_button_pressed() -> void:
	var account_name_edit: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer/LineEdit
	var password_edit: LineEdit = $LoginPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	
	var username: String = account_name_edit.text
	var password: String = password_edit.text
	
	var login_button: Button = $LoginPanel/VBoxContainer/VBoxContainer/LoginButton
	login_button.disabled = true
	if (
		CredentialsUtils.validate_username(username).code != CredentialsUtils.UsernameError.OK
		or CredentialsUtils.validate_password(password).code != CredentialsUtils.UsernameError.OK
	):
		login_button.disabled = false
		return

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayApi.login(),
		{"u": username, "p": password,
		GatewayApi.KEY_TOKEN_ID: token}
	)
	if d.has("error"):
		login_button.disabled = false
		return
	main_panel.hide()
	$LoginPanel.hide()
	populate_worlds(d.get("w", {}))
	
	fill_connection_info(d["a"]["name"], d["a"]["id"])
	$WorldSelection.show()


func _on_guest_button_pressed() -> void:
	main_panel.hide()
	popup_panel.display_waiting_popup()

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayApi.guest(),
		{GatewayApi.KEY_TOKEN_ID: token}
	)
	if d.has("error"):
		return
	
	fill_connection_info(d["a"]["name"], d["a"]["id"])
	popup_panel.hide()
	populate_worlds(d.get("w", {}))
	$WorldSelection.show()


func _on_world_selected(world_id: int) -> void:
	$WorldSelection.hide()
	popup_panel.display_waiting_popup()
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayApi.world_characters(),
		{GatewayApi.KEY_WORLD_ID: world_id,
		GatewayApi.KEY_ACCOUNT_ID: account_id,
		GatewayApi.KEY_ACCOUNT_USERNAME: account_name,
		GatewayApi.KEY_TOKEN_ID: token}
	)
	if d.has("error"):
		$WorldSelection.show()
		return
	var container: HBoxContainer = $CharacterSelection/VBoxContainer/HBoxContainer
	for child: Node in container.get_children():
		child.queue_free()
	for character_id: String in d.get("data", {}):
		var new_button: Button = Button.new()
		new_button.custom_minimum_size = Vector2(150, 250)
		new_button.text = "%s\nClass: %s\nLevel: %d" % [
			d["data"][character_id]["name"],
			d["data"][character_id]["class"],
			d["data"][character_id]["level"],
		]
		new_button.pressed.connect(_on_character_selected.bind(world_id, character_id.to_int()))
		container.add_child(new_button)
	await get_tree().process_frame
	var child_count: int = container.get_child_count()
	while child_count < 3:
		var new_button: Button = Button.new()
		new_button.custom_minimum_size = Vector2(150, 250)
		new_button.text = "Create New Character"
		container.add_child(new_button)
		new_button.pressed.connect(_on_character_selected.bind(world_id, -1))
		child_count += 1
	popup_panel.hide()
	$CharacterSelection.show()


func _on_character_selected(world_id: int, character_id: int) -> void:
	current_world_id = world_id
	if character_id == -1:
		$CharacterSelection.hide()
		var animated_sprite_2d: AnimatedSprite2D = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer2/CenterContainer/Control/AnimatedSprite2D
		animated_sprite_2d.play(&"run")
		var v_box_container: GridContainer = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer/VBoxContainer/VBoxContainer
		for button: Button in v_box_container.get_children():
			button.pressed.connect(func():
				var sprite = ContentRegistryHub.load_by_slug(&"sprites", button.text.to_lower())
				if not sprite:
					return
				selected_skin = button.text.to_lower()
				animated_sprite_2d.sprite_frames = sprite
				animated_sprite_2d.play(&"run")
			)
		$CharacterCreation.show()
		return
	$CharacterSelection.hide()

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		"http://127.0.0.1:8088/v1/world/enter",
		{"w-id": world_id, "c-id": character_id}
	)
	if d.has("error"):
		return
	world_server.connect_to_server(d["adress"], d["port"], d["token"])
	queue_free.call_deferred()


func _on_create_character_button_pressed() -> void:
	var username_edit: LineEdit = $CharacterCreation/VBoxContainer/VBoxContainer/HBoxContainer2/LineEdit

	var create_button: Button = $CharacterCreation/VBoxContainer/VBoxContainer/CreateButton
	create_button.disabled = true
	
	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayApi.world_create_char(),
		{
			GatewayApi.KEY_TOKEN_ID: token,
			"data": {
				"name": username_edit.text,
				"class": selected_skin,
				
			},
			GatewayApi.KEY_ACCOUNT_USERNAME: account_name,
			GatewayApi.KEY_WORLD_ID: current_world_id
		}
	)
	if d.has("error"):
		return
	world_server.connect_to_server(
		d["data"]["address"],
		d["data"]["port"],
		d["data"]["auth-token"]
	)
	queue_free.call_deferred()


func create_account() -> void:
	var name_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer/LineEdit
	var password_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer2/LineEdit
	var password_repeat_edit: LineEdit = $CreateAccountPanel/VBoxContainer/VBoxContainer/VBoxContainer3/LineEdit

	if password_edit.text != password_repeat_edit.text:
		await popup_panel.confirm_message("Passwords don't match")
		return
	
	var result: Dictionary
	result = CredentialsUtils.validate_username(name_edit.text)
	if result.code != CredentialsUtils.UsernameError.OK:
		await popup_panel.confirm_message("Username:\n" + result.message)
		return
	result = CredentialsUtils.validate_password(password_edit.text)
	if result.code != CredentialsUtils.UsernameError.OK:
		await popup_panel.confirm_message("Password:\n" + result.message)
		return
	
	main_panel.hide()
	$CreateAccountPanel.hide()
	popup_panel.display_waiting_popup()

	var d: Dictionary = await do_request(
		HTTPClient.Method.METHOD_POST,
		GatewayApi.account_create(),
		{"u": name_edit.text, "p": password_edit.text,
		GatewayApi.KEY_TOKEN_ID: token}
	)
	if d.has("error"):
		popup_panel.hide()
		$CreateAccountPanel.show()
		return
	fill_connection_info(d["a"]["name"], d["a"]["id"])
	populate_worlds(d.get("w", {}))
	popup_panel.hide()
	$WorldSelection.show()


func _on_create_account_button_pressed() -> void:
	main_panel.hide()
	$CreateAccountPanel.show()


func populate_worlds(world_info: Dictionary) -> void:
	var container: HBoxContainer = $WorldSelection/VBoxContainer/HBoxContainer
	for child: Node in container.get_children():
			child.queue_free()
	for world_id: String in world_info:
		var new_button: Button = Button.new()
		new_button.custom_minimum_size = Vector2(150, 250)
		new_button.clip_text = true
		new_button.text = "%s\n\n%s" % [
			world_info[world_id].get("name", "name"),
			" \n".join(str(world_info[world_id]["info"]).split(", "))
		]
		new_button.pressed.connect(_on_world_selected.bind(world_id.to_int()))
		container.add_child(new_button)


func fill_connection_info(_account_name: String, _account_id: int) -> void:
	account_name = _account_name
	account_id = _account_id
	$ConnectionInfo.text = "Accout-name: %s\nAccount-ID: %s" % [
		account_name, account_id
	]
