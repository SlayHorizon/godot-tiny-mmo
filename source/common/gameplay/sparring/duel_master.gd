class_name DuelMaster
extends Interactable
## Clickable spar STATION. Its teams are SparTeam child nodes, and each team's
## Marker2D children are its spawn slots — so the station's shape is authored
## entirely in the editor: two SparTeams with 1 marker each = 1v1; 2+2 = 2v2;
## 1+3 = 1v3; three SparTeams = a three-way. (The named "Duel Master" NPC who
## introduces the arena is a separate regular NPC; this node is purely the
## queue mechanic.)
##
## Setup: place as a direct child of a Map; give it a unique master_id and a
## CollisionShape2D (the click target); add SparTeam children, each with its
## spawn Marker2Ds inside the arena. The station's own position is the return
## point after the match. Optional: fight_zone (leaving it mid-match = instant
## loss) and game_mode (stat modifiers / future win conditions; null = default
## "keep your stats, last team standing").

@export var master_id: int = 0
## Shown as the lobby title (e.g. "Duel Arena", "2v2 Arena").
@export var master_name: String = "Duel Arena"
## Optional Area2D enclosing the arena interior. If wired, a fighter who leaves
## the zone mid-match instantly loses (anti-exploit).
@export var fight_zone: Area2D
## Optional mode hook (stat modifiers etc.). Null = SparGameMode defaults.
@export var game_mode: SparGameMode


func _ready() -> void:
	menu_name = &"sparring"
	menu_arg = master_id
	super._ready()
	if master_id <= 0:
		push_warning("DuelMaster '%s' has master_id=%d. Set a unique positive id in the inspector or it'll fail every lookup." % [name, master_id])
	if multiplayer.is_server() and teams().size() < 2:
		push_warning("DuelMaster '%s' has %d usable team(s) — add SparTeam children with at least one Marker2D each." % [name, teams().size()])


## Usable teams, in child order. A SparTeam with no Marker2D children can never
## fill, so it's skipped (with a warning at ready-time server-side).
func teams() -> Array[SparTeam]:
	var out: Array[SparTeam] = []
	for child: Node in get_children():
		if child is SparTeam and (child as SparTeam).capacity() > 0:
			out.append(child)
	return out
