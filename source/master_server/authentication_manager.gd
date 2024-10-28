extends Node


# Class Dependencies
const Database: Script = preload("res://source/master_server/database.gd")

# References
var database: Database


func _ready() -> void:
	pass


# Consider using a better token generator.
func generate_random_token() -> String:
	var characters := "abcdefghijklmnopqrstuvwxyz#$-+0123456789"
	var password := ""
	for i in range(12):
		password += characters[randi()% len(characters)]
	return password


func create_accout(username: String, password: String, is_guest: bool) -> AccountResource:
	if not is_guest and database.username_exists(username):
		return null
	var account_id: int = database.account_collection.next_account_id
	if is_guest:
		username = "guest%d" % account_id
		password = generate_random_token()
	var new_account := AccountResource.new(account_id, username, password)
	database.account_collection.collection[username] = new_account
	return new_account
