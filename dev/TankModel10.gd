@tool
extends TankModelBase
class_name TankModel10

# Design 10 — "Wraith": a shrouded infiltrator. Dark hood plates arc over the
# rear of the zoomba hull, a glowing visor strip spans its brow, radial spikes
# jut from the flanks and a small radar dome sits behind the turret. The
# cannon is a dark barrel built around a pulsing plasma orb.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	for i in 5:
		var a := PI * (0.5 + i / 4.0)
		_part(self, _box(0.62, 0.26, 1.0), dark, Vector3(cos(a) * 1.5, 2.0, sin(a) * 1.5), Vector3(0, 0, -15))

	_part(self, _box(0.12, 0.16, 1.6), glow, Vector3(-1.92, 1.5, 0))
	_part(self, _hemisphere(0.35), shell, Vector3(1.3, 1.8, 0))

	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		_part(self, _cone(0.16, 0.55, 8), chrome,
			Vector3(cos(a) * 1.85, 1.45, sin(a) * 1.85), Vector3(90, rad_to_deg(a), 0))

	_build_laser(2.25, 1.0, 0.18, dark)
	var orb := _part(_laser, _sphere(0.2), glow, Vector3(0, 0.35, 0))
	_add_pulse(orb, 6.0)
	_part(_laser, _torus(0.2, 0.24, 16, 6), glow, Vector3(0, 0.55, 0))
	_part(_laser, _torus(0.14, 0.18, 16, 6), glow, Vector3(0, 0.95, 0))
