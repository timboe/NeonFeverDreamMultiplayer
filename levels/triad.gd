extends Node

# --- Level data: triad (3-player drum) ---
#
# Synopsis: three-way free-for-all on the 360x360 arena. Bases sit at three
# corners; the centre holds a pre-lowered bowl ("the drum") ringed by raised
# obsidian with three permanent obsidian-floor gates, one facing each base.
# Every player also starts with a constructed GEN just outside their gate —
# the drum's rich ground is contested from turn one. Two-front pressure is
# the whole game: hold your gate, raid through a neighbour's.

const NAME: String = "Triad"
const MAX_PLAYERS: int = 3

const SEED: int = 411236789123

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 6
const TRIPLETS_Z: int = 6
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# Three corners of the 360x360 arena. Chosen for equal starting AoE — union
# of MCP + starting GEN = 154 tiles each (radius-6/4 BFS).
const MCP_ARRAY: Array[int] = [177, 1231, 871]

# Pre-lowered staging pads at the three bases plus the drum bowl (BFS rings
# 0-3 about tile 736).
const LOWERED: Array[int] = [
	# p1 pad
	113, 114, 173, 174, 175, 176, 177, 178, 181, 182, 246, 247, 250, 251,
	252, 253, 254, 255, 330, 331,
	# p2 pad
	1071, 1072, 1147, 1148, 1149, 1150, 1151, 1152, 1155, 1225, 1226,
	1229, 1230, 1231, 1232, 1233, 1234, 1299, 1300,
	# p3 pad
	789, 790, 867, 868, 869, 870, 871, 874, 875, 941, 942, 945, 946, 947,
	948, 949, 950, 1025, 1026,
	# drum bowl
	574, 577, 578, 649, 650, 651, 652, 653, 654, 655, 656, 657, 659, 660,
	727, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 811,
	812, 815, 816, 817, 820,
	# obsidian-floor gates (also in IMMUTABLE)
	498, 567, 571, 572, 573, 726, 729, 742, 807, 808, 809, 810, 819, 821,
	822, 901,
]

# The drum's raised obsidian ring (full boundary band about tile 736) with
# three permanent obsidian-floor gates at 120 degrees, one facing each base.
const IMMUTABLE: Array[int] = [
	501, 502, 569, 570, 575, 576, 579, 580, 581, 582, 645, 646, 647, 648,
	658, 661, 663, 664, 723, 728, 743, 744, 745, 813, 814, 818, 824, 892,
	893, 896, 897, 898,
	498, 567, 571, 572, 573, 726, 729, 742, 807, 808, 809, 810, 819, 821,
	822, 901,
]

const INVISIBLE: Array[int] = []

# A constructed GEN for each player on their gate approach — the drum's
# generator-rich ground is in play immediately.
const STARTING_BUILDINGS: Array = [
	{"tile": 415, "pnum": 1, "type": BuildingManager.Type.GEN},
	{"tile": 981, "pnum": 2, "type": BuildingManager.Type.GEN},
	{"tile": 801, "pnum": 3, "type": BuildingManager.Type.GEN},
]
