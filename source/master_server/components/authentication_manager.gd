class_name AuthenticationManager
extends Node


@export var database: MasterDatabase


func _ready() -> void:
	pass


# TODO: Consider using a real authentication auth_token generator.
func generate_random_token() -> String:
	var characters :String = "abcdefghijklmnopqrstuvwxyz#$-+0123456789"
	var password :String = ""
	for i in range(12):
		password += characters[randi()% len(characters)]
	return password


func create_account(username: String, password: String, is_guest: bool) -> AccountResource:
	if not is_guest and database.username_exists(username):
		return null
	var account_id: int = database.account_collection.next_account_id
	if is_guest:
		username = "guest%d" % account_id
		password = generate_random_token()
	var new_account: AccountResource = AccountResource.new()
	new_account.init(account_id, username, password)
	database.account_collection.collection[username] = new_account
	print("Account created: " + str(database.account_collection.collection[username]))
	ResourceSaver.save(database.account_collection, database.account_collection_path)
	return new_account
