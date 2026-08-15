extends Node

# --- Level data: forge (4-player fortress) ---
#
# Synopsis: four corner bases surround a central obsidian fortress — a ring
# wall with four permanent obsidian-floor gates, one on each diagonal, around
# a pre-lowered generator-rich core. Pre-lowered approach ramps run from every
# pad to its gate, and each player starts with a GEN mid-ramp: the forge's
# core is the prize, but four gates means every push has three flanks.

const NAME: String = "Forge"
const MAX_PLAYERS: int = 4

const SEED: int = 456789012345

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 6
const TRIPLETS_Z: int = 6
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# All four corners. Chosen for equal starting AoE (76 tiles each, radius-6
# BFS; 95 with the starting GENs).
const MCP_ARRAY: Array[int] = [113, 450, 1028, 1297]

# Pre-lowered staging pads at the four bases, the approach ramps (one per
# base, from pad to gate), the forge core (BFS rings 0-3 about tile 743) and
# the four permanent gate floors.
const LOWERED: Array[int] = [
	# p1 pad
	66, 108, 109, 110, 111, 112, 113, 116, 117, 166, 167, 170, 171, 172,
	173, 174, 175, 247, 248,
	# p2 pad
	371, 372, 446, 447, 448, 449, 450, 451, 454, 525, 526, 529, 530, 531,
	534, 609, 610,
	# p3 pad
	874, 875, 945, 946, 947, 948, 949, 950, 953, 954, 1023, 1024, 1027,
	1028, 1029, 1030, 1031, 1032, 1105, 1106,
	# p4 pad
	1151, 1152, 1224, 1225, 1226, 1227, 1228, 1229, 1232, 1292, 1293,
	1296, 1297, 1298, 1299, 1300, 1301, 1348, 1349,
	# approach ramps
	172, 173, 247, 248, 249, 250, 253, 254, 325, 326, 329, 330, 331, 332,
	408, 409, 410, 411, 438, 439, 442, 443, 446, 447, 489, 490, 517, 518,
	519, 520, 521, 522, 525, 526, 597, 598, 728, 729, 802, 803, 804, 805,
	806, 807, 878, 879, 880, 881, 882, 883, 884, 885, 951, 952, 953, 954,
	955, 956, 985, 986, 1031, 1032, 1063, 1064, 1065, 1066, 1141, 1142,
	1143, 1144,
	# forge core
	580, 583, 584, 656, 657, 658, 659, 660, 661, 662, 663, 664, 666, 667,
	734, 737, 738, 739, 740, 741, 742, 743, 744, 745, 746, 747, 748, 816,
	817, 820, 821, 822, 825,
	# obsidian-floor gates (also in IMMUTABLE)
	500, 573, 577, 578, 579, 670, 733, 736, 749, 812, 813, 814, 815, 824,
	826, 827, 905,
]

# The forge's ring wall (full boundary band about tile 743) with four
# permanent obsidian-floor gates on the diagonals.
const IMMUTABLE: Array[int] = [
	503, 504, 575, 576, 581, 582, 585, 586, 587, 588, 652, 653, 654, 655,
	665, 668, 671, 730, 735, 750, 751, 752, 818, 819, 823, 829, 896, 897,
	900, 901, 902,
	500, 573, 577, 578, 579, 670, 733, 736, 749, 812, 813, 814, 815, 824,
	826, 827, 905,
]

const INVISIBLE: Array[int] = []

# A constructed GEN for each player mid-ramp — forward economy on the way to
# the forge.
const STARTING_BUILDINGS: Array = [
	{"tile": 254, "pnum": 1, "type": BuildingManager.Type.GEN},
	{"tile": 522, "pnum": 2, "type": BuildingManager.Type.GEN},
	{"tile": 956, "pnum": 3, "type": BuildingManager.Type.GEN},
	{"tile": 1146, "pnum": 4, "type": BuildingManager.Type.GEN},
]
