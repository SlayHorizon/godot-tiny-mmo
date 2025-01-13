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
	%ConnectionStatusRect.visible = not connection_status
	if connection_status:
		$Main.result_label.text = "Connected to gateway."
		$Main.result_label.add_theme_color_override("font_color", Color("00cf00"))
