extends CanvasLayer
class_name LoadingOverlay

# Full-screen loading screen shown on every peer while the World scene loads and
# the server waits for all clients to be ready (see GameManager's start gate).

# --- Nodes ---

@onready var progress_label: Label = $Center/ProgressLabel
@onready var pulse: ColorRect = $Center/PulseBar

# --- State ---

var _pulse_tween: Tween

func _ready() -> void:
	add_to_group("loading_overlay")
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(pulse, "modulate:a", 0.2, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_pulse_tween.tween_property(pulse, "modulate:a", 1.0, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _process(_delta: float) -> void:
	if Global.game_started and visible:
		if _pulse_tween and _pulse_tween.is_valid():
			_pulse_tween.kill()
			_pulse_tween = null
		hide()

func set_progress(ready_status: int, expected: int) -> void:
	if progress_label:
		progress_label.text = "Players ready: " + str(ready_status) + " / " + str(expected)
