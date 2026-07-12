extends Node3D

class_name UnitManager

enum Type {NONE, ZOOMBA, TANK, AERIAL_PATROL, AERIAL_SCOUT, VIRUS}

# Multiplayer synchronised
var unit_dictionary : Dictionary

var _next_unit_id: int = 0

func _ready() -> void:
	pass # Replace with function body.
	
func units() -> Array:
	return unit_dictionary.values()

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
	u.id = _next_unit_id
	_next_unit_id += 1
	unit_dictionary[u.id] = u
	add_child(u)

func remove_unit(id: int):
	var u = unit_dictionary.get(id)
	if u:
		unit_dictionary.erase(id)
		u.queue_free()
