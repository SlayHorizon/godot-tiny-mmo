extends GatewayUIComponent


@export var login_menu: Control
@export var create_account_menu: Control

@onready var connect_as_guest_button: Button = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/ConnectAsGuestButton
@onready var result_label: Label = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/ResultLabel


func _ready() -> void:
	await get_node("/root/ClientMain").ready
	gateway.auth_failed.connect(_on_auth_failed)


func _on_auth_failed() -> void:
	hide()
	%ConnectionStatusLabel.text = "Authentication failed.\nPlease ensure your game is updated to the latest version."
	%ConnectionStatusLabel.add_theme_color_override("font_color", Color("de0000"))
	%ConnectionStatusRect.show()


func _on_login_button_pressed() -> void:
	hide()
	login_menu.show()


func _on_create_account_button_pressed() -> void:
	hide()
	create_account_menu.show()


func _on_connect_as_guest_button_pressed() -> void:
	connect_as_guest_button.disabled = true
	hide()
	%ConnectionStatusRect.visible = true
	%ConnectionStatusLabel.text = "Trying to connect as guest..."
	# Await for test purpose
	await get_tree().create_timer(0.5).timeout
	gateway.account_creation_result_received.connect(
		func(result_code: int):
			result_code = 1
			var message := "Connection successful."
			if result_code != OK:
				message = GatewayClient.get_error_message(result_code)
				%ConnectionStatusLabel.text = message
				# Await for test purpose
				await get_tree().create_timer(1.5).timeout
				await %ConnectionStatusButton.pressed
				show()
				connect_as_guest_button.disabled = false
			%ConnectionStatusRect.visible = false,
		ConnectFlags.CONNECT_ONE_SHOT
	)
	gateway.create_account_request.rpc_id(1, "", "", true)
