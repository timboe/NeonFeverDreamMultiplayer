@tool
extends AerialModelBase
class_name AerialModel8

# Design 8 — "Ripper": a blunt tilt-rotor gunship. A chunky armoured fuselage,
# wing-tip rotors that whirr like buzzsaws, a heavy chin cannon and stubby
# rocket pods. All business.

func _build_design() -> void:
	_build_core(_box(0.8, 0.5, 1.9))

	var hull := _mat(Color(0.14, 0.15, 0.18), 0.9, 0.32)
	var dark := _mat(Color(0.04, 0.04, 0.05), 0.6, 0.5)
	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.14)
	var glass := _mat(Color(0.5, 0.78, 0.95), 0.1, 0.05, Color(0.4, 0.7, 1.0), 1.5, false, 0.6)
	var orange := _mat(Color(1.0, 0.5, 0.05), 0.0, 0.3, Color(1.0, 0.5, 0.05), 3.0, true)

	# Nose armour + cockpit
	_part(self, _box(0.6, 0.18, 0.5), chrome, Vector3(0, 0.08, 1.1))
	_part(self, _hemisphere(0.24), glass, Vector3(0, 0.32, 0.6))
	# Wing
	_part(self, _box(2.6, 0.08, 0.6), dark, Vector3(0, 0.1, 0.2))
	# Rotor nacelles
	for side in [-1, 1]:
		var nac := Node3D.new()
		nac.position = Vector3(1.3 * side, 0.4, 0.2)
		add_child(nac)
		_part(nac, _cyl(0.14, 0.14, 0.5, 10), chrome, Vector3.ZERO, Vector3(90, 0, 0))
		var rotor := Node3D.new()
		nac.add_child(rotor)
		_part(rotor, _box(0.85, 0.02, 0.12), dark, Vector3.ZERO)
		_part(rotor, _box(0.12, 0.02, 0.85), dark, Vector3.ZERO)
		_part(rotor, _box(0.2, 0.02, 0.08), orange, Vector3(0.45, 0, 0))
		_add_spin(rotor, 20.0)
	# Tail
	_part(self, _box(0.05, 0.55, 0.5), dark, Vector3(0.34, 0.4, -0.8), Vector3(0, 0, 8))
	_part(self, _box(0.05, 0.55, 0.5), dark, Vector3(-0.34, 0.4, -0.8), Vector3(0, 0, -8))
	_part(self, _box(0.7, 0.05, 0.45), chrome, Vector3(0, 0.42, -0.95))
	# Rocket pods
	_part(self, _box(0.3, 0.16, 0.5), dark, Vector3(0.75, -0.18, 0.15))
	_part(self, _box(0.3, 0.16, 0.5), dark, Vector3(-0.75, -0.18, 0.15))
	# Skids
	_part(self, _box(0.06, 0.05, 1.2), dark, Vector3(0.32, -0.45, 0.15))
	_part(self, _box(0.06, 0.05, 1.2), dark, Vector3(-0.32, -0.45, 0.15))
	# Rear engine glows
	var e1 := Node3D.new()
	e1.position = Vector3(0.25, 0.05, -1.0)
	add_child(e1)
	_part(e1, _sphere(0.08), orange, Vector3.ZERO)
	_add_pulse(e1, 5.0, 0.0)
	var e2 := Node3D.new()
	e2.position = Vector3(-0.25, 0.05, -1.0)
	add_child(e2)
	_part(e2, _sphere(0.08), orange, Vector3.ZERO)
	_add_pulse(e2, 5.0, 3.14)
	# Chin cannon
	_build_gun(Vector3(0, -0.12, 0.75), 1.0, 0.11, dark)
	_part($Gun, _box(0.22, 0.16, 0.35), dark, Vector3(0, -0.06, 0.18))
