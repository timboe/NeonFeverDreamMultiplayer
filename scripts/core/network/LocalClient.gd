extends Node
class_name LocalClient

# Wrapper for a local player (human or AI) on the host machine.
# Owns the player_number and is_ai flag. Its child nodes
# (HumanController or AIController) read these via get_parent().
# Remote connections bypass LocalClient entirely — they send RPCs
# directly from their own GameGrid instance.

var player_number: int
var is_ai: bool = false
