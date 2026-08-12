@tool
extends TankModelBase
class_name TankModel9

# Design 9 — "Lancer": a duelling chariot. Forward-swept chrome blades brace
# the flanks, angled stabiliser skids trail at the rear, and the zoomba body
# itself is the mount for a single long lance-like barrel — a thin chrome
# shaft ringed by a glowing collar, with a splitter fin along its length.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	_part(self, _box(0.1, 1.3, 1.9), chrome, Vector3(-1.45, 1.5, -1.2), Vector3(0, 0, 15))
	_part(self, _box(0.1, 1.3, 1.9), chrome, Vector3(-1.45, 1.5, 1.2), Vector3(0, 0, 15))
	for sz in [-1.35, 1.35]:
		_part(self, _box(0.25, 0.9, 0.25), dark, Vector3(1.7, 0.95, sz), Vector3(25, 0, 0))

	_build_laser(2.1, 2.4, 0.1, chrome)
	_part(_laser, _cyl(0.13, 0.13, 1.1, SEG), dark, Vector3(0, 0.85, 0))
	_part(_laser, _torus(0.14, 0.18, 20, 6), glow, Vector3(0, 1.45, 0))
	_part(_laser, _box(0.06, 0.5, 0.38), shell, Vector3(0, 1.7, 0.15))
	_part(_laser, _torus(0.1, 0.13, 16, 6), glow, Vector3(0, 2.36, 0))
