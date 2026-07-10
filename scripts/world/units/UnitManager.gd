extends Node3D

class_name UnitManager

func _ready() -> void:
	pass # Replace with function body.

# TODO - genericse this to different units
func spawn_zoomba(building : Building):
	var zoomba = $UnitFactory/Zoomba.duplicate()
	add_child(zoomba)
	zoomba.initialise(building)
	var t = create_tween()
	zoomba.position.y = -2
	t.tween_property(zoomba, "position:y", 0, 5.0)
	t.tween_callback(zoomba_callback.bind(zoomba)).set_delay(5.0)
	#spawn_particles.emitting = true
	return zoomba

func zoomba_callback(z):
	print("zoomba created at ", z.position)
	#spawn_particles.emitting = false
	# TODO - after job system
	#z.idle_callback()
