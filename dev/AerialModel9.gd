@tool
extends AerialModelBase
class_name AerialModel9

# Design 9 — "Solstice": an alien crystalline flyer. Jagged shards grow from a
# glowing core and orbit slowly; a crystal spike is the cannon and the whole
# craft hums with refracted light.

func _build_design() -> void:
	_build_core(_sphere(0.3))

	var magenta := _mat(Color(1.0, 0.25, 0.9), 0.0, 0.2, Color(1.0, 0.25, 0.9), 3.5, true)
	var cyan := _mat(Color(0.2, 0.9, 1.0), 0.0, 0.2, Color(0.2, 0.9, 1.0), 3.5, true)
	var gold := _mat(Color(1.0, 0.8, 0.2), 0.0, 0.25, Color(1.0, 0.8, 0.2), 3.0, true)

	# Fore shard (crystal spike forward)
	_part(self, _cone(0.5, 1.5, 4), magenta, Vector3(0, 0.1, 0.75), Vector3(90, 0, 0))
	# Aft shard
	_part(self, _cone(0.4, 1.2, 4), cyan, Vector3(0, 0.02, -0.75), Vector3(-90, 0, 0))
	# Orbiting side shards
	var orbit := Node3D.new()
	add_child(orbit)
	for a in [45, 135, 225, 315]:
		var s := Node3D.new()
		s.rotation.y = deg_to_rad(a)
		orbit.add_child(s)
		_part(s, _cone(0.24, 0.75, 4), gold, Vector3(0, 0.1, 0.75), Vector3(90, 0, 0))
	_add_spin(orbit, 0.7)
	# Halo ring
	var ring := Node3D.new()
	add_child(ring)
	_part(ring, _torus(0.55, 0.66, 48, 8), gold, Vector3.ZERO, Vector3(90, 0, 0))
	_add_spin(ring, -1.6)
	# Repulsor glow underneath
	var glow := Node3D.new()
	glow.position = Vector3(0, -0.5, 0)
	add_child(glow)
	_part(glow, _cyl(0.75, 0.75, 0.04, 20), cyan, Vector3.ZERO)
	_add_pulse(glow, 4.5, 0.0)
	# Crystal cannon (a spike, not a barrel)
	$Gun.position = Vector3(0, -0.22, 0.5)
	$Gun/Muzzle.position = Vector3(0, 0, 0.95)
	var barrel := _part($Gun, _cone(0.11, 0.95, 4), magenta, Vector3(0, 0, 0.47), Vector3(90, 0, 0))
	barrel.name = "Barrel"
