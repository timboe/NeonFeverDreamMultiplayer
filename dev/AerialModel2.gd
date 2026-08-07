@tool
extends AerialModelBase
class_name AerialModel2

# Design 2 — "Stiletto": a needle-nosed stealth dart. A single broad delta wing
# rides a razor fuselage with twin tail fins; nothing but sharp edges and speed.

func _build_design() -> void:
	_build_core(_box(0.48, 0.26, 2.0))

	var hull := _mat(Color(0.14, 0.15, 0.18), 0.9, 0.3)
	var dark := _mat(Color(0.04, 0.04, 0.05), 0.6, 0.5)
	var chrome := _mat(Color(0.8, 0.84, 0.9), 1.0, 0.12)
	var glass := _mat(Color(0.5, 0.75, 0.95), 0.1, 0.05, Color(0.4, 0.7, 1.0), 1.5, false, 0.65)
	var cyan := _mat(Color(0.1, 0.9, 1.0), 0.0, 0.3, Color(0.1, 0.9, 1.0), 3.5, true)
	var red := _mat(Color(1.0, 0.15, 0.15), 0.0, 0.3, Color(1.0, 0.15, 0.15), 3.0, true)

	# Delta wing
	_part(self, _box(3.1, 0.05, 1.0), dark, Vector3(0, -0.06, -0.35))
	# Swept strakes
	_part(self, _box(1.3, 0.05, 0.4), dark, Vector3(0.75, 0.0, -0.65), Vector3(0, 40, 0))
	_part(self, _box(1.3, 0.05, 0.4), dark, Vector3(-0.75, 0.0, -0.65), Vector3(0, -40, 0))
	# Nose cone
	_part(self, _cone(0.24, 0.5, 12), dark, Vector3(0, 0, 1.05), Vector3(90, 0, 0))
	# Cockpit canopy
	_part(self, _hemisphere(0.16), glass, Vector3(0, 0.16, 0.32))
	# Twin tail fins
	_part(self, _box(0.05, 0.6, 0.5), dark, Vector3(0.24, 0.3, -0.85), Vector3(0, 0, 10))
	_part(self, _box(0.05, 0.6, 0.5), dark, Vector3(-0.24, 0.3, -0.85), Vector3(0, 0, -10))
	# Horizontal stabiliser
	_part(self, _box(0.55, 0.04, 0.45), chrome, Vector3(0, 0.35, -0.95))
	# Wingtip nav lights
	var wl := Node3D.new()
	wl.position = Vector3(1.55, 0.0, -0.35)
	add_child(wl)
	_part(wl, _sphere(0.06), red, Vector3.ZERO)
	_add_pulse(wl, 7.0, 0.0)
	var wr := Node3D.new()
	wr.position = Vector3(-1.55, 0.0, -0.35)
	add_child(wr)
	_part(wr, _sphere(0.06), red, Vector3.ZERO)
	_add_pulse(wr, 7.0, 3.14)
	# Engine glows
	var e1 := Node3D.new()
	e1.position = Vector3(0.12, -0.05, -1.02)
	add_child(e1)
	_part(e1, _sphere(0.09), cyan, Vector3.ZERO)
	_add_pulse(e1, 5.0, 0.0)
	var e2 := Node3D.new()
	e2.position = Vector3(-0.12, -0.05, -1.02)
	add_child(e2)
	_part(e2, _sphere(0.09), cyan, Vector3.ZERO)
	_add_pulse(e2, 5.0, 3.14)
	# Gun: twin cannons on the nose line
	_build_gun(Vector3(0, 0.02, 0.5), 1.15, 0.05, chrome)
	_part($Gun, _cyl(0.03, 0.03, 1.0, 10), chrome, Vector3(0.1, 0, 0.55), Vector3(90, 0, 0))
