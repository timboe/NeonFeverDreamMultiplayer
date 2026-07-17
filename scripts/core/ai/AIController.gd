extends Node
class_name AIController

var player_number: int
var timer: Timer

func _init(pnum: int) -> void:
	player_number = pnum

func _ready() -> void:
	timer = Timer.new()
	timer.timeout.connect(_on_timer)
	add_child(timer)
	_restart_timer()

func _on_timer() -> void:
	var srv = Global.network_manager.server
	if not srv:
		_restart_timer()
		return
	var tm = get_node_or_null("%TileManager")
	if not tm:
		_restart_timer()
		return
	var interactive: Array = get_tree().get_nodes_in_group("interactive")
	if interactive.is_empty():
		_restart_timer()
		return
	var tile: TileElement = interactive.pick_random()
	Global.send_command(player_number, "toggle_tile", [tile.get_id()])
	_restart_timer()

func _restart_timer() -> void:
	timer.start(1.0 + randf() * 2.0)
