class_name LoginMenu
extends Control


func _ready() -> void:
	$Main.show()
	$Login.hide()
	$CreateAccount.hide()
	$WorldSelection.hide()
	$CharacterSelection.hide()
	$CharacterCreation.hide()


func on_login_succeeded(account_data: Dictionary, worlds_info: Dictionary) -> void:
	$AccountInfo.set_account_info(account_data)
	$WorldSelection.update_worlds_info(worlds_info)
	$Main.hide()
	$Login.hide()
	$CreateAccount.hide()
	$WorldSelection.show()


func _on_gateway_connection_changed(connection_status: bool) -> void:
	%WaitingConnectionRect.visible = not connection_status
