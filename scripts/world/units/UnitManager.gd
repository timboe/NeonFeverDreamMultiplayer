extends Node3D

class_name UnitManager

enum Type {NONE, ZOOMBA, TANK, AERIAL_PATROL, AERIAL_SCOUT, VIRUS}

# Multiplayer synchronised
var unit_dictionary : Dictionary

func _ready() -> void:
	pass # Replace with function body.

# TODO - genericse this to different units
func spawn_unit(type : Type, building : Building):
	var u = null
	match type:
		Type.ZOOMBA: u = $UnitFactory/Zoomba.duplicate()
	u.initialise(building)
	add_to_dict_and_scene(u)
	#spawn_particles.emitting = true
	return u

func add_to_dict_and_scene(u : Unit):
	u.id = unit_dictionary.size()
	unit_dictionary[u.id] = u
	add_child(u)
