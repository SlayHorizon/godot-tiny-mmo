class_name AuthenticationManager
extends Node


var account_collection: AccountResourceCollection
## Production path (writable). In an exported build res:// is read-only, so
## ResourceSaver.save() against res:// silently fails and accounts can't
## persist. Mirrors the world-db split: editor reads/writes res://, exports
## live under user://. NO seed fallback — production starts blank by design,
## dev/debug accounts never leak into the live environment.
var account_collection_path: String:
	get:
		if OS.has_feature("editor"):
			return "res://source/server/master/account_collection.tres"
		return "user://master/account_collection.tres"
var active_accounts: Dictionary[StringName, AccountResource]


func _ready() -> void:
	tree_exiting.connect(save_account_collection)
	load_account_collection()


# Consider using more complex and safer token generator for your own project
func generate_random_token() -> String:
	var token_length: int = randi_range(7, 13)
	var characters: String = "abcdefghijklmnopqrstuvwxyz#$-+0123456789"
	var token: String = ""
	for i in range(token_length):
		token += characters[randi()% len(characters)]
	return token


func create_account(username: String, password: String, is_guest: bool) -> AccountResource:
	# Account names are case-insensitive (like Discord) so "John" and "john"
	# can't both exist. Normalize to lowercase before any lookup / storage.
	if not is_guest:
		username = username.strip_edges().to_lower()
	if not is_guest and username_exists(username):
		return null
	var account_id: int = account_collection.get_new_account_id()
	if is_guest:
		username = "guest%d" % account_id
		password = generate_random_token()
	var new_account: AccountResource = AccountResource.new()
	new_account.init(account_id, username, password)
	account_collection.collection[username] = new_account
	# Save on disk should only occur at specific times.
	# Temporary work around for debug purpose.
	save_account_collection()
	return new_account


func load_account_collection() -> void:
	if ResourceLoader.exists(account_collection_path):
		account_collection = ResourceLoader.load(account_collection_path)
	else:
		account_collection = AccountResourceCollection.new()


func save_account_collection() -> void:
	# Ensure user://master/ exists before the first save in an export build.
	if not OS.has_feature("editor"):
		DirAccess.make_dir_recursive_absolute("user://master")
	ResourceSaver.save(account_collection, account_collection_path)


func username_exists(username: String) -> bool:
	return account_collection.collection.has(username.strip_edges().to_lower())


func validate_credentials(username: String, password: String) -> AccountResource:
	# Case-insensitive lookup to match create_account's lowercase normalization.
	username = username.strip_edges().to_lower()
	var account: AccountResource = null
	if account_collection.collection.has(username):
		account = account_collection.collection[username]
		if account.password == password:
			return account
	return null
