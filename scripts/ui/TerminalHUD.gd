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

# Shared empower handler: sends the empower command for this building and forces
# the player out of FPS mode (the empowered status is cleared on re-entering FPS).
func _empower_building(b: Building) -> void:
	if not b:
		return
	Global.send_command_me("empower", [b.id])
	var vm = Global.VM
	if vm:
		vm.force_leave_fps()
