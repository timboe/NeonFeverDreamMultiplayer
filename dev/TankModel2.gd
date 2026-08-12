@tool
extends TankModelBase
class_name TankModel2

# Design 2 — "Skimmer": the zoomba hull sits on a hover rig — two long chrome
# skids, rear thruster pods and a prow fin. A low turret pedestal carries a
# stubby cannon with a pulsing emitter dome under a radar dome.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var thruster := _mat(Color(1.0, 0.55, 0.1), 0.0, 0.4, Color(1.0, 0.55, 0.1), 3.0, true)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	for sx in [-1, 1]:
		_part(self, _box(0.4, 0.22, 4.4), chrome, Vector3(sx * 1.85, 0.55, 0), Vector3(0, 0, sx * -8))
	_part(self, _box(0.1, 0.7, 1.1), shell, Vector3(-1.92, 1.25, 0), Vector3(0, 0, -35))

	for sz in [-0.65, 0.65]:
		var pod := Node3D.new()
		pod.position = Vector3(1.5, 1.1, sz)
		add_child(pod)
		_part(pod, _cyl(0.24, 0.24, 0.8, SEG), chrome, Vector3.ZERO, Vector3(0, 0, 30))
		var tip := _part(pod, _sphere(0.18), thruster, Vector3(0.4, 0, 0))
		_add_pulse(tip, 6.0, float(sz))

	_part(self, _hemisphere(0.35), shell, Vector3(1.35, 1.85, 0))
	_part(self, _torus(0.22, 0.26, 16, 6), glow, Vector3(1.35, 2.18, 0))

	_build_laser(2.0, 0.9, 0.2, dark)
	_part(_laser, _cyl(0.5, 0.56, 0.4, 16), chrome, Vector3(0, 0.2, 0))
	var dome := _part(_laser, _sphere(0.17), glow, Vector3(0, 0.35, 0))
	_add_pulse(dome, 5.0)
	_part(_laser, _torus(0.2, 0.24, 16, 6), glow, Vector3(0, 0.9, 0))
