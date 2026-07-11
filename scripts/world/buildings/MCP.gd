extends Building

class_name MCP

# Note: would like to also extend Generator, but just re-impliment the functionality instead

var to_rotate : Array
const A_VELOCITY = 100

const BASE_GENERATION = 100.0

func _ready():
	if name == "MCP_1":
		to_rotate.push_back($MCPTop)
		to_rotate.push_back($MCPFaceTop)
		to_rotate.push_back($MCPBottom)
		to_rotate.push_back($MCPFaceBottom)

func _process(delta):
	for to_rot in to_rotate:
		to_rot.rotate_object_local(Vector3.UP, delta * A_VELOCITY)

func initialise(tile : TileElement, pnum : int, t : BuildingManager.Type):
	initialise_base(tile, pnum, t)
	add_to_group("generator")
	add_to_group("mcp")

func get_tick_energy() -> float:
	return BASE_GENERATION
