class_name LoginMenu
extends Control


const GatewayClient = preload("res://source/client/network/gateway_client.gd")

signal connection_succeed

var username := ""
var password := ""
var selected_world_id: int = 0
var gateway: GatewayClient


func _ready() -> void:
	$Main.show()
	$ServerSelection.hide()
	$CharacterSelection.hide()
	$CharacterCreation.hide()
	
	await get_tree().create_timer(1.0).timeout
	
	gateway = GatewayClient.new()
	gateway.name = "GatewayServer"
	gateway.connection_changed.connect(_on_gateway_connection_changed)
	get_node("/root").add_child(gateway, true)
	#gateway.connect_to_gateway()


func _on_gateway_connection_changed(connection_status: bool) -> void:
	$Main/CenterContainer/MainContainer/WaitingConnectionRect.visible = not connection_status


func _on_connection_changed(connection_status: bool) -> void:
	if connection_status:
		%ServerStatusLabel.text = "Connected to the server!"
		%LoginButton.disabled = true
		connection_succeed.emit()
	else:
		%ServerStatusLabel.text = "Authentication failed.\nEnter a correct name and choose a class."
		await get_tree().create_timer(1.2).timeout
		%LoginButton.disabled = false


func _on_connect_as_guest_button_pressed() -> void:
	%ConnectAsGuestButton.disabled = true
	gateway.account_creation_result_received.connect(
		func(result_code: int):
			var message := "Creation successful."
			if result_code != OK:
				message = get_error_message(result_code)
			$Main/CenterContainer/MainContainer/MarginContainer/HBoxContainer/Label.text = message
			await get_tree().create_timer(0.5).timeout
			if result_code == OK:
				$Main.hide()
				$ServerSelection.show()
			else:
				%ConnectAsGuestButton.disabled = false,
		ConnectFlags.CONNECT_ONE_SHOT
	)
	gateway.create_account_request.rpc_id(1, username, password, true)


func _on_create_character_button_pressed() -> void:
	var create_button := $CharacterCreation/CenterContainer/VBoxContainer/CreateCharacterButton
	var result_label := $CharacterCreation/CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer2/ResultMessageLabel
	var line_edit := $CharacterCreation/CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer2/HBoxContainer/LineEdit
	create_button.disabled = true
	gateway.player_character_creation_result_received.connect(
		func(result_code: int):
			var message := "Creation successful."
			if result_code != OK:
				message = get_error_message(result_code)
			result_label.text = message
			await get_tree().create_timer(0.5).timeout
			if result_code == OK:
				connection_succeed.emit()
			else:
				create_button.disabled = false,
		ConnectFlags.CONNECT_ONE_SHOT
	)
	gateway.create_player_character_request.rpc_id(
		1,
		{
			"name": line_edit.text,
			"class": $CharacterCreation.character_class
		},
		selected_world_id
	)


func get_error_message(error_code: int) -> String:
	var message := ""
	if error_code == 1:
		message = "Username cannot be empty."
	elif error_code == 2:
		message = "Username too short. Minimum 3 characters."
	elif error_code == 3:
		message = "Username too long. Maximum 12 characters."
	elif error_code == 4:
		message = "Password cannot be empty."
	elif error_code == 5:
		message = "Password too short. Minimum 6 characters."
	elif error_code == 6:
		message = "Password too long. Max 30 characters."
	elif error_code == 7:
		message = "Please create an account first."
	elif error_code == 8:
		message = "Wrong class. Please choose a valid class."
	elif error_code == 9:
		message = "Invalid data format received."
	return message


func _on_confirm_server_button_pressed() -> void:
	$ServerSelection.hide()
	$CharacterSelection.show()


func _on_character_slot_button_pressed() -> void:
	$CharacterSelection.hide()
	$CharacterCreation.show()
