extends Node

# --- Level data: skirmish_01 (legacy 3-player test map) ---
#
# Synopsis: the original hand-authored arena — two MCPs on one side, a third
# opposite, with raised/lowered pockets and obsidian decorations. Kept around
# for 3-player testing; real matches should use duel/basin/canyons.

const NAME: String = "Skirmish"

const MAX_PLAYERS: int = 3

const SEED: int = -6398989897141750821

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 5
const TRIPLETS_Z: int = 5
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# 185 temporary / debug
const MCP_ARRAY: Array[int] = [173, 185, 892]

const LOWERED: Array[int] = [
	109, 108, 174, 893, 953, 954,
	641, 709, 714, 644, 712, 777, 782, 715, 716, 781, 786, 719, 645, 713, 718, 648,
	# temporary / debug
	120, 186, 187, 121, 190, 191, 188,
]

const IMMUTABLE: Array[int] = [
	650, 585, 588, 589, 592, 590, 595, 532, 465, 464, 468, 466, 471, 175,
	176, 178, 889, 891, 890,
]

const INVISIBLE: Array[int] = [
	405, 470, 472, 469, 536, 531, 533, 594, 596, 593, 658, 659, 654, 655, 656,
	653, 652, 651, 584, 582, 587, 586, 591, 525, 526, 523, 460, 461, 458, 463,
	462, 467, 400, 401, 404, 535,
]

const STARTING_BUILDINGS: Array = []
