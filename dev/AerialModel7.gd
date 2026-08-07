@tool
extends AerialModelBase
class_name AerialModel7

# Design 7 — "Barracuda": a manta-ray dive bomber. Wide pectoral wings rake
# back from a flattened keel; the chin gun sits low so it can strafe while the
# wing tips ripple up and down.

func _build_design() -> void:
	_build_core(_capsule(0.36, 1.0))
	_csg.rotation_degrees = Vector3(90, 0, 0)
	_csg.scale = Vector3(1, 0.62, 1)

	var hull := _mat(Color(0.12, 0.14, 0.18), 0.9, 0.3)
	var dark := _mat(Color(0.05, 0.05, 0.07), 0.7, 0.45)
	var chrome := _mat(Color(0.82, 0.85, 0.9), 1.0, 0.12)
	var cyan := _mat(Color(0.15, 0.9, 1.0), 0.0, 0.25, Color(0.15, 0.9, 1.0), 3.5, true)
	var orange := _mat(Color(1.0, 0.5, 0.05), 0.0, 0.3, Color(1.0, 0.5, 0.05), 3.0, true)

	# Pectoral wings (tips ripple up and down)
	for side in [-1, 1]:
		var wing := Node3D.new()
		wing.position = Vector3(0, 0.0, -0.15)
		add_child(wing)
		_add_flap(wing, 3.5, 0.14, 0.0 if side < 0 else 3.14, Vector3(0, 0, float(side)))
		_part(wing, _box(1.8, 0.06, 1.7), dark, Vector3(side * 0.95, 0.06, 0.1), Vector3(0, -12 * side, 14 * side))
		_part(wing, _box(0.06, 0.25, 0.5), dark, Vector3(side * 1.85, 0.16, 0.0))

	# Tail
	_part(self, _box(0.07, 0.07, 0.9), dark, Vector3(0, 0.08, -1.35))
	_part(self, _box(0.3, 0.28, 0.05), dark, Vector3(0, 0.26, -1.6))
	# Eyes on the crown
	_part(self, _sphere(0.06), cyan, Vector3(0.16, 0.35, 0.65))
	_part(self, _sphere(0.06), cyan, Vector3(-0.16, 0.35, 0.65))
	# Rear engine
	var eng := Node3D.new()
	eng.position = Vector3(0, 0.1, -0.6)
	add_child(eng)
	_part(eng, _sphere(0.1), orange, Vector3.ZERO)
	_add_pulse(eng, 5.0, 0.0)
	# Chin gun
	_build_gun(Vector3(0, -0.32, 0.45), 0.8, 0.07, chrome)
	_part($Gun, _cyl(0.05, 0.05, 0.7, 10), dark, Vector3(0.16, 0, 0.4), Vector3(90, 0, 0))
	_part($Gun, _cyl(0.05, 0.05, 0.7, 10), dark, Vector3(-0.16, 0, 0.4), Vector3(90, 0, 0))
