extends Control

class_name TerminalHUD

# Shared cursor wiring for all diegetic terminal HUDs. Each subclass scene must
# contain a "Cursor" node (TerminalCursor scene/script) that the avatar ray drives.
@onready var cursor: TerminalCursor = $Cursor

func show_cursor_at_uv(uv: Vector2) -> void:
	if cursor:
		cursor.show_at_uv(uv)

func hide_cursor() -> void:
	if cursor:
		cursor.hide_cursor()

func click_at_uv(uv: Vector2) -> void:
	if cursor:
		cursor.click_at(uv)

func uv_from_collision(screen_mesh: MeshInstance3D, collision_point: Vector3) -> Vector2:
	if cursor:
		return cursor.uv_from_collision(screen_mesh, collision_point)
	return Vector2.ZERO
