@tool
extends AerialModelBase
class_name AerialModel5

# Design 5 — "Eclipse": a scythe-blade fighter wrapped in a ring of lunar
# shadow. The fuselage is the hilt, the great halo is the edge, and the ring
# wheels slowly to keep the blade level.

func _build_design() -> void:
	_build_core(_box(0.4, 0.3, 1.4))

	var hull := _mat(Color(0.15, 0.16, 0.2), 0.9, 0.3)
	var dark := _mat(Color(0.04, 0.04, 0.05), 0.7, 0.4)
	var chrome := _mat(Color(0.85, 0.87, 0.92), 1.0, 0.1)
	var cyan := _mat(Color(0.3, 0.95, 1.0), 0.0, 0.25, Color(0.3, 0.95, 1.0), 3.5, true)
	var orange := _mat(Color(1.0, 0.45, 0.05), 0.0, 0.3, Color(1.0, 0.45, 0.05), 3.0, true)

	# The great eclipse halo
	var halo := Node3D.new()
	add_child(halo)
	halo.scale = Vector3(1, 1, 0.6)
	_part(halo, _torus(1.1, 1.28, 64, 10), dark, Vector3.ZERO, Vector3(90, 0, 0))
	_part(halo, _torus(1.14, 1.18, 64, 10), cyan, Vector3.ZERO, Vector3(90, 0, 0))
	_add_spin(halo, 1.1)

	# Blade (fore) and counter-blade (aft)
	_part(self, _box(0.14, 0.06, 1.6), chrome, Vector3(0, 0.14, 0.7))
	_part(self, _box(0.14, 0.06, 0.7), chrome, Vector3(0, 0.14, -0.8))
	# Crescent tips
	_part(self, _box(0.85, 0.07, 0.2), dark, Vector3(0.7, 0.1, 0.3), Vector3(0, 45, 0))
	_part(self, _box(0.85, 0.07, 0.2), dark, Vector3(-0.7, 0.1, 0.3), Vector3(0, -45, 0))
	# Rear engine glows
	var e1 := Node3D.new()
	e1.position = Vector3(0.12, 0.05, -1.15)
	add_child(e1)
	_part(e1, _sphere(0.08), orange, Vector3.ZERO)
	_add_pulse(e1, 5.0, 0.0)
	var e2 := Node3D.new()
	e2.position = Vector3(-0.12, 0.05, -1.15)
	add_child(e2)
	_part(e2, _sphere(0.08), orange, Vector3.ZERO)
	_add_pulse(e2, 5.0, 3.14)

	# Gun on the blade line
	_build_gun(Vector3(0, 0.06, 0.45), 1.1, 0.05, chrome)
