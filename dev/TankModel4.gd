@tool
extends TankModelBase
class_name TankModel4

# Design 4 — "Widow": a spider walker. Eight chrome legs splay out radially
# from under the zoomba body, fan-shaped dorsal plates trail behind it and
# twin antennae reach up beside the eyes. The top twin-barrel cannon mounts a
# four-sided chevron emitter block that pulses as it charges.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	for i in 8:
		var a := TAU * i / 8.0
		_part(self, _box(0.12, 1.3, 0.12), chrome,
			Vector3(cos(a) * 1.45, 0.8, sin(a) * 1.45),
			Vector3(rad_to_deg(cos(a)) * 18, 0, rad_to_deg(sin(a)) * 18))

	for i in 3:
		_part(self, _box(0.06, 0.85, 0.85), dark, Vector3(1.05, 2.05, -0.85 + i * 0.85), Vector3(0, 0, -40 + i * 20))

	for sz in [-0.35, 0.35]:
		_part(self, _cyl(0.02, 0.02, 0.55, 6), chrome, Vector3(-1.85, 1.6, sz), Vector3(0, 0, -20))
		_part(self, _sphere(0.05), glow, Vector3(-1.85, 2.18, sz))

	_build_laser(2.15, 1.0, 0.12, shell)
	_part(_laser, _cyl(0.12, 0.12, 1.0, SEG), shell, Vector3(-0.28, 0.5, 0))
	_part(_laser, _cyl(0.12, 0.12, 1.0, SEG), shell, Vector3(0.28, 0.5, 0))
	var chevron := _part(_laser, _cone(0.45, 0.4, 4), dark, Vector3(0, 0.3, 0), Vector3(0, 45, 0))
	_part(chevron, _cone(0.2, 0.25, 4), glow, Vector3(0, 0.12, 0))
	_part(_laser, _sphere(0.09), glow, Vector3(0, 1.05, 0))
