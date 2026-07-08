extends Node

var network_manager: NetworkManager
var game_config: GameConfig

var LEVEL = load("res://levels/skirmish_01.gd")

@onready var rand = RandomNumberGenerator.new()

var my_player_number: int = -1

func send_command_me(command: String, args: Array):
	send_command(my_player_number, command, args)

func send_command(pnum: int, command: String, args: Array):
	var srv = network_manager.server if network_manager else null
	if srv:
		srv.handle_command(pnum, command, args)
	else:
		rpc_id(1, "_on_remote_command", command, args)

@rpc("any_peer", "call_remote")
func _on_remote_command(command: String, args: Array):
	var caller = multiplayer.get_remote_sender_id()
	var srv = network_manager.server if network_manager else null
	if srv:
		var pnum = srv.peer_to_player.get(caller)
		if pnum != null:
			srv.handle_command(pnum, command, args)

const FLOOR_HEIGHT : float = 20.0 # Visible floor-to-roof of time 
const TILE_OFFSET : float = 1.95 # Tile extends this far below floor level
const GRID_OFFSET : float = 2.0 # Grid is this far below floor level 

# Increasing this will break some things...
const MAX_PLAYERS := 4
