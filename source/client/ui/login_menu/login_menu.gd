class_name LoginMenu
extends Control


signal connection_succeed

var username := ""
var password := ""
var gateway: GatewayConnect

func _ready() -> void:
	%MainContainer.show()
	%GuestContainer.hide()
	%ChooseClassContainer.hide()
	#Client.connection_changed.connect(self._on_connection_changed)
	await get_tree().create_timer(0.5).timeout
	gateway = GatewayConnect.new()
	gateway.name = "GatewayServer"
	gateway.connection_changed.connect(_on_gateway_connection_changed)
	get_node("/root").add_child(gateway, true)
	gateway.connect_to_gateway()


func _on_gateway_connection_changed(connection_status: bool) -> void:
	%WaitingConnectionRect.visible = not connection_status


func _on_connection_changed(connection_status: bool) -> void:
	if connection_status:
		%ServerStatusLabel.text = "Connected to the server!"
		%LoginButton.disabled = true
		connection_succeed.emit()
	else:
		%ServerStatusLabel.text = "Authentication failed.\nEnter a correct name and choose a class."
		await get_tree().create_timer(1.2).timeout
		%LoginButton.disabled = false


#func _on_login_button_pressed() -> void:
	#%LoginButton.disabled = true
	#Client.authentication_data = {
		#"username": %EnterNameInput.text,
		#"class": player_class
	#}
	#Client.connect_to_server()


func _on_connect_as_guest_button_pressed() -> void:
	%MainContainer.hide()
	%GuestContainer.show()


func _on_guest_back_button_pressed() -> void:
	%MainContainer.show()
	%GuestContainer.hide()


func _on_guest_login_button_pressed() -> void:
	%GuestLoginButton.disabled = true
	%GuestBackButton.disabled = true
	username = %EnterNameInput.text
	gateway.account_creation_result_received.connect(
		func(result: bool, message: String):
			%ServerStatusLabel.text = message
			await get_tree().create_timer(0.5).timeout
			if result:
				%GuestContainer.hide()
				%ChooseClassContainer.show()
			else:
				%GuestLoginButton.disabled = false
				%GuestBackButton.disabled = false,
		ConnectFlags.CONNECT_ONE_SHOT
	)
	gateway.create_account_request.rpc_id(1, username, password, true)


func _on_class_button_pressed() -> void:
	%ClassButton.disabled = true
	gateway.player_creation_result_received.connect(
		func(result: bool, message: String):
			%ClassLabel.text = message
			await get_tree().create_timer(0.5).timeout
			if result:
				connection_succeed.emit()
			else:
				%ClassButton.disabled = true,
		ConnectFlags.CONNECT_ONE_SHOT
	)
	gateway.create_player_request.rpc_id(1, %ChooseClassContainer.player_class)
