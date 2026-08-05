extends Control
class_name Lobby

@onready var slot_container: VBoxContainer = $VBoxContainer/SlotContainer
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var back_button: Button = $VBoxContainer/BackButton

var remote_needed: int = 0
var slot_labels: Array[Label] = []

func _ready():
	UiFX.apply_menu_backdrop($Background)
	if Global.network_manager.server:
		_setup_host()
	else:
		_setup_client()

func _setup_host():
	var config = Global.network_manager.config
	_populate_slots(config.slots, 0)

	if remote_needed == 0:
		_start_game()
		return

	Global.network_manager.server.accepting_clients = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	back_button.pressed.connect(_on_back)
	_update_status()

func _setup_client():
	status_label.text = "Connected. Waiting for host to start the game..."
	back_button.pressed.connect(_on_back)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Ask the host for the current lobby state (in case we missed the broadcast).
	rpc_id(1, "request_lobby_state")

func _on_server_disconnected():
	status_label.text = "Disconnected from host."

# Host only: a client asked for the current lobby state — reply just to them.
@rpc("any_peer", "call_remote")
func request_lobby_state() -> void:
	var srv = Global.network_manager.server
	if not srv:
		return
	var caller := multiplayer.get_remote_sender_id()
	rpc_id(caller, "rpc_receive_lobby_state", Global.network_manager.config.slots, srv.peer_to_player.size())

func _on_peer_connected(_peer_id: int):
	call_deferred("_update_status")

func _on_peer_disconnected(_peer_id: int):
	_update_status()

func _update_status():
	var srv = Global.network_manager.server
	if not srv:
		return
	var connected = srv.peer_to_player.size()
	_populate_slots(Global.network_manager.config.slots, connected)
	status_label.text = str(connected) + " / " + str(remote_needed) + " remote players connected"
	_broadcast_state()
	if connected >= remote_needed:
		_start_game()

# Builds/updates the slot labels. Used by the host locally and by clients via
# rpc_receive_lobby_state. Labels are created once and their text updated.
func _populate_slots(slots: Array, connected_remote: int) -> void:
	while slot_labels.size() < slots.size():
		var label := Label.new()
		slot_container.add_child(label)
		slot_labels.append(label)
	remote_needed = 0
	var remote_idx := 0
	for i in range(slots.size()):
		var text := "P" + str(i + 1) + ": "
		var slot_type = slots[i] as GameConfig.SlotType
		match slot_type:
			GameConfig.SlotType.LOCAL:
				text += "Host"
			GameConfig.SlotType.REMOTE:
				remote_needed += 1
				text += "Remote (connected)" if remote_idx < connected_remote else "Remote (waiting)"
				remote_idx += 1
			GameConfig.SlotType.AI:
				text += "AI"
			GameConfig.SlotType.CLOSED:
				text += "Closed"
		slot_labels[i].text = text

# Host only: push the current lobby state out to connected clients.
func _broadcast_state() -> void:
	var srv = Global.network_manager.server
	if not srv:
		return
	rpc("rpc_receive_lobby_state", Global.network_manager.config.slots, srv.peer_to_player.size())

@rpc("authority", "call_remote", "reliable")
func rpc_receive_lobby_state(slots: Array, connected_remote: int) -> void:
	_populate_slots(slots, connected_remote)
	status_label.text = str(connected_remote) + " / " + str(remote_needed) + " remote players connected"

func _start_game():
	# Called on the host when all remote slots are filled.
	# Broadcasts the transition RPC, then transitions locally.
	if Global.network_manager.server:
		Global.network_manager.server.accepting_clients = false
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
		if Global.network_manager.server:
			Global.network_manager.server.accepting_clients = false
		Global.network_manager.stop()
		Global.network_manager.queue_free()
		Global.network_manager = null
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")
