@tool
extends AerialModelBase
class_name AerialModel6

# Design 6 — "Gimbal": a vertical command pod held inside two counter-rotating
# gyroscope rings. The hull never tilts; the rings do all the turning around it.

func _build_design() -> void:
	_build_core(_capsule(0.3, 0.5))

	var hull := _mat(Color(0.13, 0.14, 0.17), 0.9, 0.3)
	var chrome := _mat(Color(0.8, 0.84, 0.9), 1.0, 0.12)
	var dark := _mat(Color(0.04, 0.04, 0.05), 0.6, 0.5)
	var glass := _mat(Color(0.55, 0.8, 1.0), 0.1, 0.05, Color(0.45, 0.75, 1.0), 1.5, false, 0.6)
	var cyan := _mat(Color(0.15, 0.9, 1.0), 0.0, 0.3, Color(0.15, 0.9, 1.0), 3.0, true)

	# Horizontal gimbal ring
	var r1 := Node3D.new()
	add_child(r1)
	_part(r1, _torus(0.7, 0.9, 64, 10), chrome, Vector3.ZERO, Vector3(90, 0, 0))
	_add_spin(r1, 1.3)

	# Vertical gimbal ring
	var r2 := Node3D.new()
	add_child(r2)
	_part(r2, _torus(0.7, 0.9, 64, 10), dark, Vector3.ZERO, Vector3(0, 90, 0))
	_add_spin(r2, -1.0)

	# Command pod (the CSG capsule is the hull)
	_part(self, _hemisphere(0.22), glass, Vector3(0, 0.66, 0))
	_part(self, _torus(0.24, 0.28), chrome, Vector3(0, 0.42, 0))
	# Engine glows at the pod base
	var e1 := Node3D.new()
	e1.position = Vector3(0.1, -0.3, 0)
	add_child(e1)
	_part(e1, _sphere(0.07), cyan, Vector3.ZERO)
	_add_pulse(e1, 6.0, 0.0)
	var e2 := Node3D.new()
	e2.position = Vector3(-0.1, -0.3, 0)
	add_child(e2)
	_part(e2, _sphere(0.07), cyan, Vector3.ZERO)
	_add_pulse(e2, 6.0, 3.14)

	# Twin cannons
	_build_gun(Vector3(0, -0.02, 0.5), 0.9, 0.06, chrome)
	_part($Gun, _cyl(0.035, 0.035, 0.9, 10), chrome, Vector3(0.18, 0, 0.45), Vector3(90, 0, 0))
