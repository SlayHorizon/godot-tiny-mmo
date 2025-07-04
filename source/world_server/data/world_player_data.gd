class_name WorldPlayerData
extends Resource
# I can't recommend using Resource as a whole database, but for the demonstration,
# I found it interesting to use Godot exclusively to have a minimal setup.

## Suppose to store the different character IDs of registered accounts.[br][br]
## So if player with name ID "horizon" login to this world,
## we can retrieve its different character IDs thanks to this.[br][br]
## Here is how it should look like:
## [codeblock]
## print(accounts) # {"horizon": [6, 14], "another_guy": [2]}
## [/codeblock]
@export var accounts: Dictionary[String, PackedInt32Array]
@export var max_character_per_account: int = 3

@export var players: Dictionary[int, PlayerResource]
@export var next_player_id: int = 0

@export var admin_ids: PackedInt32Array

@export var guilds: Dictionary[String, Guild]


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
	
	next_player_id += 1
	var player_id: int = next_player_id
	var player_character := PlayerResource.new()
	player_character.init(
		player_id, username,
		character_data["name"], character_data["class"]
	)
	players[player_id] = player_character
	if accounts.has(username):
		accounts[username].append(player_id)
	else:
		accounts[username] = [player_id] as PackedInt32Array
	return player_id


func get_account_characters(account_name: String) -> Dictionary:
	var data: Dictionary#[int, Dictionary]
	
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


func create_guild(guild_name: String, player_id: int) -> bool:
	var player: PlayerResource = players.get(player_id)
	if not player or guilds.has(guild_name):
		return false
	var new_guild: Guild = Guild.new()
	new_guild.leader_id = player_id
	new_guild.guild_name = guild_name
	new_guild.add_member(player_id, "Leader")
	guilds[guild_name] = new_guild
	return true
