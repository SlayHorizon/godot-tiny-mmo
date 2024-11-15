class_name MasterDatabase
extends Node


var account_collection: AccountResourceCollection
var account_collection_path := "res://source/master_server/account_collection.tres"


func _ready() -> void:
	load_account_collection()


func load_account_collection() -> void:
	if ResourceLoader.exists(account_collection_path):
		account_collection = ResourceLoader.load(account_collection_path)
	else:
		account_collection = AccountResourceCollection.new()


func username_exists(username: String) -> bool:
	if account_collection.collection.has(username):
		return true
	return false


func validate_credentials(username: String, password: String) -> AccountResource:
	var account: AccountResource = null
	if account_collection.collection.has(username):
		account = account_collection.collection[username]
		if account.password == password:
			return account
	return null
