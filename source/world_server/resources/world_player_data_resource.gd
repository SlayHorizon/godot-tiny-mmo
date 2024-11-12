class_name WorldPlayerDataResource
extends Resource


# account = {account_id: [player_id1, player_id2]}
@export var accounts: Dictionary#[String, Array[int]]
@export var max_character_per_account: int = 3

@export var players: Dictionary#[int, PlayerResource]
@export var next_player_id: int = 0:
	get():
		next_player_id += 1
		return next_player_id


func get_player_resource(player_id: int) -> PlayerResource:
	if players.has(player_id):
		return players[player_id]
	return null


func create_player_character(username: String, character_data: Dictionary) -> int:
	if (
		accounts.has(username)
		and accounts[username].size() > max_character_per_account
	):
		return -1
	
	var player_id := next_player_id
	var player_character := PlayerResource.new(
		player_id, username,
		character_data["name"], character_data["class"]
	)
	players[player_id] = player_character
	if accounts.has(username):
		accounts[username].append(player_id)
	else:
		accounts[username] = [player_id]
	return player_id


func get_account_characters(account_name: String) -> Dictionary:
	var data := {}
	if accounts.has(account_name):
		for player_id: int in accounts[account_name]:
			var player_character := get_player_resource(player_id)
			if player_character:
				data[player_id] = {
					"name": player_character.display_name,
					"class": player_character.character_class,
					"level": player_character.level
				}
	return data
