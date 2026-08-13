extends Control
class_name MainMenu

# --- Nodes ---

@onready var slots_container: VBoxContainer = $VBoxContainer/ModeTabs/HostSection/SlotsContainer
@onready var player_count_spin: SpinBox = $VBoxContainer/ModeTabs/HostSection/PlayerCountSpin
@onready var port_line: LineEdit = $VBoxContainer/ModeTabs/HostSection/PortLine
@onready var ip_line: LineEdit = $VBoxContainer/ModeTabs/ConnectSection/IPLine
@onready var connect_port_line: LineEdit = $VBoxContainer/ModeTabs/ConnectSection/ConnectPortLine
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var mode_tabs: TabContainer = $VBoxContainer/ModeTabs
@onready var connect_error_overlay: ColorRect = $ConnectionErrorOverlay

# --- State ---

var _slot_option_buttons: Array[OptionButton] = []
var _connect_timer: Timer

# --- Constants ---

const CONNECT_TIMEOUT: float = 8.0

func _ready() -> void:
	UiFX.apply_menu_backdrop($Background)
	UiFX.pulse_title($VBoxContainer/Title)
	mode_tabs.tab_changed.connect(_on_tab_changed)
	player_count_spin.value_changed.connect(_on_player_count_changed)
	start_button.pressed.connect(_on_start_pressed)
	_on_player_count_changed(int(player_count_spin.value))
	_update_start_button()
	connect_error_overlay.get_node("DialogPanel/VBox/OKButton").pressed.connect(
		func(): connect_error_overlay.visible = false)

	if "--client" in OS.get_cmdline_args():
		mode_tabs.current_tab = 1

func _on_tab_changed(_tab_index: int) -> void:
	_update_start_button()

func _update_start_button() -> void:
	if mode_tabs.current_tab == 0:
		var has_remote = false
		for btn in _slot_option_buttons:
			if btn.selected == 1:
				has_remote = true
				break
		start_button.text = "Start Lobby" if has_remote else "Start Game"
	else:
		start_button.text = "Connect"

func _on_player_count_changed(count: int) -> void:
	for child in slots_container.get_children():
		child.queue_free()
	_slot_option_buttons.clear()

	for i in range(count):
		var hbox = HBoxContainer.new()
		var label = Label.new()
		label.text = "Player " + str(i + 1) + ":"
		label.size_flags_horizontal = Control.SIZE_EXPAND
		hbox.add_child(label)

		var option = OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND
		option.add_item("Host (Local)", GameConfig.SlotType.LOCAL)
		option.add_item("Remote", GameConfig.SlotType.REMOTE)
		option.add_item("AI", GameConfig.SlotType.AI)
		if i == 0:
			option.selected = 0
		else:
			option.selected = 1 if i == 1 else 2
		option.item_selected.connect(_on_slot_selected.bind(option))
		hbox.add_child(option)
		_slot_option_buttons.append(option)
		slots_container.add_child(hbox)

	_update_start_button()

func _on_slot_selected(selected_index: int, changed_button: OptionButton) -> void:
	if selected_index != 0:
		_update_start_button()
		return
	for btn in _slot_option_buttons:
		if btn != changed_button and btn.selected == 0:
			btn.selected = 1
	_update_start_button()

func _on_start_pressed() -> void:
	if mode_tabs.current_tab == 0:
		_start_host()
	else:
		_connect_to_server()

func _start_host() -> void:
	var config = GameConfig.new()
	config.player_count = int(player_count_spin.value)
	config.port = int(port_line.text)

	config.slots.resize(config.player_count)
	for i in range(config.player_count):
		var idx = _slot_option_buttons[i].selected
		config.slots[i] = _slot_option_buttons[i].get_item_id(idx) as GameConfig.SlotType

	var nm = preload("res://scripts/core/network/NetworkManager.gd").new()
	# Deterministic node name — the server routes RPCs (e.g. rpc_set_my_player_number)
	# to /root/NetworkManager on every peer. A generic .new() name would differ
	# per instance and silently drop the RPC (spectator clients).
	nm.name = "NetworkManager"
	get_tree().root.add_child(nm)
	Global.network_manager = nm
	if not nm.start_server(config):
		# Server failed to bind the port (e.g. another game instance — possibly
		# a stale one from an earlier session — is already holding it). Abort
		# instead of entering the lobby with a dead server, which would leave
		# remote players connecting to the wrong instance.
		Global.network_manager = null
		nm.stop()
		nm.queue_free()
		_show_overlay("Could Not Start Server",
			"The server could not listen on port " + str(config.port) + ". It may already be in use by another game instance — check for a second running copy of the game and close it before trying again.")
		return

	var has_remote = false
	for slot in config.slots:
		if slot == GameConfig.SlotType.REMOTE:
			has_remote = true
			break
	if has_remote:
		print("Start Lobby")
		get_tree().change_scene_to_file("res://scenes/menu/Lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/world/World.tscn")

func _connect_to_server() -> void:
	var ip = ip_line.text
	var port = int(connect_port_line.text)
	var nm = preload("res://scripts/core/network/NetworkManager.gd").new()
	# Deterministic node name — the server's rpc_set_my_player_number RPC routes to
	# /root/NetworkManager; a generic name would drop it (spectator client).
	nm.name = "NetworkManager"
	get_tree().root.add_child(nm)
	Global.network_manager = nm
	nm.connect_result.connect(_on_connect_result)
	start_button.disabled = true
	start_button.text = "Connecting..."
	# Safety net: ENet can hang in "connecting" without ever firing
	# connection_failed (e.g. unreachable host), so force the error on timeout.
	_connect_timer = Timer.new()
	_connect_timer.one_shot = true
	_connect_timer.wait_time = CONNECT_TIMEOUT
	_connect_timer.timeout.connect(_handle_connect_failure)
	add_child(_connect_timer)
	_connect_timer.start()
	nm.connect_to_server(ip, port)

func _on_connect_result(success: bool) -> void:
	if _connect_timer:
		_connect_timer.stop()
	if success:
		get_tree().change_scene_to_file("res://scenes/menu/Lobby.tscn")
		return
	_handle_connect_failure()

func _show_overlay(title: String, message: String) -> void:
	connect_error_overlay.get_node("DialogPanel/VBox/Title").text = title
	connect_error_overlay.get_node("DialogPanel/VBox/Message").text = message
	connect_error_overlay.visible = true

func _handle_connect_failure() -> void:
	if _connect_timer:
		_connect_timer.stop()
		_connect_timer.queue_free()
		_connect_timer = null
	# Connection failed (server not running, not ready, or unreachable).
	if Global.network_manager:
		var nm := Global.network_manager
		Global.network_manager = null
		nm.connect_result.disconnect(_on_connect_result)
		nm.stop()
		nm.queue_free()
	start_button.disabled = false
	start_button.text = "Connect"
	connect_error_overlay.visible = true
