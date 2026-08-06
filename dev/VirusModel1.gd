@tool
extends VirusModelBase
class_name VirusModel1

# Design 1 — "Hedgehog": a dense flat starburst of radial chevrons (each point
# set 90 deg to its orbital motion), like a spiny seed / sea urchin. Reads as
# a low, wide star from above.

const HEDGE_RINGS := [
	{"radius": 1.32, "y": 0.12, "count": 24, "span": 0.3, "depth": 0.5, "spin": 0.55},
	{"radius": 0.95, "y": 0.24, "count": 16, "span": 0.24, "depth": 0.4, "spin": -0.65},
	{"radius": 0.58, "y": 0.36, "count": 10, "span": 0.18, "depth": 0.32, "spin": 0.8},
]

func _build_design() -> void:
	_build_core(0.55, 1.05)
	_build_ring(1.5, 0.07)
	for ring in HEDGE_RINGS:
		var root := Node3D.new()
		root.position.y = ring["y"]
		var count: int = ring["count"]
		for i in count:
			var a := TAU * i / float(count)
			var pos := Vector3(cos(a) * ring["radius"], 0, sin(a) * ring["radius"])
			_spawn_chevron(root, ring["span"], ring["depth"], pos, Vector3(0, _radial_yaw(a), 0))
		_add_spin(root, ring["spin"])
		add_child(root)
	_build_arcs()
	_build_motes(110, 40)
