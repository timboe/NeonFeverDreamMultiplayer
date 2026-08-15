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

# Opposite diagonal corners of the 300x300 arena.
const MCP_ARRAY: Array[int] = [110, 880]

# Pre-lowered staging pads around each MCP (equal count per side). Tiles 62
# and 885 were originally in these pads but sit on the playable-area border
# (their rotated check-corners graze the world rectangle), so they generate
# as DISABLED_RAISED and would become obsidian floors if listed here.
const LOWERED: Array[int] = [
	63, 106, 107, 108, 109, 110, 111, 114, 115, 165, 166, 169, 170,
	171, 172, 173, 174, 236, 237,
	812, 813, 876, 877, 878, 879, 880, 881, 884, 936, 937, 940, 941,
	942, 943, 944, 945, 991, 992,
]

# The anti-diagonal obsidian spine (x+z ~ 300): a continuous border-to-border
# wall with three crossings left open (centre + two flanks). Players can only
# meet through the gaps.
const IMMUTABLE: Array[int] = [
	274, 275, 276, 277, 340, 341, 394, 395, 455, 456, 459, 460, 461, 462,
	519, 520, 523, 524, 703, 706, 707, 769, 770, 771, 774, 775,
]

const INVISIBLE: Array[int] = []

const STARTING_BUILDINGS: Array = []
