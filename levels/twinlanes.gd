extends Node

# --- Level data: twinlanes (4-player dual lane) ---

const NAME: String = "Twin Lanes"
const MAX_PLAYERS: int = 4

const SEED: int = -7733992211

# TRIPLETS_X drives the world x extent, TRIPLETS_Z the world z extent
# (see TileManager._generate).
const TRIPLETS_X: int = 6
const TRIPLETS_Z: int = 6
const BORDER_TRIPLETS: int = 2
const MOUNTAINS: int = 5

const MCP_ARRAY: Array[int] = []

const LOWERED: Array[int] = []

const IMMUTABLE: Array[int] = []

const INVISIBLE: Array[int] = []

const STARTING_BUILDINGS: Array = []
