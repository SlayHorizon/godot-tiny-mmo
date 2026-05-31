class_name AccountResourceCollection
extends Resource


@export var collection: Dictionary[StringName, AccountResource]

## Starts at 2 so the first account never claims id=1 — that value collides
## with the server's authoritative Godot-multiplayer peer_id, which the chat
## (and other systems) treat as "system / server" speaker. Reserving 1 keeps
## that semantics clean.
@export var next_account_id: int = 2


func get_new_account_id() -> int:
	var new_account_id: int = next_account_id
	next_account_id += 1
	return new_account_id
