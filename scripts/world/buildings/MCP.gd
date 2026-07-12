extends Building

class_name MCP

# Note: would like to also extend Generator, but just re-impliment the functionality instead

var to_rotate : Array
const A_VELOCITY = 100

const BASE_GENERATION := 100.0
const ZOOMBA_CREATON_COOLDOWN_TICKS := 10

var cooldown_ticks := 0

func _ready():
	if name == "MCP_1":
		to_rotate.push_back($MCPTop)
		to_rotate.push_back($MCPFaceTop)
		to_rotate.push_back($MCPBottom)
		to_rotate.push_back($MCPFaceBottom)

func _process(delta):
	for to_rot in to_rotate:
		to_rot.rotate_object_local(Vector3.UP, delta * A_VELOCITY)

func zoomba_cap() -> int:
	var tm = get_node_or_null("/root/World/TileManager")
	return floor(sqrt( tm.player_aoe_totals[player_owner] * 8 ))

func check_work():
	if not multiplayer.is_server():
		return
	if cooldown_ticks:
		cooldown_ticks -= 1
		return
	var um = get_node_or_null("/root/World/UnitManager")
	if um.unit_count(player_owner, UnitManager.Type.ZOOMBA) < zoomba_cap():		
		um.rpc("rpc_spawn_unit", UnitManager.Type.ZOOMBA, self.id)
		cooldown_ticks = ZOOMBA_CREATON_COOLDOWN_TICKS
		print("new zoomba for player ",player_owner," (cap is ",zoomba_cap(),")")

func initialise(tile : TileElement, pnum : int):
	var t : BuildingManager.Type
	match name:
		"MCP_1": t = BuildingManager.Type.MCP_1
		"MCP_2": t = BuildingManager.Type.MCP_2
		"MCP_3": t = BuildingManager.Type.MCP_3
		"MCP_4": t = BuildingManager.Type.MCP_4
	initialise_base(tile, pnum, t)
	add_to_group("generator")
	add_to_group("mcp")

func get_tick_energy() -> float:
	return BASE_GENERATION
