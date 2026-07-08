extends Node

class_name PathingManager

@onready var astar : Array 

func _ready():
	# The 0-MAX_PLAYERS networks are used to track the monorail network (with 
	# per-player one-way instructions included)
	# The +1 network is used to track the destroyed tiles network
	for _i in range(Global.MAX_PLAYERS + 1):
		astar.push_back( AStar3D.new() )

func add_tile(tile : TileElement):
	for i in range(Global.MAX_PLAYERS + 1):
		astar[i].add_point( tile.get_id(), tile.pathing_centre )

func disconnect_tiles(player : int, a : TileElement, b : TileElement):
	astar[player].disconnect_points(a.get_id(), b.get_id())

func are_tiles_connected(player : int, a : TileElement, b : TileElement) -> bool:
	return (pathfind(player, a, b).size() > 0)

func connect_tiles(player : int, from : TileElement, to : TileElement, bidirectional : bool):
	astar[player].connect_points(from.get_id(), to.get_id(), bidirectional) 

func pathfind(player, from : TileElement, to : TileElement) -> PackedInt64Array:
	return astar[player].get_id_path(from.get_id(), to.get_id())

func get_point(id : int) -> Vector3:
	return astar[0].get_point_position(id) # we could have used any of the instances
	
func get_tile(id : int) -> TileElement:
	return $"../../TileManager".tile_dictionary[id]
