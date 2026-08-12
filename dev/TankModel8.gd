@tool
extends TankModelBase
class_name TankModel8

# Design 8 — "Gyro": the zoomba body hangs inside a chrome gyroscope cage —
# one upright cradle hoop and a spinning equatorial hoop joined by gimbal
# arms. The top cannon is slim, ringed by radiating heatsink fins and capped
# with a glowing bolt.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	_part(self, _torus(2.13, 2.25, 56, 10), chrome, Vector3(0, 1.2, 0), Vector3(90, 0, 0))
	var hoop := Node3D.new()
	hoop.position = Vector3(0, 1.3, 0)
	add_child(hoop)
	_part(hoop, _torus(2.0, 2.1, 56, 10), chrome, Vector3.ZERO)
	_add_spin(hoop, 0.8)
	for i in 4:
		var a := TAU * i / 4.0
		_part(self, _box(0.1, 0.14, 2.0), chrome, Vector3(cos(a) * 2.06, 1.25, sin(a) * 2.06), Vector3(0, rad_to_deg(a), 0))

	_build_laser(2.35, 1.1, 0.18, dark)
	for i in 6:
		var a := TAU * i / 6.0
		var fin := Node3D.new()
		fin.position = Vector3(0, 0.75, 0)
		fin.rotation.y = a
		_laser.add_child(fin)
		_part(fin, _box(0.35, 0.4, 0.06), dark, Vector3(0.32, 0, 0))
	_part(_laser, _torus(0.18, 0.22, 16, 6), chrome, Vector3(0, 1.05, 0))
	_part(_laser, _sphere(0.1), glow, Vector3(0, 1.15, 0))
