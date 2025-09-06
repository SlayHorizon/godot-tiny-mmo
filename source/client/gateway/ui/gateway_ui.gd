class_name GatewayUI
extends Control


func _ready() -> void:
	%ConnectionStatusRect.show()
	
	$Main.show()
	$Login.hide()
	$CreateAccount.hide()
	$WorldSelection.hide()
	$CharacterSelection.hide()
	$CharacterCreation.hide()


func on_login_succeeded(account_data: Dictionary, worlds_info: Dictionary) -> void:
	%ConnectionStatusRect.hide()
	
	$AccountInfo.set_account_info(account_data)
	$AccountInfo.show()
	
	$WorldSelection.update_worlds_info(worlds_info)
	
	$Main.hide()
	$Login.hide()
	$CreateAccount.hide()
	$WorldSelection.show()


func _on_gateway_connection_changed(connection_status: bool) -> void:
	print("CONNECTION STATUS = ", connection_status)
	%ConnectionStatusRect.visible = not connection_status
	if connection_status:
		$Main.result_label.text = "Connected to gateway."
		$Main.result_label.add_theme_color_override("font_color", Color("00cf00"))
	else:
		%ConnectionStatusLabel.text = "Please retry. If not working contact an admin."
		for i: int in [3, 2, 1]:
			await get_tree().create_timer(1.0).timeout
			%ConnectionStatusButton.text = "Wait %d" % i
		%ConnectionStatusButton.text = "Retry"
		%ConnectionStatusButton.pressed.connect($"../../GatewayClient".start_client, CONNECT_ONE_SHOT)
