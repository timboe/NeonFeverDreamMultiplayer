@tool
extends TankModelBase
class_name TankModel5

# Design 5 — "Obelisk": a ceremonial war-shrine. The zoomba body carries a
# stepped obelisk spire ringed by chrome pylons, with an energy hoop spinning
# around its mid-point. The apex laser fires from a crystal emitter embedded
# in the topmost tier.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	_part(self, _box(1.7, 1.2, 1.7), shell, Vector3(0, 2.3, 0))
	_part(self, _box(1.15, 1.0, 1.15), shell, Vector3(0, 3.25, 0))
	_part(self, _box(0.6, 0.9, 0.6), dark, Vector3(0, 4.2, 0))

	var hoop := Node3D.new()
	hoop.position = Vector3(0, 3.0, 0)
	add_child(hoop)
	_part(hoop, _torus(1.05, 1.15, 40, 8), glow, Vector3.ZERO, Vector3(90, 0, 0))
	_add_spin(hoop, 1.6)

	for i in 4:
		var a := TAU * i / 4.0
		_part(self, _box(0.22, 1.05, 0.22), chrome, Vector3(cos(a) * 1.4, 2.1, sin(a) * 1.4))

	_build_laser(4.65, 0.7, 0.16, dark)
	_part(_laser, _torus(0.24, 0.3, 20, 6), chrome, Vector3(0, 0.2, 0))
	var crystal := _part(_laser, _sphere(0.2), glow, Vector3(0, 0.42, 0))
	_add_pulse(crystal, 4.0)
