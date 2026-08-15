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

# Opposite diagonal corners of the 300x300 arena. Chosen for equal starting
# AoE (96 tiles each, radius-6 BFS).
const MCP_ARRAY: Array[int] = [238, 874]

# Pre-lowered staging pads at both bases, the bowl (a rich pre-lowered
# building ground just south-east of the map centre) and the three permanent
# gate floors through the obsidian ring.
const LOWERED: Array[int] = [
	# p1 pad
	110, 111, 169, 170, 171, 172, 173, 174, 177, 178, 233, 234, 237, 238,
	239, 240, 241, 242, 304, 305,
	# p2 pad
	807, 808, 870, 871, 872, 873, 874, 875, 878, 879, 934, 935, 938, 939,
	940, 941, 942, 943, 991,
	# bowl (BFS rings 0-2 about tile 593)
	520, 522, 523, 524, 525, 526, 527, 588, 589, 590, 591, 592, 593, 594,
	595, 597, 660,
	# obsidian-floor gates (also in IMMUTABLE)
	451, 453, 454, 461, 521, 528, 529, 598, 599, 659, 661, 662, 663, 664,
	665, 730,
]

# A raised obsidian ring around the bowl (the full boundary band about tile
# 593, kept tight so neither starting AoE touches it) with three gates: one
# toward each base and one toward the far corner. The gate tiles are obsidian
# FLOORS (IMMUTABLE + LOWERED) — permanent walkable gates that can never be
# raised or built on.
const IMMUTABLE: Array[int] = [
	450, 455, 456, 457, 458, 516, 518, 519, 530, 531, 584, 585, 586, 587,
	596, 601, 651, 655, 656, 657, 658,
	451, 453, 454, 461, 521, 528, 529, 598, 599, 659, 661, 662, 663, 664,
	665, 730,
]

const INVISIBLE: Array[int] = []

const STARTING_BUILDINGS: Array = []
