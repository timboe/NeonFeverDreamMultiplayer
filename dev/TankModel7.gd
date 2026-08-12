@tool
extends TankModelBase
class_name TankModel7

# Design 7 — "Juggernaut": an over-armoured bruiser. Two heavy shoulder domes
# cover the zoomba flanks, a sloped ram plate guards the front, and twin
# exhaust stacks with pulsing flame tips trail behind. The cannon is a
# massive barrel collared by twin emitter rings and a chrome jacket.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var fire := _mat(Color(1.0, 0.55, 0.1), 0.0, 0.4, Color(1.0, 0.55, 0.1), 3.0, true)

	_part(self, _hemisphere(0.7), shell, Vector3(-1.4, 1.95, 0))
	_part(self, _hemisphere(0.7), shell, Vector3(1.4, 1.95, 0))
	_part(self, _box(1.7, 0.55, 2.4), shell, Vector3(-1.3, 1.7, 0), Vector3(0, 0, -20))

	for sz in [-0.5, 0.5]:
		var ex := Node3D.new()
		ex.position = Vector3(1.35, 2.0, sz)
		add_child(ex)
		_part(ex, _cyl(0.22, 0.22, 0.9, SEG), chrome, Vector3.ZERO, Vector3(0, 0, -35))
		var tip := _part(ex, _sphere(0.18), fire, Vector3(0.5, 0, 0))
		_add_pulse(tip, 7.0, float(sz))

	_build_laser(2.35, 1.3, 0.3, shell)
	_part(_laser, _cyl(0.34, 0.34, 0.7, SEG), chrome, Vector3(0, 0.5, 0))
	for yy in [0.55, 0.95]:
		_part(_laser, _torus(0.34, 0.4, 24, 8), dark, Vector3(0, yy, 0))
	_part(_laser, _sphere(0.14), fire, Vector3(0, 1.36, 0))
