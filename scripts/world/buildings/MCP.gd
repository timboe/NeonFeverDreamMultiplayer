extends Building

class_name MCP

# Note: would like to also extend Generator, but just re-impliment the functionality instead

var to_rotate : Array
const A_VELOCITY = 100

const BASE_GENERATION := 27.0
const BASE_CAPACITY := 1000.0

const ZOOMBA_CREATION_COOLDOWN_TICKS := 10
const AVATAR_CREATION_COOLDOWN_TICKS := 10

var cooldown_ticks := 0

func _ready():
	if name == "MCP_1":
		to_rotate.append($MCPTop)
		to_rotate.append($MCPFaceTop)
		to_rotate.append($MCPBottom)
		to_rotate.append($MCPFaceBottom)

func _process(delta):
	for to_rot in to_rotate:
		to_rot.rotate_object_local(Vector3.UP, delta * A_VELOCITY)

func zoomba_cap() -> int:
	var tm = get_node_or_null("/root/World/TileManager")
	return floor(sqrt( tm.player_aoe_totals[player_owner] ))

func check_work():
	if not multiplayer.is_server():
		return
	if cooldown_ticks:
		cooldown_ticks -= 1
		return
	var um = get_node_or_null("/root/World/UnitManager")
	var to_spawn = UnitManager.Type.NONE
	if um.unit_count(player_owner, UnitManager.Type.AVATAR) < 1:
		to_spawn = UnitManager.Type.AVATAR
		cooldown_ticks = AVATAR_CREATION_COOLDOWN_TICKS
	elif um.unit_count(player_owner, UnitManager.Type.ZOOMBA) < zoomba_cap():
		to_spawn = UnitManager.Type.ZOOMBA
		cooldown_ticks = ZOOMBA_CREATION_COOLDOWN_TICKS
		print("new zoomba for player ",player_owner," (cap is ",zoomba_cap(),")")
	if to_spawn != UnitManager.Type.NONE:
		var uid = um.get_inc_next_unit_id() # Server dictates the ID for extra safety
		um.rpc("rpc_spawn_unit", uid, to_spawn, self.id)

func initialise(pnum : int, tile : TileElement, t : BuildingManager.Type):
	initialise_base(pnum, tile, t)
	add_to_group("generator")
	add_to_group("generator_player"+str(pnum))
	add_to_group("mcp")
	add_to_group("mcp_player"+str(pnum))
	add_to_group("vat")
	add_to_group("vat_player"+str(pnum))

func get_energy() -> float:
	return BASE_GENERATION
	
func get_capacity():
	return BASE_CAPACITY
