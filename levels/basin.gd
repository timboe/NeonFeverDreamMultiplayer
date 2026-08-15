extends Node

# --- Level data: basin (2-player economy bowl) ---
#
# Synopsis: an economy rush. Bases in opposite corners, but the heart of the
# map is a pre-lowered bowl of rich building ground ringed by a raised
# obsidian wall. Three permanent obsidian-floor gates are the only ways in or
# out — they can never be raised or built on, so the bowl is always exposed
# from every gate. Whoever claims the bowl first gets generator/vat riches,
# but holding all three gates against a two-front push is hard.

const NAME: String = "Basin"
const MAX_PLAYERS: int = 2

const SEED: int = -464216271911

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 5
const TRIPLETS_Z: int = 5
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# Opposite diagonal corners of the 300x300 arena.
const MCP_ARRAY: Array[int] = [110, 811]

# Pre-lowered staging pads at both bases, the central bowl (a rich pre-lowered
# building ground) and the three permanent gate floors through the obsidian
# ring. Tile 64 was dropped from the p1 pad: it sits on the playable-area
# border and generates as DISABLED_RAISED.
const LOWERED: Array[int] = [
	# p1 pad
	65, 106, 107, 108, 109, 110, 111, 114, 115, 167, 168, 171, 172,
	173, 174, 175, 176, 237, 238,
	# p2 pad
	743, 744, 807, 808, 809, 810, 811, 812, 815, 816, 872, 873, 876,
	877, 878, 879, 880, 881, 942, 943,
	# central bowl
	389, 390, 453, 454, 455, 456, 457, 458, 461, 462, 520, 521, 524,
	525, 526, 527, 528, 529, 592, 593,
	# obsidian-floor gates (also in IMMUTABLE)
	314, 315, 383, 384, 465, 466, 532, 533, 598, 599, 663, 664,
]

# A raised obsidian ring around the bowl (r 40-58 about the centre) with three
# gaps: one toward each base and one toward the far side. The gap tiles are
# obsidian FLOORS (IMMUTABLE + LOWERED) — permanent walkable gates that can
# never be raised or built on.
const IMMUTABLE: Array[int] = [
	318, 319, 322, 323, 381, 382, 387, 388, 391, 392, 397, 398, 447, 448,
	449, 450, 463, 464, 516, 517, 518, 519, 534, 535, 584, 585, 590, 591,
	594, 595, 600, 601, 655, 656, 659, 660,
	314, 315, 383, 384, 465, 466, 532, 533, 598, 599, 663, 664,
]

const INVISIBLE: Array[int] = []

const STARTING_BUILDINGS: Array = []
