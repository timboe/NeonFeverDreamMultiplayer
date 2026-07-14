extends Control
class_name Lobby

@onready var slot_container: VBoxContainer = $VBoxContainer/SlotContainer
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var back_button: Button = $VBoxContainer/BackButton

var remote_needed: int = 0
var slot_labels: Array[Label] = []

func _ready():
	if Global.network_manager.server:
		_setup_host()
	else:
		_setup_client()

func _setup_host():
	var config = Global.network_manager.config
	var slots = config.slots

	for i in range(slots.size()):
		var slot_type = slots[i]
		var label = Label.new()
		var text = "P" + str(i + 1) + ": "
		match slot_type:
			GameConfig.SlotType.LOCAL:
				text += "Host"
			GameConfig.SlotType.REMOTE:
				text += "Remote (waiting)"
				remote_needed += 1
			GameConfig.SlotType.AI:
				text += "AI"
			GameConfig.SlotType.CLOSED:
				text += "Closed"
		label.text = text
		slot_container.add_child(label)
		slot_labels.append(label)

	if remote_needed == 0:
		_start_game()
		return

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	back_button.pressed.connect(_on_back)
	_update_status()

func _setup_client():
	status_label.text = "Connected. Waiting for host to start the game..."
	back_button.pressed.connect(_on_back)

func _on_peer_connected(_peer_id: int):
	_update_status()

func _on_peer_disconnected(_peer_id: int):
	_update_status()

func _update_status():
	var srv = Global.network_manager.server
	if not srv:
		return
	var connected = srv.peer_to_player.size()
	status_label.text = str(connected) + " / " + str(remote_needed) + " remote players connected"

	var remote_idx = 0
	for i in range(slot_labels.size()):
		var slot_type = Global.network_manager.config.slots[i]
		if slot_type == GameConfig.SlotType.REMOTE:
			if remote_idx < connected:
				slot_labels[i].text = "P" + str(i + 1) + ": Remote (connected)"
			else:
				slot_labels[i].text = "P" + str(i + 1) + ": Remote (waiting)"
			remote_idx += 1

	if connected >= remote_needed:
		_start_game()

func _start_game():
	# Called on the host when all remote slots are filled.
	# Broadcasts the transition RPC, then transitions locally.
	if Global.network_manager.server:
		if multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.disconnect(_on_peer_connected)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
		rpc("remote_start_game")
	get_tree().change_scene_to_file("res://scenes/world/World.tscn")

@rpc("authority", "call_remote")
func remote_start_game():
	# Executed on each remote client when the host starts the game.
	get_tree().change_scene_to_file("res://scenes/world/World.tscn")

func _on_back():
	if Global.network_manager:
		Global.network_manager.stop()
		Global.network_manager.queue_free()
		Global.network_manager = null
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
