extends Control
class_name MainMenu

# --- Nodes ---

@onready var slots_container: VBoxContainer = $VBoxContainer/BodyRow/ModeTabs/HostSection/SlotsContainer
@onready var player_count_spin: SpinBox = $VBoxContainer/BodyRow/ModeTabs/HostSection/PlayerCountRow/PlayerCountSpin
@onready var port_line: LineEdit = $VBoxContainer/BodyRow/ModeTabs/HostSection/PortRow/PortLine
@onready var ip_line: LineEdit = $VBoxContainer/BodyRow/ModeTabs/ConnectSection/AddressRow/IPLine
@onready var connect_port_line: LineEdit = $VBoxContainer/BodyRow/ModeTabs/ConnectSection/PortRow/ConnectPortLine
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var mode_tabs: TabContainer = $VBoxContainer/BodyRow/ModeTabs
@onready var preview_panel: PanelContainer = $VBoxContainer/BodyRow/PreviewPanel
@onready var preview_texture: TextureRect = $VBoxContainer/BodyRow/PreviewPanel/Content/PreviewTexture
@onready var preview_fallback: Label = $VBoxContainer/BodyRow/PreviewPanel/Content/FallbackLabel
@onready var connect_error_overlay: ColorRect = $ConnectionErrorOverlay

# --- State ---

var _slot_option_buttons: Array[OptionButton] = []
var _map_option: OptionButton
var _connect_timer: Timer

# --- Constants ---

const CONNECT_TIMEOUT: float = 8.0

func _ready() -> void:
	# Headless level-authoring helper: godot --headless --path . -- --dump-tiles --level=duel
	# Deferred: root is still busy setting up the scene during _ready, so an
	# immediate add_child(NetworkManager) fails.
	if "--dump-tiles" in OS.get_cmdline_user_args():
		_start_dump_run.call_deferred()
		return
	if "--capture-preview" in OS.get_cmdline_user_args():
		_start_capture_run.call_deferred()
		return
	UiFX.apply_menu_backdrop($Background)
	UiFX.pulse_title($VBoxContainer/Title)
	mode_tabs.tab_changed.connect(_on_tab_changed)
	player_count_spin.value_changed.connect(_on_player_count_changed)
	start_button.pressed.connect(_on_start_pressed)
	_setup_map_picker()
	_on_player_count_changed(int(player_count_spin.value))
	_update_start_button()
	connect_error_overlay.get_node("DialogPanel/VBox/OKButton").pressed.connect(
		func(): connect_error_overlay.visible = false)
	# Keep the preview square: side = the tabs' height (and it may change once
	# the containers finish their first layout).
	mode_tabs.resized.connect(_update_preview_size)
	_update_preview_size.call_deferred()

	if "--client" in OS.get_cmdline_args():
		mode_tabs.current_tab = 1

func _update_preview_size() -> void:
	var h := mode_tabs.size.y
	if h > 0:
		preview_panel.custom_minimum_size = Vector2(h, h)

func _setup_map_picker() -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Map:"
	label.size_flags_horizontal = Control.SIZE_EXPAND
	row.add_child(label)
	_map_option = OptionButton.new()
	_map_option.size_flags_horizontal = Control.SIZE_EXPAND
	for key in Global.LEVELS:
		_map_option.add_item(Global.level_label(key), _map_option.item_count)
		_map_option.set_item_metadata(_map_option.item_count - 1, key)
	_map_option.item_selected.connect(_on_map_changed)
	row.add_child(_map_option)
	var host_section := $VBoxContainer/BodyRow/ModeTabs/HostSection
	host_section.add_child(row)
	host_section.move_child(row, 0)
	_on_map_changed(_map_option.selected)

func _on_map_changed(index: int) -> void:
	var max_p := Global.level_max_players(_map_option.get_item_metadata(index))
	player_count_spin.max_value = max_p
	if player_count_spin.value > max_p:
		player_count_spin.value = max_p
	_update_preview_texture()

# Loads res://previews/<key>.png for the selected map into the preview box.
# Missing captures (previews not generated yet) fall back to the label.
func _update_preview_texture() -> void:
	if _map_option == null:
		return
	var key: String = _map_option.get_item_metadata(_map_option.selected)
	var tex := load("res://previews/" + key + ".png") as Texture2D
	preview_texture.texture = tex
	preview_fallback.visible = tex == null

# Level-preview authoring helper: godot --path . -- --capture-preview
# --level=duel. NOT headless — headless has no renderer, so captures come out
# black. Loads World with the requested level, then PreviewCapture (a /root
# node, so it survives the scene change) frames the arena with a square ortho
# camera, saves res://previews/<key>.png and quits.
func _start_capture_run() -> void:
	var level_key := Global.DEFAULT_LEVEL
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_key = arg.substr("--level=".length())
	Global.set_level(level_key)
	var config := GameConfig.new()
	config.player_count = 1
	config.level_name = level_key
	config.slots = [GameConfig.SlotType.LOCAL, GameConfig.SlotType.CLOSED,
		GameConfig.SlotType.CLOSED, GameConfig.SlotType.CLOSED]
	var nm = preload("res://scripts/core/network/NetworkManager.gd").new()
	nm.name = "NetworkManager"
	get_tree().root.add_child(nm)
	Global.network_manager = nm
	# ENet rejects port 0 — hunt for a free high port (see _start_dump_run).
	var bound := false
	for attempt in range(50):
		config.port = 20000 + randi_range(0, 40000)
		if nm.start_server(config):
			bound = true
			break
	if not bound:
		push_warning("MainMenu._start_capture_run: no free port found — continuing without network")
	var capture = preload("res://scripts/authoring/PreviewCapture.gd").new()
	capture.level_key = level_key
	get_tree().root.add_child(capture)
	get_tree().change_scene_to_file("res://scenes/world/World.tscn")

# Loads World directly with the requested level and no lobby, then TileManager
# dumps every tile (id + world coords + flags) to stdout and
# user://level_dump.txt before quitting. Networking is started so the usual
# host code paths hold, but nothing connects.
func _start_dump_run() -> void:
	var level_key := Global.DEFAULT_LEVEL
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_key = arg.substr("--level=".length())
	Global.set_level(level_key)
	var config := GameConfig.new()
	config.player_count = 1
	config.level_name = level_key
	config.slots = [GameConfig.SlotType.LOCAL, GameConfig.SlotType.CLOSED,
		GameConfig.SlotType.CLOSED, GameConfig.SlotType.CLOSED]
	var nm = preload("res://scripts/core/network/NetworkManager.gd").new()
	nm.name = "NetworkManager"
	get_tree().root.add_child(nm)
	Global.network_manager = nm
	# ENet rejects port 0 — hunt for a free high port so the usual host-side
	# code paths hold without colliding with a real lobby on 8070.
	var bound := false
	for attempt in range(50):
		config.port = 20000 + randi_range(0, 40000)
		if nm.start_server(config):
			bound = true
			break
	if not bound:
		push_warning("MainMenu._start_dump_run: no free port found — continuing without network")
	get_tree().change_scene_to_file("res://scenes/world/World.tscn")

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
	if _map_option:
		config.level_name = _map_option.get_item_metadata(_map_option.selected)

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
		# No lobby — the level choice must be applied before World generates.
		Global.set_level(config.level_name)
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
