extends PanelContainer

class_name NotificationManager

# --- Constants ---

const MAX_VISIBLE := 7
const DISPLAY_DURATION := 20.0

const EVENT_COLORS := {
	"added": Color(0.35, 0.8, 1, 1),
	"assigned": Color(0.3, 1, 0.5, 1),
	"abandoned": Color(1, 0.7, 0.2, 1),
	"finished": Color(0.7, 1, 1, 1),
}

# --- State ---

var notification_list: VBoxContainer
var placeholder: Label

var _notification_data: Dictionary = {}
var _next_id := 0

func _ready() -> void:
	Global.NM = self
	notification_list = %List
	for child in notification_list.get_children():
		if child is Label:
			placeholder = child
			break
	add_to_group("notification_manager")

func add_notification(pnum: int, event: String, text: String, location: Vector3) -> void:
	if pnum != Global.my_player_number:
		return
	var id := _next_id
	_next_id += 1
	placeholder.visible = false
	while notification_list.get_child_count() > MAX_VISIBLE:
		var oldest := notification_list.get_child(1)
		if oldest:
			_remove_entry(oldest.name.to_int())
	var chip := _build_chip(event, text, id)
	chip.name = str(id)
	notification_list.add_child(chip)
	# Entry animation — fade in.
	chip.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(chip, "modulate:a", 1.0, 0.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(DISPLAY_DURATION - 2.0)
	tween.tween_property(chip, "modulate:a", 0.0, 2.0)
	tween.tween_callback(_remove_entry.bind(id))
	_notification_data[id] = {"text": text, "location": location, "node": chip, "tween": tween}

func _build_chip(event: String, text: String, id: int) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var accent := Config.player_accent(Global.my_player_number)
	sb.bg_color = Color(0.03, 0.04, 0.08, 0.92)
	sb.border_color = Color(accent.r, accent.g, accent.b, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_right = 8.0
	sb.content_margin_bottom = 4.0
	chip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	var strip := ColorRect.new()
	strip.custom_minimum_size = Vector2(4, 0)
	strip.color = EVENT_COLORS.get(event, Color(0, 1, 1, 1))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(strip)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.gui_input.connect(_on_label_gui_input.bind(id))
	return chip

func _remove_entry(id: int) -> void:
	if id in _notification_data:
		var entry = _notification_data[id]
		var tween = entry.get("tween")
		if tween and tween.is_valid():
			tween.kill()
		var node = entry["node"]
		if node and is_instance_valid(node):
			if node.get_parent():
				node.get_parent().remove_child(node)
			node.queue_free()
		_notification_data.erase(id)
	if _notification_data.is_empty():
		placeholder.visible = true

func _on_label_gui_input(event: InputEvent, id: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_notification_clicked(id)

func _on_notification_clicked(id: int) -> void:
	if id in _notification_data:
		var loc = _notification_data[id]["location"]
		Global.VM.jump_to(loc)

@rpc("authority", "call_local", "reliable")
func rpc_add_job_notification(pnum: int, event: String, text: String, loc_x: float, loc_y: float, loc_z: float) -> void:
	add_notification(pnum, event, text, Vector3(loc_x, loc_y, loc_z))
