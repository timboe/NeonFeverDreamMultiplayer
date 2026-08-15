extends Node

# --- Level data: spokes (3-player hub) ---
#
# Synopsis: three-way free-for-all with three rim bases and pre-lowered spoke
# corridors converging on a central hub plaza. Each spoke passes an obsidian
# pinch wall with a narrow gate — the only pre-lowered crossing on that spoke.
# Walling your gate defends your approach but cuts your expansion, so every
# player must decide when the hub is worth leaving home for. Each base also
# starts with a VAT, giving an early storage edge.

const NAME: String = "Spokes"
const MAX_PLAYERS: int = 3

const SEED: int = -57710263945

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 6
const TRIPLETS_Z: int = 6
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# Three corners of the 360x360 arena. Chosen for equal starting AoE (91 tiles
# each, radius-6 BFS, with the pinch walls in place).
const MCP_ARRAY: Array[int] = [175, 1148, 944]

# Pre-lowered staging pads at the three bases, the central hub plaza (r 50
# about the centre) and the three spoke corridors (path + band about each
# spoke line, minus the pinch walls).
const LOWERED: Array[int] = [
	# p1 pad
	112, 113, 171, 172, 173, 174, 175, 176, 179, 180, 244, 245, 248, 249,
	250, 251, 252, 253, 326, 327,
	# p2 pad
	1070, 1071, 1144, 1145, 1146, 1147, 1148, 1149, 1152, 1221, 1222,
	1225, 1226, 1227, 1228, 1229, 1230, 1291, 1292,
	# p3 pad
	786, 787, 863, 864, 865, 866, 867, 870, 871, 940, 941, 944, 945, 946,
	947, 948, 949, 1024, 1025,
	# hub plaza
	575, 574, 571, 570, 500, 499, 496, 495, 494, 493, 490, 489, 415, 414,
	411, 410, 408, 333, 331, 330, 255, 254, 253, 252, 180, 179, 1143,
	1142, 1139, 1138, 1067, 1066, 1063, 1062, 1060, 983, 981, 980, 903,
	902, 901, 900, 897, 896, 823, 822, 819, 818, 869, 868, 801, 800, 797,
	796, 794, 792, 791, 790, 724, 723, 722, 721, 720, 719, 716, 644, 643,
]

# The three obsidian pinch walls across the spokes, each leaving a narrow
# gate (2 tiles) for the pre-lowered corridor.
const IMMUTABLE: Array[int] = [
	332, 336, 337, 406, 407, 409, 412, 413, 485, 486, 635, 636, 713, 714,
	715, 793, 795, 872, 873, 906, 907, 978, 979, 982, 984, 985, 1056,
	1057, 1061,
]

const INVISIBLE: Array[int] = []

# A constructed VAT beside each MCP — early storage, slightly offset from the
# command post.
const STARTING_BUILDINGS: Array = [
	{"tile": 176, "pnum": 1, "type": BuildingManager.Type.VAT},
	{"tile": 1225, "pnum": 2, "type": BuildingManager.Type.VAT},
	{"tile": 945, "pnum": 3, "type": BuildingManager.Type.VAT},
]
