extends Node3D

class_name Unit

var id : int # My ID within the UnitManager
var building : Building # Building which spawned me (designates owner)

enum State {IDLE, PATHING, WORKING}

var state : int = State.IDLE


func initialise_base(b : Building):
	building = b
	global_transform.origin = building.find_unit_spawn_location()
	add_to_group("unit")
