extends Control
class_name MainMenu

@onready var slots_container: VBoxContainer = $VBoxContainer/ModeTabs/HostSection/SlotsContainer
@onready var player_count_spin: SpinBox = $VBoxContainer/ModeTabs/HostSection/PlayerCountSpin
@onready var port_line: LineEdit = $VBoxContainer/ModeTabs/HostSection/PortLine
@onready var ip_line: LineEdit = $VBoxContainer/ModeTabs/ConnectSection/IPLine
@onready var connect_port_line: LineEdit = $VBoxContainer/ModeTabs/ConnectSection/ConnectPortLine
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var mode_tabs: TabContainer = $VBoxContainer/ModeTabs

var slot_option_buttons: Array[OptionButton] = []

func _ready():
	mode_tabs.tab_changed.connect(_on_tab_changed)
	player_count_spin.value_changed.connect(_on_player_count_changed)
	start_button.pressed.connect(_on_start_pressed)
	_on_player_count_changed(int(player_count_spin.value))
	_update_start_button()

	if "--client" in OS.get_cmdline_args():
		mode_tabs.current_tab = 1

func _on_tab_changed(_tab_index: int):
	_update_start_button()

func _update_start_button():
	if mode_tabs.current_tab == 0:
		var has_remote = false
		for btn in slot_option_buttons:
			if btn.selected == 1:
				has_remote = true
				break
		start_button.text = "Start Lobby" if has_remote else "Start Game"
	else:
		start_button.text = "Connect"

func _on_player_count_changed(count: int):
	for child in slots_container.get_children():
		child.queue_free()
	slot_option_buttons.clear()

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
		slot_option_buttons.append(option)
		slots_container.add_child(hbox)

	_update_start_button()

func _on_slot_selected(selected_index: int, changed_button: OptionButton):
	if selected_index != 0:
		_update_start_button()
		return
	for btn in slot_option_buttons:
		if btn != changed_button and btn.selected == 0:
			btn.selected = 1
	_update_start_button()

func _on_start_pressed():
	if mode_tabs.current_tab == 0:
		_start_host()
	else:
		_connect_to_server()

func _start_host():
	var config = GameConfig.new()
	config.player_count = int(player_count_spin.value)
	config.port = int(port_line.text)

	config.slots.resize(config.player_count)
	for i in range(config.player_count):
		var idx = slot_option_buttons[i].selected
		config.slots[i] = slot_option_buttons[i].get_item_id(idx) as GameConfig.SlotType

	var nm = preload("res://scripts/core/network/NetworkManager.gd").new()
	get_tree().root.add_child(nm)
	Global.network_manager = nm
	nm.start_server(config)

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

func _connect_to_server():
	var ip = ip_line.text
	var port = int(connect_port_line.text)
	var nm = preload("res://scripts/core/network/NetworkManager.gd").new()
	get_tree().root.add_child(nm)
	Global.network_manager = nm
	nm.connect_to_server(ip, port)
	get_tree().change_scene_to_file("res://scenes/menu/Lobby.tscn")
