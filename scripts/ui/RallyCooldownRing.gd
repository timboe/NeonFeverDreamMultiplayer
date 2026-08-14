extends Control

class_name RallyCooldownRing

# Circular rally-cooldown indicator drawn around the FPS crosshair. Appears
# only while the cooldown is live (after pressing R) and drains over it;
# nothing is drawn when R is ready. Client-side display only — the server
# enforces the real cooldown.

# --- State ---

var _fraction := 0.0 # remaining cooldown fraction; 0 = ready, nothing drawn
var _accent := Color.CYAN

# --- Lifecycle ---

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_accent = Config.player_accent(Global.my_player_number)

# --- API ---

func set_fraction(f: float) -> void:
	_fraction = clampf(f, 0.0, 1.0)
	queue_redraw()

# --- Drawing ---

func _draw() -> void:
	if _fraction <= 0.0:
		return # ready — the rally button shows nothing
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 6.0
	# Faint full ring behind the draining arc for readability.
	draw_arc(center, radius, 0.0, TAU, 48, Color(_accent.r, _accent.g, _accent.b, 0.15), 6.0, true)
	# Bright arc from the top, shrinking as the cooldown drains.
	draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * _fraction, 48,
		Color(_accent.r, _accent.g, _accent.b, 0.9), 6.0, true)
