class_name SparGameMode
extends Resource
## Game-mode hook for a spar station. The DEFAULT is exactly this base class:
## fighters keep their own stats untouched, and the win condition is the service's
## built-in "last team standing". Subclass + override to build modifiers
## (level-normalized stats, fixed loadouts, ...) or, later, alternate win
## conditions (first blood, point score, timed) — the service calls these hooks,
## so new modes are data: author a resource, assign it on the station.


## Called for each fighter right after the spawn/HP-reset, before the countdown.
## Default: do nothing — players fight with the stats they walked in with.
func apply_to_fighter(_player: Player) -> void:
	pass


## Called for each fighter when the match ends (win, loss, or disconnect sweep).
## Override to revert whatever apply_to_fighter changed. Default: nothing to undo.
func remove_from_fighter(_player: Player) -> void:
	pass
