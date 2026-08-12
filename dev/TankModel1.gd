@tool
extends TankModelBase
class_name TankModel1

# Design 1 — "Warhound": the direct evolution of the current tank chassis.
# The zoomba body rides on the classic chrome undercarriage (four legs, a
# platform and a ring) under a single heavy cannon whose glowing emitter coil
# spins around the barrel.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_part(self, _box(0.2, 1.5, 0.2), chrome, Vector3(sx * 1.4, 1.25, sz * 1.4))
	_part(self, _box(3, 0.2, 3), chrome, Vector3(0, 1.9, 0))
	_part(self, _cyl(1.3, 1.3, 0.2, 32), chrome, Vector3(0, 2.1, 0))

	_build_laser(2.3, 1.2, 0.22, shell)
	_part(_laser, _cyl(0.26, 0.26, 0.5, SEG), chrome, Vector3(0, 0.35, 0))
	var coil := Node3D.new()
	coil.position = Vector3(0, 0.6, 0)
	_laser.add_child(coil)
	_part(coil, _torus(0.3, 0.36, 32, 8), glow, Vector3.ZERO)
	_add_spin(coil, 2.4)
	_part(_laser, _sphere(0.12), glow, Vector3(0, 1.28, 0))
