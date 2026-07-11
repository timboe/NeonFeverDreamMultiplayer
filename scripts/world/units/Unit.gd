extends Node3D

class_name Unit

enum State {IDLE, PATHING, WORKING}

var state : int = State.IDLE

var building : Building

func initialise_base(b : Building):
	building = b
	global_transform.origin = building.find_unit_spawn_location()
