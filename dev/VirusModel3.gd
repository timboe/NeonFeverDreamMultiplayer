@tool
extends VirusModelBase
class_name VirusModel3

# Design 3 — "Caltrop": four large chevrons standing as blades around the
# unknown core, each blade's face cutting edge-on through the orbital motion.
# Reads as a 3D spiked asterisk / crown, distinct from flat or tall shapes.

const BLADE_SPAN := 1.0
const BLADE_DEPTH := 0.9
const BLADE_COUNT := 4
const BLADE_RADIUS := 0.45
const BLADE_BASE_Y := 0.1
const BLADE_TILT := -1.05 # radians from horizontal (stand up, lean outward)

func _build_design() -> void:
	_build_core(0.7, 1.5)
	_build_ring(1.5, 0.07)
	var crown := Node3D.new()
	for i in BLADE_COUNT:
		var a := TAU * i / float(BLADE_COUNT)
		var pivot := Node3D.new()
		pivot.rotation.y = a
		_spawn_chevron(pivot, BLADE_SPAN, BLADE_DEPTH, Vector3(0, BLADE_BASE_Y, BLADE_RADIUS), Vector3(BLADE_TILT, 0, 0))
		crown.add_child(pivot)
	_add_spin(crown, 0.4)
	add_child(crown)
	_build_arcs()
	_build_motes(90, 40)
