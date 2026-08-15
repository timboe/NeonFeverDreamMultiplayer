extends Node

# --- Level data: duel (2-player mirror 1v1) ---
#
# Synopsis: the classic skirmish. Both MCPs sit in opposite diagonal corners
# of the 300x300 arena behind pre-lowered staging pads. An unbroken obsidian
# spine runs along the anti-diagonal (x+z ~ 300) from border to border with
# three crossings left open — the short centre lane plus two flank lanes. The
# wall is permanent; territory is plentiful. The game is about which crossing
# you contest, and whether you raise flank walls to force the centre.

const NAME: String = "Duel"
const MAX_PLAYERS: int = 2

const SEED: int = 2026080101

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 5
const TRIPLETS_Z: int = 5
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# Opposite diagonal corners of the 300x300 arena. Chosen for equal starting
# AoE (85 tiles each, radius-6 BFS).
const MCP_ARRAY: Array[int] = [174, 937]

# Pre-lowered staging pads around each MCP (equal count per side).
const LOWERED: Array[int] = [
	# p1 pad
	110, 111, 112, 113, 114, 115, 118, 119, 169, 170, 173, 174, 175, 176,
	177, 178, 240, 241,
	# p2 pad
	808, 809, 872, 873, 874, 875, 876, 877, 880, 881, 932, 933, 936, 937,
	938, 939, 940, 941, 987,
]

# The anti-diagonal obsidian spine (x+z ~ 300): a continuous border-to-border
# wall with three narrow crossings left open (centre + two flanks). Players
# can only meet through the gates.
const IMMUTABLE: Array[int] = [
	270, 271, 274, 275, 276, 277, 336, 337, 340, 341, 394, 395, 398, 399,
	459, 460, 461, 462, 465, 466, 517, 518, 523, 524, 578, 579, 582, 583,
	584, 585, 645, 646, 649, 650, 703, 706, 707, 769, 770, 771, 774, 775,
]

const INVISIBLE: Array[int] = []

const STARTING_BUILDINGS: Array = []
