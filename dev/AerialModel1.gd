@tool
extends AerialModelBase
class_name AerialModel1

# Design 1 — "Oracle": a floating armoured eyeball. A polished gyroscope ring
# wheels around a player-coloured sphere whose entire front is one enormous
# glowing iris. It reads from any angle as a watchful sentry.

func _build_design() -> void:
	_build_core(_sphere(0.55))

	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var iris := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)
	var pupil := _mat(Color(0.01, 0.01, 0.03), 0.0, 0.1)
	var thruster := _mat(Color(1.0, 0.55, 0.1), 0.0, 0.4, Color(1.0, 0.55, 0.1), 3.0, true)

	# Gyroscope ring
	var gyro := Node3D.new()
	add_child(gyro)
	_part(gyro, _torus(0.62, 0.85, 48, 10), chrome, Vector3.ZERO, Vector3(90, 0, 0))
	_add_spin(gyro, 1.4)

	# Eye: socket ring, iris, pupil, glow halo
	_part(self, _torus(0.28, 0.32), dark, Vector3(0, 0.05, 0.5))
	_part(self, _sphere(0.24), iris, Vector3(0, 0.05, 0.6))
	_part(self, _sphere(0.09), pupil, Vector3(0, 0.05, 0.84))
	_part(self, _torus(0.12, 0.14), iris, Vector3(0, 0.05, 0.85))

	# Armour plates on the rear hemisphere
	_part(self, _box(0.5, 0.14, 0.4), shell, Vector3(0, 0.32, -0.3), Vector3(0, 0, -25))
	_part(self, _box(0.5, 0.14, 0.4), shell, Vector3(0, -0.32, -0.3), Vector3(0, 0, 25))

	# Rear thruster
	var t1 := Node3D.new()
	t1.position = Vector3(0, 0, -0.55)
	add_child(t1)
	_part(t1, _cyl(0.07, 0.07, 0.4, 10), shell, Vector3.ZERO, Vector3(90, 0, 0))
	_part(t1, _sphere(0.07), thruster, Vector3(0, 0, -0.25))
	_add_pulse(t1, 6.0, 0.0)

	# Side thrusters
	for sx in [-1, 1]:
		var t := Node3D.new()
		t.position = Vector3(sx * 0.4, -0.15, -0.42)
		add_child(t)
		_part(t, _cyl(0.045, 0.045, 0.3, 8), shell, Vector3.ZERO, Vector3(90, 0, 0))
		_part(t, _sphere(0.045), thruster, Vector3(0, 0, -0.18))
		_add_pulse(t, 6.0, 1.0 + float(sx))

	# Top antenna
	_part(self, _cyl(0.02, 0.02, 0.5, 6), chrome, Vector3(0, 0.6, 0.1))
	_part(self, _sphere(0.05), iris, Vector3(0, 0.86, 0.1))

	# Forward weapon under the eye
	_build_gun(Vector3(0, -0.4, 0.45), 0.8, 0.06, shell)
	_part($Gun, _box(0.24, 0.14, 0.3), dark, Vector3(0, -0.02, 0.12))
