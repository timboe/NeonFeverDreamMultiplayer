extends Node

# --- Level data: crescent (3-player asymmetric) ---
#
# Synopsis: a deliberately asymmetric three-way free-for-all. A crescent of
# obsidian hugs the map's south-east rim — a landmark wall that offers the
# corners behind it a natural defensive flank. The rest of the arena is a wide
# pre-lowered flood plain dotted with invisible sinkholes. Every player starts
# with a constructed GEN out on the plain, so territory is contested from the
# first second: the crescent is the only shelter.

const NAME: String = "Crescent"
const MAX_PLAYERS: int = 3

const SEED: int = 8855224411

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 6
const TRIPLETS_Z: int = 6
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# Three corners of the 360x360 arena. Chosen for equal starting AoE (95 tiles
# each, radius-6 BFS; 141 with the starting GENs).
const MCP_ARRAY: Array[int] = [173, 1229, 948]

# Pre-lowered staging pads at the three bases plus the flood plain (r 85
# about the centre).
const LOWERED: Array[int] = [
	# p1 pad
	110, 111, 169, 170, 171, 172, 173, 174, 177, 178, 244, 245, 248, 249,
	250, 251, 252, 253, 327, 328,
	# p2 pad
	1073, 1074, 1147, 1148, 1149, 1150, 1151, 1152, 1155, 1224, 1225,
	1228, 1229, 1230, 1231, 1232, 1233, 1293, 1294,
	# p3 pad
	791, 792, 866, 867, 868, 869, 870, 873, 874, 944, 945, 948, 949, 950,
	951, 952, 953, 1027, 1028,
	# flood plain
	413, 414, 417, 418, 421, 422, 425, 426, 489, 490, 491, 492, 493, 494,
	495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 509, 510,
	568, 569, 570, 571, 572, 573, 574, 575, 576, 577, 578, 579, 580, 582,
	583, 584, 585, 586, 587, 588, 589, 590, 591, 594, 595, 646, 647, 648,
	649, 650, 651, 652, 653, 654, 655, 656, 657, 658, 659, 660, 661, 662,
	663, 664, 665, 666, 668, 669, 670, 671, 672, 673, 725, 726, 727, 728,
	729, 730, 731, 732, 733, 734, 735, 736, 737, 738, 739, 740, 741, 742,
	743, 744, 745, 746, 747, 748, 749, 750, 751, 752, 805, 806, 809, 810,
	811, 812, 813, 814, 815, 816, 817, 818, 819, 820, 821, 822, 823, 824,
	825, 826, 827, 828, 829, 830, 887, 888, 891, 893, 894, 895, 896, 897,
	898, 899, 900, 901, 902, 903, 904, 972, 973, 976, 977, 980, 981,
]

# The crescent: a contiguous obsidian chain across the south-east quadrant
# (angles ~-95 to ~15 degrees), clear of all three starting AoEs.
const IMMUTABLE: Array[int] = [
	188, 187, 190, 269, 268, 271, 352, 351, 354, 436, 435, 438, 520, 519,
	522, 600, 603, 678, 681, 757, 760, 837, 840, 915, 918,
]

# Sinkholes — invisible pits (collision kept) scattered across the flood plain
# as no-build zones and visual drama.
const INVISIBLE: Array[int] = [
	892, 581, 667,
]

# A constructed GEN for each player out on the flood plain — exposed claims on
# shared ground.
const STARTING_BUILDINGS: Array = [
	{"tile": 418, "pnum": 1, "type": BuildingManager.Type.GEN},
	{"tile": 902, "pnum": 2, "type": BuildingManager.Type.GEN},
	{"tile": 883, "pnum": 3, "type": BuildingManager.Type.GEN},
]
