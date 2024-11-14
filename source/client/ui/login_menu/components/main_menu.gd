extends Control


@export var login_menu: Control
@export var create_account_menu: Control

@onready var connect_as_guest_button: Button = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/ConnectAsGuestButton
@onready var result_label: Label = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/ResultLabel


func _on_login_button_pressed() -> void:
	hide()
	login_menu.show()


func _on_create_account_button_pressed() -> void:
	hide()
	create_account_menu.show()


func _on_connect_as_guest_button_pressed() -> void:
	connect_as_guest_button.disabled = true
	GatewayClient.gateway.account_creation_result_received.connect(
		func(result_code: int):
			var message := "Creation successful."
			if result_code != OK:
				message = GatewayClient.get_error_message(result_code)
			result_label.text = message
			await get_tree().create_timer(0.5).timeout
			%WaitingConnectionRect.visible = false,
		ConnectFlags.CONNECT_ONE_SHOT
	)
	GatewayClient.gateway.create_account_request.rpc_id(1, "", "", true)
