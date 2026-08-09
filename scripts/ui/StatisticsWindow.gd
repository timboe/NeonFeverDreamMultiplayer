extends CanvasLayer

class_name StatisticsWindow

# Modal statistics overlay (toggled with the `ui_stats`/M key while in RTS mode).
# Renders three stacked line graphs from the current player's StatisticsManager
# history: AoE+Energy (dual-axis), Units, and Damage.

# --- Constants ---

const REFRESH_INTERVAL := 0.5

# Per-metric line colours (distinct neon palette).
const PALETTE := {
	"stored": Color(0, 1, 1),
	"capacity": Color(0.45, 0.75, 1),
	"generated": Color(0.25, 1, 0.4),
	"used": Color(1, 0.65, 0.1),
	"aoe": Color(1, 0.25, 0.85),
	"zoomba": Color(0.25, 1, 0.4),
	"tank": Color(1, 0.85, 0.25),
	"aerial_patrol": Color(0, 1, 1),
	"aerial_strike": Color(1, 0.25, 0.85),
	"virus": Color(1, 0.35, 0.35),
	"damage_done": Color(0, 1, 1),
	"damage_received": Color(1, 0.35, 0.35),
}

# Trailing-window options: sample count -> button label (1 sample per second).
const WINDOW_OPTIONS := {30: "30s", 600: "10m", 1800: "30m"}

# --- State ---

var _refresh_timer := 0.0
var _window_size := 30

var _btn_normal: StyleBoxFlat
var _btn_hover: StyleBoxFlat
var _btn_pressed: StyleBoxFlat
var _btn_focus: StyleBoxFlat
var _btn_disabled: StyleBoxFlat

# --- Nodes ---

@onready var _root: Control = $Root
@onready var _graph_aoe_energy: LineGraph = $Root/Panel/Margin/VBox/GraphAoeEnergy
@onready var _graph_units: LineGraph = $Root/Panel/Margin/VBox/GraphUnits
@onready var _graph_damage: LineGraph = $Root/Panel/Margin/VBox/GraphDamage
@onready var _close_btn: Button = $Root/Panel/Margin/VBox/TitleBar/CloseBtn
@onready var _window_buttons: Dictionary = {
	30: $Root/Panel/Margin/VBox/Footer/Window30,
	600: $Root/Panel/Margin/VBox/Footer/Window600,
	1800: $Root/Panel/Margin/VBox/Footer/Window1800,
}

# --- Lifecycle ---

func _ready() -> void:
	add_to_group("statistics_window")
	_close_btn.pressed.connect(close)
	for n in _window_buttons:
		_window_buttons[n].pressed.connect(_on_window_pressed.bind(n))
	_apply_theme()
	_window_buttons[_window_size].set_pressed_no_signal(true)

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer += delta
	if _refresh_timer >= REFRESH_INTERVAL:
		_refresh_timer = 0.0
		_refresh_graphs()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- Public API ---

func toggle() -> void:
	if visible:
		close()
	elif _can_open():
		open()

func open() -> void:
	visible = true
	_refresh_graphs()

func close() -> void:
	visible = false

func _can_open() -> bool:
	var vm = Global.VM
	if not vm:
		return false
	return vm.camera_status == vm.CameraStatus.OVERHEAD

# --- Graph refresh ---

func _refresh_graphs() -> void:
	var records: Array = Global.SM.get_stats(Global.my_player_number)
	_graph_aoe_energy.set_data(_build_series(records, [
		["Energy stored", "stored", "left", "energy.stored"],
		["Capacity", "capacity", "left", "energy.capacity"],
		["Generated/s", "generated", "left", "energy.generated"],
		["Used/s", "used", "left", "energy.used"],
		["AoE", "aoe", "right", "aoe_size"],
	]))
	_graph_units.set_data(_build_series(records, [
		["Zoomba", "zoomba", "left", "units.zoomba"],
		["Tank", "tank", "left", "units.tank"],
		["Aerial patrol", "aerial_patrol", "left", "units.aerial_patrol"],
		["Aerial strike", "aerial_strike", "left", "units.aerial_strike"],
		["Virus", "virus", "left", "units.virus"],
	]))
	_graph_damage.set_data(_build_series(records, [
		["Damage done", "damage_done", "left", "damage.done"],
		["Damage received", "damage_received", "left", "damage.received"],
	]))
	for g in [_graph_aoe_energy, _graph_units, _graph_damage]:
		g.set_window_size(_window_size)

