extends Node

# --- Level data: canyons (2-player long narrow map) ---
#
# Synopsis: a long, narrow 1v1 strip (480 world z x 180 world x). Two zigzag
# obsidian ridges plus an east-side spur wall the strip into dead-end side
# lanes; the pre-lowered centre corridor is the only through-route, so every
# push funnels through it while aerials and cloaked viruses play the margins.
# Invisible sinkholes litter the side lanes as no-build zones. Generator tiles
# are deliberately scarce, so each player starts with a constructed GEN on
# their staging pad.

const NAME: String = "Canyons"
const MAX_PLAYERS: int = 2

const SEED: int = -707022117411

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate). Long in world z, narrow in world x.
const TRIPLETS_X: int = 3
const TRIPLETS_Z: int = 8
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

# Both ends of the long axis. Chosen for equal starting AoE (96 tiles each,
# radius-6 BFS).
const MCP_ARRAY: Array[int] = [222, 935]

# Base staging pads plus the central pre-lowered corridor — the only route
# between the ends: the obsidian ridges below are unbroken except where they
# cross this corridor (their gaps).
const LOWERED: Array[int] = [
	# p1 pad
	123, 124, 169, 170, 171, 172, 173, 174, 177, 178, 217, 218, 221, 222,
	223, 224, 225, 226, 269, 270,
	# p2 pad
	840, 841, 884, 885, 886, 887, 888, 889, 892, 893, 931, 932, 935, 936,
	937, 938, 939, 940, 982, 983,
	# centre corridor (x 85-115, full length)
	123, 124, 171, 172, 173, 174, 221, 222, 223, 224, 267, 268, 269, 270,
	271, 272, 315, 316, 317, 318, 319, 320, 362, 363, 364, 365, 412, 413,
	414, 415, 457, 458, 459, 460, 461, 462, 505, 506, 507, 508, 509, 510,
	557, 558, 559, 560, 606, 607, 608, 609, 610, 611, 653, 654, 655, 656,
	657, 658, 704, 705, 706, 707, 751, 752, 753, 754, 797, 798, 799, 800,
	801, 802, 842, 843, 844, 845, 846, 847, 890, 891, 892, 893, 939, 940,
	941, 942, 986, 987,
]

# Two diagonal obsidian ridges zigzagging across the strip (they follow the
# natural tiling diagonals) plus a short spur on the east side. Each ridge
# leaves its centre-corridor crossing open, so the pre-lowered corridor is the
# only way through — east/west lanes are dead ends.
const IMMUTABLE: Array[int] = [
	# ridge 1 (z ~90-180)
	328, 323, 324, 311, 312, 307, 309, 306, 350, 352, 349, 396, 397,
	# ridge 2 (z ~280-360)
	593, 592, 595, 598, 599, 602, 603, 709, 708, 711, 760, 759, 762, 812,
	813,
	# east spur (z ~235-250)
	621, 616, 617, 612, 613,
]

# Sinkholes — invisible pits (collision kept) scattered through the margins as
# no-build zones and visual drama.
const INVISIBLE: Array[int] = [
	570, 568, 666, 399, 442, 492,
]

# Each player starts with a constructed GEN on their staging pad — the map's
# generator tiles are deliberately scarce outside the corridor.
const STARTING_BUILDINGS: Array = [
	{"tile": 171, "pnum": 1, "type": BuildingManager.Type.GEN},
	{"tile": 936, "pnum": 2, "type": BuildingManager.Type.GEN},
]
