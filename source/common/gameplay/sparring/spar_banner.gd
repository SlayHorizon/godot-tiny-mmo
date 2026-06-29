class_name SparBanner
extends RichTextLabel
## A world-placed arena banner showing the live matchup ("A vs B") for ONE DuelMaster station while
## a spar runs, then clearing when it ends. Server-driven via the sparring.match.banner push, which
## is broadcast to the WHOLE instance — so onlookers read it too, not just the fighters. Place a
## RichTextLabel near the station, attach this script, and set [member master_id] to that station's id.

## The DuelMaster station id this banner mirrors. Match it to that station's master_id.
@export var master_id: int = 0

## Per-side colors for the styled "A vs B" (team 0, team 1, then cycling), as bare hex (no '#').
const SIDE_COLORS: PackedStringArray = ["f2bd2a", "73b3ff"]
## Winner color (bare hex) for the post-match "A wins!" line.
const WIN_COLOR: String = "ffd54a"


func _ready() -> void:
	if multiplayer.is_server():
		return # display-only; nothing to wire on the headless server
	bbcode_enabled = true
	visible = false
	text = ""
	Client.subscribe(&"sparring.match.banner", _on_banner)


func _exit_tree() -> void:
	if multiplayer.is_server():
		return
	Client.unsubscribe(&"sparring.match.banner", _on_banner)


## Update THIS station's board: the live "A vs B" at match start, then "A wins!" / "Draw" at match
## end — which STAYS up until the next match's matchup replaces it. Ignores other stations' pushes.
func _on_banner(payload: Dictionary) -> void:
	if int(payload.get("master_id", -1)) != master_id:
		return
	var display: String = ""
	match str(payload.get("kind", "")):
		"matchup":
			display = _format_matchup(payload.get("teams", []))
		"result":
			display = _format_result(payload.get("winners", []), bool(payload.get("draw", false)))
	if display.is_empty():
		return # unknown kind or no data — leave the board as-is
	text = display
	visible = true


## "[b][color]A & B[/color][/b]  vs  [color]C & D[/color]…" from the per-team name arrays.
func _format_matchup(teams: Array) -> String:
	var sides: PackedStringArray = []
	for i: int in teams.size():
		var color: String = SIDE_COLORS[i % SIDE_COLORS.size()]
		sides.append("[b][color=#%s]%s[/color][/b]" % [color, " & ".join(teams[i] as Array)])
	return "  [color=#888888]vs[/color]  ".join(sides)


## "[b]A & B[/b] win!" (gold) or "Draw" (grey) — the post-match result line.
func _format_result(winners: Array, draw: bool) -> String:
	if draw:
		return "[color=#cccccc]Draw[/color]"
	if winners.is_empty():
		return ""
	var verb: String = "win" if winners.size() > 1 else "wins"
	return "[b][color=#%s]%s[/color][/b] %s!" % [WIN_COLOR, " & ".join(winners as Array), verb]
