class_name LineGraph
extends Control

# Custom neon-themed line graph. One or more series drawn as polylines with
# optional left/right y-axes, an autoscaled grid, and an in-canvas legend.

# --- Constants ---

const PAD_LEFT := 48.0
const PAD_RIGHT := 48.0
const PAD_TOP := 10.0
const PAD_BOTTOM := 22.0
const GRID_DIVISIONS := 5
const AXIS_FONT_SIZE := 11
const LEGEND_ROW := 16.0
const FILL_ALPHA := 0.07

# --- State ---

# Array of {name: String, color: Color, axis: "left"|"right", values: PackedFloat32Array}
# Index 0 of each values array is the oldest sample (newest last), matching the
# StatisticsManager history layout.
var series: Array = []

# How many of the most recent samples to draw (fewer if the history is shorter).
var window_size := 30

# --- Public API ---

func set_data(new_series: Array) -> void:
	series = new_series
	queue_redraw()
func set_window_size(n: int) -> void:
	window_size = n
	queue_redraw()

# --- Drawing ---

func _draw() -> void:
	var area := Rect2(PAD_LEFT, PAD_TOP, size.x - PAD_LEFT - PAD_RIGHT, size.y - PAD_TOP - PAD_BOTTOM)
	if area.size.x < 10.0 or area.size.y < 10.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.06, 0.9))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 1, 1, 0.35), false, 1.0)

	var total := _max_sample_count()
	if total < 2:
		var font := _mono_font()
		draw_string(font, Vector2(PAD_LEFT, size.y * 0.5 - 6), "NO DATA",
			HORIZONTAL_ALIGNMENT_LEFT, area.size.x, 18, Color(0.5, 0.55, 0.65, 0.8))
		return

	var count := mini(total, window_size)
	var start := total - count

	var left_max := _axis_max("left", start)
	var right_max := _axis_max("right", start)
	left_max = _nice_ceil(maxf(left_max, 4.0))
	right_max = _nice_ceil(maxf(right_max, 4.0))

	_draw_grid(area, left_max, right_max, count)
	_draw_series(area, start, count, left_max, right_max)
	_draw_legend()

func _draw_grid(area: Rect2, left_max: float, right_max: float, count: int) -> void:
	var font := _mono_font()
	var grid_col := Color(0, 1, 1, 0.12)
	var label_col := Color(0.6, 0.7, 0.8, 0.9)
	var right_col := Color(0.85, 0.6, 0.95, 0.9)
	for i in range(GRID_DIVISIONS + 1):
		var t := float(i) / float(GRID_DIVISIONS)
		var y := area.position.y + area.size.y * (1.0 - t)
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), grid_col, 1.0)
		var left_val := left_max * t
		draw_string(font, Vector2(2, y + AXIS_FONT_SIZE * 0.4), _fmt(left_val),
			HORIZONTAL_ALIGNMENT_LEFT, PAD_LEFT - 6, AXIS_FONT_SIZE, label_col)
		if right_max > 4.0 and _axis_has_series("right"):
			var right_val := right_max * t
			draw_string(font, Vector2(size.x - PAD_RIGHT + 4, y + AXIS_FONT_SIZE * 0.4), _fmt(right_val),
				HORIZONTAL_ALIGNMENT_LEFT, PAD_RIGHT - 6, AXIS_FONT_SIZE, right_col)
	# X-axis: oldest edge and "now".
	var now_txt := "now"
	var oldest_txt := "-" + str(count) + "s"
	draw_string(font, Vector2(area.position.x, area.end.y + 15), oldest_txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_FONT_SIZE, label_col)
	draw_string(font, Vector2(area.end.x, area.end.y + 15), now_txt,
		HORIZONTAL_ALIGNMENT_RIGHT, -1, AXIS_FONT_SIZE, label_col)

func _draw_series(area: Rect2, start: int, count: int, left_max: float, right_max: float) -> void:
	for s in series:
		var vals: PackedFloat32Array = s["values"]
		if vals.size() < 2:
			continue
		var axis_max := left_max if s["axis"] == "left" else right_max
		if axis_max <= 0.0:
			continue
		var pts := PackedVector2Array()
		var n := mini(count, vals.size() - start)
		for i in range(n):
			var t := float(i) / float(maxi(count - 1, 1))
			var x := area.position.x + area.size.x * t
			var v := float(vals[start + i])
			var y := area.position.y + area.size.y * (1.0 - clampf(v / axis_max, 0.0, 1.0))
			pts.append(Vector2(x, y))
		if pts.size() >= 2:
			draw_polyline(pts, s["color"], 2.0, true)
			var fill := PackedVector2Array()
			fill.append(Vector2(pts[0].x, area.end.y))
			fill.append_array(pts)
			fill.append(Vector2(pts[pts.size() - 1].x, area.end.y))
			var fill_col: Color = s["color"]
			fill_col.a = FILL_ALPHA
			draw_colored_polygon(fill, fill_col)

func _draw_legend() -> void:
	if series.is_empty():
		return
	var font := _mono_font()
	var swatch := 18.0
	var gap := 8.0
	var x := PAD_LEFT + 8.0
	var y := PAD_TOP + 8.0
	var max_w := 0.0
	for s in series:
		var w := swatch + gap + font.get_string_size(s["name"], HORIZONTAL_ALIGNMENT_LEFT, AXIS_FONT_SIZE + 1).x
		max_w = maxf(max_w, w)
	draw_rect(Rect2(x - 4.0, y - 4.0, max_w + 14.0, series.size() * LEGEND_ROW + 6.0),
		Color(0.02, 0.02, 0.05, 0.65))
	for s in series:
		draw_line(Vector2(x, y + 6.0), Vector2(x + swatch, y + 6.0), s["color"], 2.0)
		draw_string(font, Vector2(x + swatch + gap, y + AXIS_FONT_SIZE + 1), s["name"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, AXIS_FONT_SIZE + 1, Color(0.9, 0.95, 1, 0.95))
		y += LEGEND_ROW

# --- Helpers ---

func _max_sample_count() -> int:
	var m := 0
	for s in series:
		m = maxi(m, (s["values"] as PackedFloat32Array).size())
	return m

func _axis_has_series(axis: String) -> bool:
	for s in series:
		if s["axis"] == axis and (s["values"] as PackedFloat32Array).size() > 0:
			return true
	return false

func _axis_max(axis: String, start: int) -> float:
	var m := 0.0
	for s in series:
		if s["axis"] != axis:
			continue
		var vals: PackedFloat32Array = s["values"]
		for i in range(maxi(start, 0), vals.size()):
			m = maxf(m, float(vals[i]))
	return m

func _nice_ceil(v: float) -> float:
	if v <= 0.0:
		return 4.0
	var exp: float = floor(log(v) / log(10.0))
	var base: float = pow(10.0, exp)
	var norm := v / base
	var nice := 10.0
	if norm <= 1.0:
		nice = 1.0
	elif norm <= 2.0:
		nice = 2.0
	elif norm <= 5.0:
		nice = 5.0
	return nice * base

func _fmt(v: float) -> String:
	if v >= 100.0:
		return str(int(v))
	return String.num(v, 1)

func _mono_font() -> Font:
	var f: Font = get_theme_font("font", "ValueLabel")
	if f:
		return f
	return get_theme_default_font()
