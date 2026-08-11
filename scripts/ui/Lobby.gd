extends Control
class_name Lobby

@onready var slot_container: VBoxContainer = $VBoxContainer/SlotContainer
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var back_button: Button = $VBoxContainer/BackButton

var remote_needed: int = 0
var slot_labels: Array[Label] = []
var _started: bool = false
# Peers that have confirmed they're inside the Lobby scene (rpc_client_lobby_ready).
# The host waits for every connected client to report ready before broadcasting
# state or starting the game — otherwise lobby RPCs target /root/Lobby on a peer
# that hasn't loaded (or has already left) the scene.
var _ready_peers: Dictionary = {}
var _lobby_wait_timer: Timer
const LOBBY_WAIT_TIMEOUT: float = 10.0

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
	# Soft-lock fallback: if a connected client never reports lobby-ready, the
	# host force-starts after LOBBY_WAIT_TIMEOUT instead of waiting forever.
	_lobby_wait_timer = Timer.new()
	_lobby_wait_timer.one_shot = true
	_lobby_wait_timer.wait_time = LOBBY_WAIT_TIMEOUT
	_lobby_wait_timer.timeout.connect(_on_lobby_wait_timeout)
	add_child(_lobby_wait_timer)
	_update_status()

func _setup_client():
	status_label.text = "Connected. Waiting for host to start the game..."
	back_button.pressed.connect(_on_back)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# Ask the host for the current lobby state (in case we missed the broadcast).
	rpc_id(1, "rpc_request_lobby_state")
	# Confirm we're inside the Lobby scene — the host won't broadcast state or
	# start the game until every connected client has reported ready.
	rpc_id(1, "rpc_client_lobby_ready")
	# The server assigned our player number at connect (set_my_player_number
	# RPC) — surface it once it arrives so the client can verify their slot.
	_poll_client_player_number.call_deferred()

func _poll_client_player_number() -> void:
	if Global.my_player_number >= 0:
		status_label.text = "You are Player %d. Connected. Waiting for host to start the game..." % Global.my_player_number
		return
	if multiplayer.multiplayer_peer == null:
		return
	var t := get_tree().create_timer(0.2)
	t.timeout.connect(_poll_client_player_number)

# Host only: a client has finished loading the Lobby scene. The host may now
# broadcast state / start the game safely — every lobby RPC will find the
# sender's Lobby node.
@rpc("any_peer", "call_remote", "reliable")
func rpc_client_lobby_ready() -> void:
	var srv = Global.network_manager.server
	if not srv:
		return
	var peer := multiplayer.get_remote_sender_id()
	_ready_peers[peer] = true
	_update_status()

func _on_server_disconnected():
	status_label.text = "Disconnected from host."

# Host only: a client asked for the current lobby state — reply just to them.
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_lobby_state() -> void:
	var srv = Global.network_manager.server
	if not srv:
		return
	var caller := multiplayer.get_remote_sender_id()
	rpc_id(caller, "rpc_receive_lobby_state", Global.network_manager.config.slots, srv.peer_to_player.size())

func _on_peer_connected(_peer_id: int):
	# Arm the fallback in case this client never reports lobby-ready.
	if _lobby_wait_timer and _lobby_wait_timer.is_stopped():
		_lobby_wait_timer.start()
	call_deferred("_update_status")

func _on_peer_disconnected(peer_id: int):
	_ready_peers.erase(peer_id)
	_update_status()

func _on_lobby_wait_timeout() -> void:
	# Force-proceed past clients that never reported lobby-ready (dropped
	# reliable RPC or a broken client) — the GameManager ready-gate is the real
	# safety net once World loads.
	if _started:
		return
	var srv = Global.network_manager.server
	if not srv:
		return
	if srv.peer_to_player.size() >= remote_needed:
		_broadcast_state()
		_start_game()

func _update_status():
	var srv = Global.network_manager.server
	if not srv:
		return
	var connected = srv.peer_to_player.size()
	_populate_slots(Global.network_manager.config.slots, connected)
	status_label.text = str(connected) + " / " + str(remote_needed) + " remote players connected"
	# Only broadcast state / start once every connected client has confirmed it
	# is inside the Lobby scene — otherwise the broadcast and rpc_start_game
	# target /root/Lobby on a peer that hasn't loaded the scene yet.
	if connected >= remote_needed and _ready_peers.size() >= connected:
		_broadcast_state()
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
	if Global.my_player_number >= 0:
		status_label.text = "You are Player " + str(Global.my_player_number) + ". " + status_label.text

func _start_game():
	# Called on the host when all remote slots are filled.
	# Broadcasts the transition RPC, then transitions locally.
	# Guarded: peer connect/disconnect events can both land in the same frame
	# window, which would otherwise double-fire the scene transition.
	if _started:
		return
	_started = true
	if _lobby_wait_timer:
		_lobby_wait_timer.stop()
		_lobby_wait_timer.queue_free()
		_lobby_wait_timer = null
	if Global.network_manager.server:
		Global.network_manager.server.accepting_clients = false
		if multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.disconnect(_on_peer_connected)
		if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
		rpc("rpc_start_game")
	get_tree().change_scene_to_file("res://scenes/world/World.tscn")

@rpc("authority", "call_remote")
func rpc_start_game():
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
