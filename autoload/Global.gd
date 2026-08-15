extends Node

# --- Constants ---

const MAX_PLAYERS := 4
const FLOOR_HEIGHT: float = 20.0 # Visible floor-to-roof of tile
const TILE_OFFSET: float = 1.95 # Tile extends this far below floor level
const GRID_OFFSET: float = 2.0 # Grid is this far below floor level

# Level registry: menu key -> preloaded level script (a GDScript whose consts
# are the level data — see levels/*.gd). `level` is a var because the chosen
# map is synced at lobby/game start: every peer MUST set Global.level to the
# same entry before World loads or the deterministic tile IDs desync.
const LEVELS := {
	"duel": preload("res://levels/duel.gd"),
	"basin": preload("res://levels/basin.gd"),
	"canyons": preload("res://levels/canyons.gd"),
	"skirmish_01": preload("res://levels/skirmish_01.gd"),
}
const DEFAULT_LEVEL := "duel"
var level = LEVELS[DEFAULT_LEVEL]

func level_name(key: String) -> String:
	if not LEVELS.has(key):
		return "?"
	return String(LEVELS[key].NAME)

func level_max_players(key: String) -> int:
	if not LEVELS.has(key):
		return MAX_PLAYERS
	return int(LEVELS[key].MAX_PLAYERS)

# Menu dropdown label: "Duel (2 player)", "Skirmish (2-3 player)", "(2-4 player)".
func level_label(key: String) -> String:
	var max_p := level_max_players(key)
	if max_p <= 2:
		return level_name(key) + " (2 player)"
	return level_name(key) + " (2-" + str(max_p) + " player)"

func set_level(key: String) -> void:
	if LEVELS.has(key):
		level = LEVELS[key]
	else:
		push_warning("Global.set_level: unknown level '", key, "' — falling back to '", DEFAULT_LEVEL, "'")
		level = LEVELS[DEFAULT_LEVEL]

# --- Manager references ---
# Each manager registers itself in its _ready(). Null until World is loaded.

var GM: GameManager = null
var BM: BuildingManager = null
var EM: EnergyManager = null
var TM: TileManager = null
var UM: UnitManager = null
var JM: JobManager = null
var CM: CombatManager = null
var VM: VideoManager = null
var SM: StatisticsManager = null
var PM: PathingManager = null
var NM: NotificationManager = null

# --- State ---

# False until every peer has loaded the World and the server signals game_start.
var game_started: bool = false

@onready var rand := RandomNumberGenerator.new()

# --- Network ---

var network_manager: NetworkManager
var game_config: GameConfig
var my_player_number: int = -1

func get_server() -> Server:
	if network_manager:
		return network_manager.server
	return null

# Whether the statistics window is open. The modal also blocks 3D-world input
# (CameraRTS, tile picking) which Control mouse_filter can't reach.
func stats_window_open() -> bool:
	var sw = get_tree().get_first_node_in_group("statistics_window")
	return sw != null and sw.visible

# Tear down the network session and return to the main menu. Used by the Lobby
# back button and by the end-of-game flow (statistics window dismissal). The
# host's server may close before its clients disconnect — stop() closes both
# peer types, and network_manager is nulled first so any signal re-entry
# (e.g. server_disconnected fired by our own peer close) no-ops.
func leave_game() -> void:
	var nm := network_manager
	network_manager = null
	if nm:
		if nm.server:
			nm.server.accepting_clients = false
		nm.stop()
		nm.queue_free()
	my_player_number = -1
	# A client can be in FPS (MOUSE_MODE_CAPTURED) when the host quits — the
	# menu must never render with a hidden/locked cursor.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")

func send_command_me(command: String, args: Array) -> void:
	if my_player_number < 0:
		return
	send_command(my_player_number, command, args)

func send_command(pnum: int, command: String, args: Array) -> void:
	var srv := get_server()
	if srv:
		srv.handle_command(pnum, command, args)
	else:
		rpc_id(1, "_on_remote_command", command, args)

@rpc("any_peer", "call_remote")
func _on_remote_command(command: String, args: Array) -> void:
	var caller := multiplayer.get_remote_sender_id()
	var srv := get_server()
	if srv:
		var pnum = srv.peer_to_player.get(caller)
		if pnum != null:
			srv.handle_command(pnum, command, args)
