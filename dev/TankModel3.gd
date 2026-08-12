@tool
extends TankModelBase
class_name TankModel3

# Design 3 — "Treadbunker": a squat assault variant. Two big side wheels
# (standing torus rings) carry the zoomba hull like a tracked platform, with
# a sloped front wedge and a rear hatch block. The top hatch ring frames a
# boxy cannon with a square emitter block and twin fuel cells.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	var wheel := _torus(0.95, 1.12, 48, 12)
	_part(self, wheel, dark, Vector3(-1.7, 1.1, 0), Vector3(90, 0, 0))
	_part(self, wheel, dark, Vector3(1.7, 1.1, 0), Vector3(90, 0, 0))

	_part(self, _box(0.9, 0.9, 3.4), shell, Vector3(-1.55, 1.65, 0), Vector3(0, 0, -30))
	_part(self, _box(0.8, 0.7, 2.4), shell, Vector3(1.55, 1.7, 0))
	_part(self, _torus(0.5, 0.58, 32, 8), dark, Vector3(0, 1.95, 0))

	_build_laser(2.2, 1.0, 0.3, shell)
	_part(_laser, _box(0.8, 0.5, 0.8), dark, Vector3(0, 0.4, 0))
	_part(_laser, _box(0.24, 0.55, 0.24), chrome, Vector3(-0.55, 0.42, 0))
	_part(_laser, _box(0.24, 0.55, 0.24), chrome, Vector3(0.55, 0.42, 0))
	_part(_laser, _torus(0.3, 0.36, 16, 6), glow, Vector3(0, 0.95, 0))
	_part(_laser, _sphere(0.1), glow, Vector3(0, 1.05, 0))
