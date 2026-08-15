extends Node

# --- Level data: twinlanes (4-player dual lane) ---
#
# Synopsis: two parallel 1v1 lanes split by a full-length obsidian spine that
# runs the map's north-south axis. Two cross-passages (gates in the spine) are
# the only ways between lanes. Works as a free-for-all or as a 2v2 arena via
# the per-player enemy lists: each lane is a one-on-one until someone breaks
# through a passage to swing the other fight. Every base starts with a VAT.

const NAME: String = "Twin Lanes"
const MAX_PLAYERS: int = 4

const SEED: int = -7733992211

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 6
const TRIPLETS_Z: int = 6
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# All four corners. Chosen for equal starting AoE (76 tiles each, radius-6
# BFS).
const MCP_ARRAY: Array[int] = [99, 440, 1017, 1289]

# Pre-lowered staging pads at the four bases (two per lane).
const LOWERED: Array[int] = [
	# p1 pad (west lane, north)
	57, 94, 95, 96, 97, 98, 99, 102, 103, 161, 162, 165, 166, 167, 168,
	169, 170, 237, 238,
	# p2 pad (east lane, north)
	361, 362, 436, 437, 438, 439, 440, 441, 444, 514, 515, 518, 519, 520,
	523, 599, 600,
	# p3 pad (west lane, south)
	860, 861, 934, 935, 936, 937, 938, 939, 942, 943, 1012, 1013, 1016,
	1017, 1018, 1019, 1020, 1021, 1095, 1096,
	# p4 pad (east lane, south)
	1141, 1142, 1216, 1217, 1218, 1219, 1220, 1221, 1224, 1284, 1285,
	1288, 1289, 1290, 1291, 1292, 1293, 1341, 1342,
]

# The full-length obsidian spine between the lanes, with two cross-passages
# left open (gates near z ~110 and z ~250).
const IMMUTABLE: Array[int] = [
	190, 185, 187, 184, 253, 255, 332, 333, 411, 488, 568, 569, 649, 650,
	727, 728, 725, 802, 956, 959, 1036, 1039, 1115, 1118, 1194, 1197,
	1264,
]

const INVISIBLE: Array[int] = []

# A constructed VAT beside each MCP — early storage in both lanes.
const STARTING_BUILDINGS: Array = [
	{"tile": 170, "pnum": 1, "type": BuildingManager.Type.VAT},
	{"tile": 441, "pnum": 2, "type": BuildingManager.Type.VAT},
	{"tile": 1018, "pnum": 3, "type": BuildingManager.Type.VAT},
	{"tile": 1288, "pnum": 4, "type": BuildingManager.Type.VAT},
]
