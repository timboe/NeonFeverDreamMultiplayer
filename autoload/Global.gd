extends Node

const MAX_PLAYERS := 4
const FLOOR_HEIGHT: float = 20.0 # Visible floor-to-roof of tile
const TILE_OFFSET: float = 1.95 # Tile extends this far below floor level
const GRID_OFFSET: float = 2.0 # Grid is this far below floor level
const level = preload("res://levels/skirmish_01.gd")

var network_manager: NetworkManager
var game_config: GameConfig
var my_player_number: int = -1

@onready var rand := RandomNumberGenerator.new()

func _get_server() -> Server:
	if network_manager:
		return network_manager.server
	return null

func send_command_me(command: String, args: Array) -> void:
	send_command(my_player_number, command, args)

func send_command(pnum: int, command: String, args: Array) -> void:
	var srv := _get_server()
	if srv:
		srv.handle_command(pnum, command, args)
	else:
		rpc_id(1, "_on_remote_command", command, args)

@rpc("any_peer", "call_remote")
func _on_remote_command(command: String, args: Array) -> void:
	var caller := multiplayer.get_remote_sender_id()
	var srv := _get_server()
	if srv:
		var pnum = srv.peer_to_player.get(caller)
		if pnum != null:
			srv.handle_command(pnum, command, args)
