@tool
extends AerialModelBase
class_name AerialModel3

# Design 3 — "Gnat": a mosquito-scale strike insect. Glass wings beat on a
# segmented abdomen banded with magenta, ending in a long proboscis that
# doubles as the cannon.

func _build_design() -> void:
	_build_core(_capsule(0.28, 0.7))

	var shell := _mat(Color(0.12, 0.13, 0.16), 0.9, 0.3)
	var dark := _mat(Color(0.05, 0.05, 0.06), 0.6, 0.5)
	var wing := _mat(Color(0.5, 0.9, 1.0), 0.0, 0.2, Color(0.4, 0.8, 1.0), 1.5, false, 0.45)
	var magenta := _mat(Color(1.0, 0.2, 0.85), 0.0, 0.35, Color(1.0, 0.2, 0.85), 3.0, true)
	var eye := _mat(Color(1.0, 0.1, 0.2), 0.0, 0.2, Color(1.0, 0.1, 0.2), 4.0, true)

	# Thorax along +Z (player-coloured core)
	_csg.rotation_degrees = Vector3(90, 0, 0)

	# Head
	_part(self, _sphere(0.2), dark, Vector3(0, 0.22, 0.78))
	_part(self, _sphere(0.06), eye, Vector3(0.13, 0.3, 0.82))
	_part(self, _sphere(0.06), eye, Vector3(-0.13, 0.3, 0.82))
	# Antennae
	_part(self, _cyl(0.012, 0.012, 0.5, 6), dark, Vector3(0.1, 0.4, 0.7), Vector3(-25, 0, 30))
	_part(self, _cyl(0.012, 0.012, 0.5, 6), dark, Vector3(-0.1, 0.4, 0.7), Vector3(-25, 0, -30))

	# Abdomen
	_part(self, _capsule(0.2, 0.8), dark, Vector3(0, 0.12, -0.8), Vector3(90, 0, 0))
	# Magenta banding
	_part(self, _torus(0.17, 0.24), magenta, Vector3(0, 0.12, -0.6))
	_part(self, _torus(0.17, 0.24), magenta, Vector3(0, 0.12, -0.85))
	_part(self, _torus(0.17, 0.24), magenta, Vector3(0, 0.12, -1.1))
	# Stinger tip
	_part(self, _cone(0.12, 0.45, 10), dark, Vector3(0, 0.08, -1.35), Vector3(-90, 0, 0))

	# Wings: two flapping pairs
	for side in [-1, 1]:
		var pair := Node3D.new()
		pair.position = Vector3(0, 0.35, 0.0)
		add_child(pair)
		_add_flap(pair, 9.0, 0.4, 0.0 if side < 0 else 1.3, Vector3(0, 0, float(side)))
		_part(pair, _box(1.3, 0.03, 0.5), wing, Vector3(side * 0.8, 0, 0.1), Vector3(0, -35 * side, 0))
		_part(pair, _box(1.3, 0.03, 0.45), wing, Vector3(side * 0.85, 0, -0.25), Vector3(0, -30 * side, 0))

	# Proboscis gun
	_build_gun(Vector3(0, 0.18, 0.7), 1.1, 0.035, dark)
