extends Unit

class_name Tank

# --- Combat visuals ---

var _beam_node: MeshInstance3D

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.TANK
	_health_bar.position.y = 3.0
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("tank")
	add_to_group("tank_player" + str(player_owner))
	var updated_mat = load("res://materials/player/player" + str(player_owner) + "_material.tres")
	$Body/CSG.set_surface_override_material(0, updated_mat)
	weapon_node = $Body/Laser
	muzzle_node = $Body/Laser/Muzzle
	weapon_forward_local = Vector3.UP
	_beam_node = MeshInstance3D.new()
	_beam_node.mesh = _make_beam_mesh()
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Config.PLAYER_COLORS[ player_owner - 1 ]
	mat.emission_energy_multiplier = 5.0
	mat.albedo_color = Config.PLAYER_COLORS[ player_owner - 1 ]
	mat.albedo_color.a = 0.85
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_node.material_override = mat
	_beam_node.visible = false
	var ph = get_node_or_null("/root/World/ProjectilesHolder")
	ph.add_child(_beam_node)
	tree_exiting.connect(_beam_node.queue_free)

func _make_beam_mesh() -> ArrayMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	var surf := cyl.get_mesh_arrays()
	var verts: PackedVector3Array = surf[Mesh.ARRAY_VERTEX]
	for i in range(verts.size()):
		verts[i] += Vector3(0, 0.5, 0)
	surf[Mesh.ARRAY_VERTEX] = verts
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surf)
	return arr_mesh

func _on_fire_event() -> void:
	if _beam_node == null:
		return
	_laser_timer = Config.WEAPON_BURST_DURATION
	_show_beam()

func _show_beam() -> void:
	if _beam_node == null or not muzzle_node or not combat_target or not is_instance_valid(combat_target):
		return
	_beam_node.visible = true

func _hide_beam() -> void:
	if _beam_node:
		_beam_node.visible = false

func _update_combat_visuals(delta: float) -> void:
	super._update_combat_visuals(delta)
	if _beam_node == null:
		return
	if _beam_node.visible and combat_target and is_instance_valid(combat_target):
		var from = _get_muzzle_global()
		var to = combat_manager.combat_target_position(combat_target)
		var dir = to - from
		var dist = dir.length()
		if dist < 0.1:
			_hide_beam()
			return
		var y = dir / dist
		var x = Vector3.UP.cross(y)
		if x.length_squared() < 0.0001:
			x = Vector3.RIGHT
		x = x.normalized()
		var z = x.cross(y).normalized()
		var new_basis = Basis(x, y, z)
		new_basis.x *= 0.35
		new_basis.y *= dist
		new_basis.z *= 0.35
		_beam_node.global_transform = Transform3D(new_basis, from)
	elif _beam_node:
		_beam_node.visible = false
