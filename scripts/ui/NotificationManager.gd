extends PanelContainer

class_name NotificationManager

const MAX_VISIBLE := 7
const DISPLAY_DURATION := 20.0

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

func add_notification(pnum: int, text: String, location: Vector3) -> void:
	if pnum != Global.my_player_number:
		return
	var id := _next_id
	_next_id += 1
	placeholder.visible = false
	while notification_list.get_child_count() > MAX_VISIBLE:
		var oldest := notification_list.get_child(1)
		if oldest:
			_remove_entry(oldest.name.to_int())
	var label := Label.new()
	label.name = str(id)
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(_on_label_gui_input.bind(id))
	notification_list.add_child(label)
	var tween := create_tween()
	tween.tween_interval(DISPLAY_DURATION - 2.0)
	tween.tween_property(label, "modulate:a", 0.0, 2.0)
	tween.tween_callback(_remove_entry.bind(id))
	_notification_data[id] = {"text": text, "location": location, "node": label, "tween": tween}

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
		print("Notification clicked — jump to ", loc)
		# STUB: future camera jump
		# var cam = get_tree().get_first_node_in_group("camera_rts")
		# if cam and cam.has_method("jump_to"):
		#     cam.jump_to(loc)

@rpc("authority", "call_local", "reliable")
func rpc_add_job_notification(pnum: int, text: String, loc_x: float, loc_y: float, loc_z: float) -> void:
	add_notification(pnum, text, Vector3(loc_x, loc_y, loc_z))
