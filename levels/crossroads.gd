extends Node

# --- Level data: crossroads (4-player plaza) ---
#
# Synopsis: the classic four-way free-for-all. MCPs sit in all four corners
# of the 360x360 arena; a pre-lowered central plaza is the contested meeting
# ground, its sight lines broken by four small obsidian monolith clusters on
# the approaches. Every route between bases crosses the plaza, so the fight
# is about who can hold the middle without overextending.

const NAME: String = "Crossroads"
const MAX_PLAYERS: int = 4

const SEED: int = 912331155

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 6
const TRIPLETS_Z: int = 6
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# All four corners of the 360x360 arena. Chosen for equal starting AoE (76
# tiles each, radius-6 BFS).
const MCP_ARRAY: Array[int] = [105, 444, 1015, 1285]

# Pre-lowered staging pads at the four bases plus the central plaza (r 45
# about the centre).
const LOWERED: Array[int] = [
	# p1 pad
	58, 100, 101, 102, 103, 104, 105, 108, 109, 162, 163, 166, 167, 168,
	169, 170, 171, 244, 245,
	# p2 pad
	367, 368, 440, 441, 442, 443, 444, 445, 448, 517, 518, 521, 522, 523,
	526, 600, 601,
	# p3 pad
	857, 858, 932, 933, 934, 935, 936, 937, 940, 941, 1010, 1011, 1014,
	1015, 1016, 1017, 1018, 1019, 1091, 1092,
	# p4 pad
	1137, 1138, 1209, 1210, 1211, 1212, 1213, 1214, 1217, 1280, 1281,
	1284, 1285, 1286, 1287, 1288, 1289, 1330, 1331,
	# central plaza
	810, 809, 806, 805, 802, 801, 732, 731, 730, 729, 728, 727, 726, 725,
	724, 723, 722, 721, 718, 717, 656, 655, 654, 653, 652, 651, 650, 649,
	648, 647, 646, 645, 644, 643, 579, 578, 575, 574, 571, 570,
]

# Four obsidian monolith clusters on the plaza approaches — sight-line
# breakers and no-build anchors.
const IMMUTABLE: Array[int] = [
	408, 409, 412, 413, 485, 486, 487, 488, 489, 490, 503, 504, 564, 565,
	580, 581, 582, 583, 657, 658, 715, 716, 793, 794, 811, 812, 887, 888,
]

const INVISIBLE: Array[int] = []

const STARTING_BUILDINGS: Array = []
