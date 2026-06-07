class_name ChatCommand
extends RefCounted


var command_name: String = ""
var command_alias: PackedStringArray = []
var command_priority: int = 0
## One-line usage string, e.g. "/heal <self|@account|#id> <amount>". Set in
## _init(); commands return it on a malformed call AND /help <name> prints it, so
## the format lives in exactly one place. Empty falls back to "/<name>".
var command_usage: String = ""


@warning_ignore("unused_parameter")
func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	return "Unknown command."


## Parse a duration token like "30s", "10m", "2h", "1d" into milliseconds.
## Returns 0 if the input is empty or has no valid unit suffix — callers use
## that as the "no duration / treat as reason instead" sentinel. Bare numbers
## (no suffix) return 0 on purpose so "/mute 1042 spam" can't be misread as a
## duration when the reason starts with digits.
static func parse_duration_ms(s: String) -> int:
	if s.length() < 2:
		return 0
	var lower: String = s.to_lower()
	var suffix: String = lower.right(1)
	var unit_ms: int = 0
	match suffix:
		"s": unit_ms = 1000
		"m": unit_ms = 60 * 1000
		"h": unit_ms = 60 * 60 * 1000
		"d": unit_ms = 24 * 60 * 60 * 1000
		_: return 0
	var numeric: String = lower.left(lower.length() - 1)
	if not numeric.is_valid_int():
		return 0
	var n: int = numeric.to_int()
	if n <= 0:
		return 0
	return n * unit_ms
