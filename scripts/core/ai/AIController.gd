extends Node
class_name AIController

# Present on the host machine only (child of a LocalClient with is_ai=true).
# Operates identically to HumanController except the trigger is a timer
# instead of mouse input. Calls the same Server._handle_toggle_cell()
# entry point, making AI behaviourally equivalent to a human player
# from the server's perspective.

var timer: Timer

func _ready():
	timer = Timer.new()
	timer.wait_time = 1.0 + randf() * 2.0
	timer.timeout.connect(_on_timer)
	add_child(timer)
	timer.start()

func _on_timer():
	var client = get_parent() as LocalClient
	if not client:
		return
	var srv = Global.network_manager.server
	if not srv:
		return
	# Don't act during lobby — the World scene and its GameGrid don't exist yet
	if not srv.get_node_or_null("/root/World/GameGrid"):
		timer.wait_time = 1.0 + randf() * 2.0
		timer.start()
		return
	var x = randi() % 32
	var z = randi() % 32
	srv._handle_toggle_cell(client.player_number, x, z)
	timer.wait_time = 1.0 + randf() * 2.0
	timer.start()