# defs: Array of [display name, palette key, axis, dot-path into a record].
func _build_series(records: Array, defs: Array) -> Array:
	var out: Array = []
	for d in defs:
		var values := PackedFloat32Array()
		for r in records:
			values.append(_dig(r, d[3]))
		out.append({"name": d[0], "color": PALETTE[d[1]], "axis": d[2], "values": values})
	return out

func _dig(r: Dictionary, path: String) -> float:
	var parts := path.split(".")
	var cur = r
	for p in parts:
		cur = cur[p]
	return float(cur)

# --- Window selector ---

func _on_window_pressed(seconds: int) -> void:
	_window_size = seconds
	for n in _window_buttons:
		_window_buttons[n].set_pressed_no_signal(n == seconds)
	for g in [_graph_aoe_energy, _graph_units, _graph_damage]:
		g.set_window_size(_window_size)

# --- Styling (player-accent tint, mirrors HUD.gd) ---

func _apply_theme() -> void:
	var c := Config.player_accent(Global.my_player_number)
	var lit := Color(c.r, c.g, c.b, Config.BUTTON_LIT_ALPHA)
	var cut := CutCornerBox.new()
	cut.cut = 12.0
	cut.border_color = lit
	cut.border_width = 2.0
	cut.fill_color = Color(0.02, 0.02, 0.05, 0.92)
	$Root/Panel.add_theme_stylebox_override("panel", cut)
	_btn_normal = _tinted_button(&"normal", Color(c.r, c.g, c.b, Config.BUTTON_NORMAL_BORDER_ALPHA), Color(c.r, c.g, c.b, Config.BUTTON_NORMAL_GLOW_ALPHA))
	_btn_hover = _tinted_button(&"hover", lit, Color(c.r, c.g, c.b, Config.BUTTON_HOVER_GLOW_ALPHA))
	_btn_pressed = _tinted_button(&"pressed", lit, Color(c.r, c.g, c.b, Config.BUTTON_PRESSED_GLOW_ALPHA))
	if _btn_pressed:
		_btn_pressed.bg_color = Color(c.r * Config.BUTTON_PRESSED_BG_SCALE, c.g * Config.BUTTON_PRESSED_BG_SCALE, c.b * Config.BUTTON_PRESSED_BG_SCALE, 1)
	_btn_focus = _tinted_button(&"focus", Color(c.r, c.g, c.b, Config.BUTTON_FOCUS_BORDER_ALPHA), Color(c.r, c.g, c.b, Config.BUTTON_FOCUS_GLOW_ALPHA))
	_btn_disabled = _tinted_button(&"disabled", Color(c.r, c.g, c.b, Config.BUTTON_DISABLED_BORDER_ALPHA), Color(c.r, c.g, c.b, Config.BUTTON_DISABLED_GLOW_ALPHA))
	for btn in [_close_btn] + _window_buttons.values():
		_apply_button_theme(btn)
		UiFX.attach_glow_pulse(btn, Color(c.r, c.g, c.b, 0.6))

func _tinted_button(state: StringName, border: Color, glow: Color) -> StyleBoxFlat:
	var base := _root.get_theme_stylebox(state, "Button") as StyleBoxFlat
	if base == null:
		return null
	var sb: StyleBoxFlat = base.duplicate()
	sb.border_color = border
	sb.shadow_color = glow
	return sb

func _apply_button_theme(btn: Button) -> void:
	if _btn_normal:
		btn.add_theme_stylebox_override("normal", _btn_normal)
	if _btn_hover:
		btn.add_theme_stylebox_override("hover", _btn_hover)
	if _btn_pressed:
		btn.add_theme_stylebox_override("pressed", _btn_pressed)
	if _btn_focus:
		btn.add_theme_stylebox_override("focus", _btn_focus)
	if _btn_disabled:
		btn.add_theme_stylebox_override("disabled", _btn_disabled)
