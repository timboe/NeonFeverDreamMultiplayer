@tool
extends TankModelBase
class_name TankModel6

# Design 6 — "Pocket Fortress": a miniature stronghold. A chrome deck plate
# and a ring of merlon blocks cap the zoomba body, and four corner turrets
# peek over the rim. A twin-barrel turret rises from a dark pedestal in the
# centre of the deck.

func _build_design() -> void:
	_build_zoomba_core()

	var chrome := _mat(Color(0.78, 0.82, 0.88), 1.0, 0.15)
	var shell := _mat(Color(0.09, 0.1, 0.12), 0.9, 0.35)
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6, 0.5)
	var glow := _mat(Color(0.1, 0.95, 1.0), 0.0, 0.2, Color(0.1, 0.95, 1.0), 4.0, true)

	_part(self, _cyl(1.55, 1.55, 0.2, 24), chrome, Vector3(0, 2.0, 0))
	for i in 10:
		var a := TAU * i / 10.0
		_part(self, _box(0.5, 0.5, 0.5), shell, Vector3(cos(a) * 1.7, 2.15, sin(a) * 1.7))
	for i in 4:
		var a := TAU * i / 4.0 + PI / 4.0
		_part(self, _box(0.3, 0.4, 0.3), dark, Vector3(cos(a) * 1.85, 2.5, sin(a) * 1.85))

	_part(self, _cyl(0.5, 0.62, 0.4, 16), dark, Vector3(0, 2.5, 0))
	_build_laser(2.75, 0.9, 0.14, dark)
	_part(_laser, _cyl(0.14, 0.14, 0.9, SEG), shell, Vector3(-0.26, 0.45, 0))
	_part(_laser, _torus(0.16, 0.2, 16, 6), glow, Vector3(0, 0.88, 0))
