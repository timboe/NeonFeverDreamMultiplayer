extends Node
class_name AIController

var player_number: int
var timer: Timer

func _init(pnum: int):
	player_number = pnum

func _ready():
	timer = Timer.new()
	timer.wait_time = 1.0 + randf() * 2.0
	timer.timeout.connect(_on_timer)
	add_child(timer)
	timer.start()

func _on_timer():
	var srv = Global.network_manager.server
	if not srv:
		return
	var tm = get_node_or_null("/root/World/TileManager")
	if not tm:
		timer.wait_time = 1.0 + randf() * 2.0
		timer.start()
		return
	var tile_id = randi() % tm.tile_dictionary.size()
	Global.send_command(player_number, "toggle_tile", [tile_id])
	timer.wait_time = 1.0 + randf() * 2.0
	timer.start()
