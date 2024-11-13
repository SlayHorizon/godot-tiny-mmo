class_name LoginMenu
extends Control


@export var gateway: GatewayClient

var selected_world_id: int = 0


func _ready() -> void:
	$Main.show()
	$Login.hide()
	$CreateAccount.hide()
	$ServerSelection.hide()
	$CharacterSelection.hide()
	$CharacterCreation.hide()
	gateway.login_succeeded.connect(on_login_succeeded)
	gateway.connection_changed.connect(_on_gateway_connection_changed)


func on_login_succeeded(account_data: Dictionary, worlds_info: Dictionary) -> void:
	$AccountInfo.set_account_info(account_data)
	$ServerSelection.update_worlds_info(worlds_info)
	$Main.hide()
	$Login.hide()
	$CreateAccount.hide()
	$ServerSelection.show()


func _on_gateway_connection_changed(connection_status: bool) -> void:
	%WaitingConnectionRect.visible = not connection_status
