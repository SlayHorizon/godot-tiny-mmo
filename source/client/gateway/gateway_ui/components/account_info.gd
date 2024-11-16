extends VBoxContainer


func set_account_info(account_data: Dictionary) -> void:
	$Label.text = "Account name: %s" % account_data["name"]
	$Label2.text = "Accoount id: %d" % account_data["id"]
