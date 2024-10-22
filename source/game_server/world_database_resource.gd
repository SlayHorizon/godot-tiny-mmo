extends Resource


# account = {account_id: [player_id1, player_id2]}
@export var accounts: Dictionary#[int, Array[int]]
@export var players: Dictionary#[int, PlayerResource]
