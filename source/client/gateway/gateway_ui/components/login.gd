extends GatewayUIComponent


@export var previous_menu: Control

@onready var account_name_edit: LineEdit = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/VBoxContainer/LineEdit
@onready var password_edit: LineEdit = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/VBoxContainer2/LineEdit

@onready var result_label: Label = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/ResultLabel

@onready var login_button: Button = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/LoginButton
@onready var back_button: Button = $CenterContainer/MainContainer/MarginContainer/HBoxContainer/BackButton


func _on_login_button_pressed() -> void:
	var account_name: String = account_name_edit.text
	var password: String = password_edit.text
	
	 # More checks can be done with specific message
	set_disable_state(true)
	if (
		account_name.length() > 3 and account_name.length() < 12
		and password.length() > 5 and password.length() < 20
	):
		result_label.text = "..."
		gateway.login_request.rpc_id(
			1, account_name, password
		)
		gateway.login_result_received.connect(
			func(result_code: int):
				if result_code != OK:
					result_label.text = GatewayClient.get_error_message(result_code)
					delay_disable_state(false)
				else:
					result_label.text = "Login successful.",
			ConnectFlags.CONNECT_ONE_SHOT
		)
	else:
		result_label.text = "Invalid input."
		delay_disable_state(false)


func _on_back_button_pressed() -> void:
	hide()
	previous_menu.show()


func delay_disable_state(disable: bool) -> void:
	get_tree().create_timer(3.0).timeout.connect(
		func():
			set_disable_state(disable)
	)


func set_disable_state(disable: bool) -> void:
	login_button.disabled = disable
	back_button.disabled = disable
