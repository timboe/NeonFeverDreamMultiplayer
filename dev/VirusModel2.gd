@tool
extends VirusModelBase
class_name VirusModel2

# Design 2 — "Needle": a tall cone of chevron rings shrinking up to a glowing
# point, like a virus totem / pine. Each chevron wraps around the direction of
# rotation so the rings read as flowing >>. Reads as a tall, narrow spire.
# No arcs; a faint electric haze instead.

const TOWER_SPIN := 0.9

const RINGS := [
	{"y": 0.2, "radius": 1.0, "count": 12, "span": 0.36, "depth": 0.4},
	{"y": 0.6, "radius": 0.82, "count": 10, "span": 0.3, "depth": 0.34},
	{"y": 1.0, "radius": 0.65, "count": 8, "span": 0.24, "depth": 0.28},
	{"y": 1.4, "radius": 0.5, "count": 6, "span": 0.19, "depth": 0.22},
	{"y": 1.8, "radius": 0.37, "count": 5, "span": 0.15, "depth": 0.18},
	{"y": 2.2, "radius": 0.26, "count": 4, "span": 0.11, "depth": 0.14},
]

func _build_design() -> void:
	_arc_node.visible = false
	var tower := Node3D.new()
	for ring in RINGS:
		var count: int = ring["count"]
		for i in count:
			var a := TAU * i / float(count)
			var pos := Vector3(cos(a) * ring["radius"], ring["y"], sin(a) * ring["radius"])
			_spawn_chevron(tower, ring["span"], ring["depth"], pos, Vector3(0, _tangent_yaw(a, TOWER_SPIN), 0))
	_add_spin(tower, TOWER_SPIN)
	add_child(tower)
	_build_core(0.3, 2.55)
	_build_ring(1.15, 0.07)
	_build_motes(7, 3)
