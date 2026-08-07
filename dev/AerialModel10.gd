@tool
extends AerialModelBase
class_name AerialModel10

# Design 10 — "Vulture": a wide armoured hover-skiff. A broad deck carries a
# raised command bubble and side pods; four repulsor pads hover-glow beneath
# while the deck cannon points the way.

func _build_design() -> void:
	_build_core(_box(1.9, 0.3, 2.3))

	var hull := _mat(Color(0.13, 0.14, 0.17), 0.9, 0.32)
	var dark := _mat(Color(0.04, 0.04, 0.05), 0.6, 0.5)
	var chrome := _mat(Color(0.8, 0.84, 0.9), 1.0, 0.13)
	var glass := _mat(Color(0.5, 0.78, 0.95), 0.1, 0.05, Color(0.4, 0.7, 1.0), 1.5, false, 0.6)
	var cyan := _mat(Color(0.2, 0.9, 1.0), 0.0, 0.3, Color(0.2, 0.9, 1.0), 3.0, true)
	var orange := _mat(Color(1.0, 0.5, 0.05), 0.0, 0.3, Color(1.0, 0.5, 0.05), 3.0, true)
	var red := _mat(Color(1.0, 0.15, 0.15), 0.0, 0.3, Color(1.0, 0.15, 0.15), 3.0, true)

	# Nose plate
	_part(self, _box(0.8, 0.16, 0.7), dark, Vector3(0, 0.06, 1.35))
	# Command pylon + bubble
	_part(self, _box(0.5, 0.5, 0.5), chrome, Vector3(0, 0.48, -0.5))
	_part(self, _hemisphere(0.2), glass, Vector3(0, 0.7, -0.5))
	# Antenna + beacon
	_part(self, _cyl(0.015, 0.015, 0.5, 6), chrome, Vector3(0, 0.85, -0.9))
	var beacon := Node3D.new()
	beacon.position = Vector3(0, 1.15, -0.9)
	add_child(beacon)
	_part(beacon, _sphere(0.06), red, Vector3.ZERO)
	_add_pulse(beacon, 6.0, 0.0)
	# Side pods
	_part(self, _box(0.5, 0.35, 1.0), dark, Vector3(1.15, 0.14, -0.2))
	_part(self, _box(0.5, 0.35, 1.0), dark, Vector3(-1.15, 0.14, -0.2))
	# Repulsor pads
	var i := 0.0
	for c in [[1.2, 0.9], [1.2, -0.9], [-1.2, 0.9], [-1.2, -0.9]]:
		_part(self, _cyl(0.12, 0.12, 0.25, 10), chrome, Vector3(c[0], 0.05, c[1]))
		var pad := Node3D.new()
		pad.position = Vector3(c[0], -0.3, c[1])
		add_child(pad)
		_part(pad, _cyl(0.35, 0.35, 0.03, 16), cyan, Vector3.ZERO)
		_add_pulse(pad, 5.0, i)
		i += 1.57
	# Engine block + glows
	_part(self, _box(0.9, 0.4, 0.45), dark, Vector3(0, 0.35, -1.15))
	var en1 := Node3D.new()
	en1.position = Vector3(0.3, 0.35, -1.4)
	add_child(en1)
	_part(en1, _cyl(0.18, 0.18, 0.08, 12), orange, Vector3.ZERO, Vector3(90, 0, 0))
	_add_pulse(en1, 5.0, 0.0)
	var en2 := Node3D.new()
	en2.position = Vector3(-0.3, 0.35, -1.4)
	add_child(en2)
	_part(en2, _cyl(0.18, 0.18, 0.08, 12), orange, Vector3.ZERO, Vector3(90, 0, 0))
	_add_pulse(en2, 5.0, 3.14)
	# Side guns
	_part(self, _cyl(0.04, 0.04, 0.5, 8), dark, Vector3(1.0, 0.08, 1.25), Vector3(90, 0, 0))
	_part(self, _cyl(0.04, 0.04, 0.5, 8), dark, Vector3(-1.0, 0.08, 1.25), Vector3(90, 0, 0))
	# Skid fins
	_part(self, _box(0.08, 0.35, 0.6), dark, Vector3(0.85, -0.22, 0))
	_part(self, _box(0.08, 0.35, 0.6), dark, Vector3(-0.85, -0.22, 0))
	# Deck cannon
	_build_gun(Vector3(0, 0.04, 1.05), 1.3, 0.13, chrome)
	_part($Gun, _box(0.32, 0.2, 0.3), dark, Vector3(0, -0.06, 0.1))
