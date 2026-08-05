class_name CutCornerBox
extends StyleBox

# Sci-fi octagonal panel: each corner is clipped at 45°, with a coloured border.

var cut := 14.0
var fill_color := Color(0.02, 0.02, 0.05, 0.92)
var border_color := Color(0, 1, 1, 0.6)
var border_width := 2.0

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var p := rect.position
	var s := rect.size
	var c := cut
	var pts := PackedVector2Array([
		p + Vector2(c, 0.0),
		p + Vector2(s.x - c, 0.0),
		p + Vector2(s.x, c),
		p + Vector2(s.x, s.y - c),
		p + Vector2(s.x - c, s.y),
		p + Vector2(c, s.y),
		p + Vector2(0.0, s.y - c),
		p + Vector2(0.0, c),
	])
	RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([fill_color]))
	var outline := pts.duplicate()
	outline.append(outline[0])
	RenderingServer.canvas_item_add_polyline(to_canvas_item, outline, PackedColorArray([border_color]), border_width, true)
