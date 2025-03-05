extends Node

## ANSI color codes
const WHITE: String = "[1;0m"
const DARK_RED: String = "[31m"
const GREEN: String = "[32m"
const DARK_YELLOW: String = "[33m"
const MAGENTA: String = "[35m"

signal stdin_readed

@export var database: WorldDatabase
@export var world_server: WorldServer

var escape: String = PackedByteArray([0x1b]).get_string_from_ascii()

var define_commands: Dictionary = {
	clear_console: ["clear", "clear_console"],
	print_player_count: ["print_player_count", "player_count"],
	shutdown: ["q", "quit", "shutdown", "exit"],
	save: ["save"],
}
var commands: Dictionary = {}

var stdin_thread: Thread
var cmd_begin: String = str("\n" + escape + 
	DARK_YELLOW + "admin@tiny-mmo " + escape + MAGENTA + "EOS " + 
	escape + GREEN + "~" + escape + WHITE + "\n" + "$ ")


func _ready() -> void:
	if not OS.has_feature("console"):
		return
	for callable: Callable in define_commands:
		for keyword: String in define_commands[callable]:
			commands[keyword] = callable
	print_rich(escape + "[2J" + escape + "[;H" + "[color=purple]Tiny MMO's server console:[/color]")
	stdin_readed.connect(self._on_stdin_readed)
	start_read_stdin_thread()


func start_read_stdin_thread() -> bool:
	stdin_thread = Thread.new()
	var _error: Error = stdin_thread.start(read_stdin)
	return _error


func read_stdin() -> String:
	printraw(cmd_begin)
	var buffer: String = OS.read_string_from_stdin(80)
	stdin_readed.emit.call_deferred()
	return buffer


func _on_stdin_readed() -> void:
	var stdin: String
	if stdin_thread.is_started():
		if not stdin_thread.is_alive():
			stdin = stdin_thread.wait_to_finish() as String
			if not stdin.strip_edges(true).is_empty():
				if await execute_command(stdin):
					start_read_stdin_thread()
			else:
				start_read_stdin_thread()


func _exit_tree() -> void:
	if not stdin_thread:
		return
	if stdin_thread.is_started():
		if stdin_thread.is_alive():
			stdin_thread.wait_to_finish()


func execute_command(stdin: String) -> bool:
	var inputs: PackedStringArray
	var command: String
	var to_call: Callable
	
	stdin = stdin.strip_escapes()
	inputs = stdin.split(" ", false)
	command = inputs[0]
	if commands.has(command):
		to_call = commands[command]
	if to_call.is_valid():
		printraw(escape + GREEN)
		if inputs.size() == 2:
			await to_call.call(inputs[1])
		else:
			await to_call.call()
	else:
		print(escape + DARK_RED + "Command doesn't exist.")
	return false if to_call == shutdown else true


func print_player_count() -> void:
	print("Current player connected: %d" % world_server.connected_players.size())


func clear_console() -> void:
	printraw(escape + "[2J")


func save() -> void:
	database.save_world_database()
	print("Saved!")


func shutdown() -> void:
	print("Saving before shutdown.")
	save()
	print("Shutdown server in:")
	print("3")
	await get_tree().create_timer(1.0).timeout
	print("2")
	await get_tree().create_timer(1.0).timeout
	print("1")
	await get_tree().create_timer(1.0).timeout
	print("Server offline.")
	get_tree().quit.call_deferred()
