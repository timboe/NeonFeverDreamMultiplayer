extends CanvasLayer

class_name VictoryBanner

# Full-screen end-of-game banner: the winning player's name in large Neon-font
# text in their colour. Shown by GameManager for 5s after rpc_game_over, then
# hidden when the statistics window opens.

# --- Nodes ---

@onready var _winner_label: Label = $Root/Center/WinnerLabel

func _ready() -> void:
	add_to_group("victory_banner")

# --- Public API ---

func show_winner(pnum: int) -> void:
	_winner_label.text = _winner_text(pnum)
	_winner_label.add_theme_color_override("font_color", Config.player_accent(pnum))
	visible = true

func hide_banner() -> void:
	visible = false

func _winner_text(pnum: int) -> String:
	if pnum >= 1 and pnum <= Config.PLAYER_NAMES.size():
		return Config.PLAYER_NAMES[pnum - 1].to_upper() + " WINS!"
	return "PLAYER " + str(pnum) + " WINS!"
