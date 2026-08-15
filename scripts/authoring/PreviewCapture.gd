extends Node

# One-shot level-preview authoring helper. Invoked via the MainMenu
# --capture-preview flag (see MainMenu._start_capture_run):
#   godot --path . -- --capture-preview --level=duel
#
# NOT headless — the headless display server renders nothing, so captures would
# come out black. Runs the usual single-LOCAL host path so the world generates
# identically (fixed seed), then frames the arena with a square top-down ortho
# camera, saves res://previews/<key>.png and quits. Added to /root (not the
# menu scene) so it survives the scene change into World.

# --- Constants ---

const PREVIEW_SIZE := Vector2i(1024, 1024)
const SAVE_DIR := "res://previews/"
# Extra framing beyond the world rectangle: tile anchors can poke ~33u past the
# ragged border, so leave a comfortable margin around it.
const MARGIN := 90.0

# --- State ---

var level_key: String = ""
var _capturing := false

func _ready() -> void:
	# Square aspect must be in place before the first rendered frame.
	get_window().size = PREVIEW_SIZE
	_run.call_deferred()

func _run() -> void:
	# Wait for World to load, then hook the tile-generation signal (emitted on
	# the first physics frame after TileManager._ready). If it already fired
	# before we connected, the frame-budget watchdog below captures anyway.
	while Global.TM == null:
		await get_tree().process_frame
	if not Global.TM.level_loaded.is_connected(_on_level_loaded):
		Global.TM.level_loaded.connect(_on_level_loaded, CONNECT_ONE_SHOT)
	for _i in range(90):
		if _capturing:
			return
		await get_tree().process_frame
	_capture()

func _on_level_loaded() -> void:
	# Let the freshly-built multimeshes hit the renderer, then capture.
	_capture.call_deferred()

func _capture() -> void:
	if _capturing:
		return
	_capturing = true
	# Pure world in the shot — no HUD, loading overlay or stats windows.
	for group in ["hud", "loading_overlay", "statistics_window"]:
		for node in get_tree().get_nodes_in_group(group):
			node.visible = false
	# The RTS camera must not fight ours for "current".
	for c in Global.VM.get_children():
		if c is Camera3D:
			c.current = false

	var extent_x: float = float(Global.level.TRIPLETS_X) * 3 * Cairo.UNIT * 2
	var extent_z: float = float(Global.level.TRIPLETS_Z) * 3 * Cairo.UNIT * 2
	var centre := Vector3(extent_x * 0.5, 0.0, extent_z * 0.5)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 4000.0
	cam.size = maxf(extent_x, extent_z) + 2.0 * MARGIN
	cam.position = centre + Vector3(0.0, maxf(extent_x, extent_z) * 2.0, 0.0)
	add_child(cam)
	cam.look_at(centre, Vector3(0, 0, -1))
	cam.make_current()

	# One frame for the camera switch, one to read the freshly rendered frame.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var path := SAVE_DIR + level_key + ".png"
	var err := image.save_png(path)
	if err == OK:
		print("Preview saved: " + path)
	else:
		push_error("PreviewCapture: failed to save " + path + " (err " + str(err) + ")")
	get_tree().quit()
