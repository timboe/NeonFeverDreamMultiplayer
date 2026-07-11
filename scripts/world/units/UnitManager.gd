extends Node3D

class_name UnitManager

enum Type {NONE, ZOOMBA, TANK, AERIAL, VIRUS}

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
	u.position.y = -2
	var t = create_tween()
	t.tween_property(u, "position:y", 0, 5.0)
	t.tween_callback(new_unit_callback.bind(u)).set_delay(5.0)
	#spawn_particles.emitting = true
	return u

func add_to_dict_and_scene(u : Unit):
	u.id = unit_dictionary.size()
	unit_dictionary[u.id] = u
	add_child(u)

func new_unit_callback(new_unit):
	print("new unit created at ", new_unit.position)
	#spawn_particles.emitting = false
	# TODO - after job system
	#z.idle_callback()
