extends Node3D

class_name DestructionFX

# --- Constants ---

# Building feel (defaults — spawn_unit() overrides with the unit-scale values).
# How long chunks tumble before cleanup sinks them below the ground.
const CHUNK_LIFETIME: float = 6.0
# Duration of the below-ground sink that ends each chunk's life.
const SINK_TIME: float = 1.0
# How far below its resting spot a chunk sinks before being freed (relative, so
# chunks resting on raised tiles drop below them too).
const SINK_DEPTH: float = 18.0
# Debris speed = base + radius-factor × horizontal distance from the FX centre,
# capped — pieces near the centre (or high above it) blast mostly upward and
# fall back onto the wreck, so nothing is flung across the map.
const BLAST_SPEED_BASE: float = 3.0
const BLAST_SPEED_RADIUS_FACTOR: float = 0.5
const BLAST_SPEED_MAX: float = 8.0
# Random upward kick added to the radial blast.
const BLAST_LIFT_MAX: float = 3.0
# Minimum chunk mass (tiny meshes would otherwise be massless).
const MASS_FLOOR: float = 1.0

# Unit feel (used by spawn_unit()).
const UNIT_CHUNK_LIFETIME: float = 3.5
const UNIT_SINK_TIME: float = 0.8
const UNIT_SINK_DEPTH: float = 6.0
const UNIT_BLAST_SPEED_BASE: float = 1.5
const UNIT_BLAST_SPEED_RADIUS_FACTOR: float = 0.3
const UNIT_BLAST_SPEED_MAX: float = 4.0
const UNIT_BLAST_LIFT_MAX: float = 1.5
const UNIT_MASS_FLOOR: float = 0.1

# Debris lives on its own physics layer and only collides with tiles, so it
# never disturbs units/buildings while it tumbles.
const CHUNK_COLLISION_LAYER: int = 4
const TILE_COLLISION_LAYER: int = 1
# Mesh-instance names that must never become debris (terminal HUD subtree,
# Vat liquid — the liquid is a shader-driven fill, not a solid chunk; the
# avatar's selection ray).
const EXCLUDED_NAMES := ["Terminal", "Screen", "Liquid", "RayRender"]

# Ember burst scene (scene-authored like every working particle system in the
# project — code-built GPUParticles3D never rendered here). Buildings only.
const BURST_SCENE = preload("res://scenes/world/fx/DestructionFXBurst.tscn")

# --- State ---

var _chunks: Array[RigidBody3D] = []
# Unit-scale overrides (set by spawn_unit); defaults give the building feel.
var _chunk_lifetime: float = CHUNK_LIFETIME
var _sink_time: float = SINK_TIME
var _sink_depth: float = SINK_DEPTH
var _blast_speed_base: float = BLAST_SPEED_BASE
var _blast_speed_radius_factor: float = BLAST_SPEED_RADIUS_FACTOR
var _blast_speed_max: float = BLAST_SPEED_MAX
var _blast_lift_max: float = BLAST_LIFT_MAX
var _mass_floor: float = MASS_FLOOR
var _spawn_particles: bool = true

# Spawns a one-shot destruction effect for a CONSTRUCTED building, chunking its
# own mesh children into physics debris. Cosmetic only — callers run it locally
# on every peer simultaneously (driven from the call_local rpc_remove_building /
# rpc_remove_unit), so no networking is involved.
static func spawn(building: Building) -> void:
	# Drop the dying building out of physics first: the debris copies its exact
	# mesh transforms, so without this every chunk starts deeply overlapping the
	# building's own colliders and Jolt's depenetration violently ejects them
	# (they appear many tiles away from the wreck).
	building.collision_layer = 0
	building.collision_mask = 0
	var fx := DestructionFX.new()
	fx.name = "DestructionFX_" + str(building.id)
	building.get_parent().add_child(fx)
	fx.global_transform = building.global_transform
	fx._setup(building)

# Unit variant: the same debris machinery at unit scale, no particle burst.
# The Avatar root never moves, so its FX centres on the FPSBody instead.
static func spawn_unit(unit: Unit) -> void:
	var fx := DestructionFX.new()
	fx.name = "DestructionFX_" + str(unit.id)
	unit.get_parent().add_child(fx)
	fx._chunk_lifetime = UNIT_CHUNK_LIFETIME
	fx._sink_time = UNIT_SINK_TIME
	fx._sink_depth = UNIT_SINK_DEPTH
	fx._blast_speed_base = UNIT_BLAST_SPEED_BASE
	fx._blast_speed_radius_factor = UNIT_BLAST_SPEED_RADIUS_FACTOR
	fx._blast_speed_max = UNIT_BLAST_SPEED_MAX
	fx._blast_lift_max = UNIT_BLAST_LIFT_MAX
	fx._mass_floor = UNIT_MASS_FLOOR
	fx._spawn_particles = false
	fx._setup_unit(unit)

func _setup(building: Building) -> void:
	_make_chunks_from(building)
	if _spawn_particles:
		_add_particles(building)
	Global.VM.add_trauma(0.35, global_position, 0.2)
	_arm_cleanup()

func _setup_unit(unit: Unit) -> void:
	var body := unit.get_node_or_null("FPSBody")
	global_position = body.global_position if body else unit.global_position
	_make_chunks_from(unit)
	_arm_cleanup()

func _make_chunks_from(root: Node3D) -> void:
	# Recursive: buildings keep their meshes as direct children but units nest
	# theirs under a "Body" node (Zoomba: Ball/Ball2/CSG, Tank: +Barrel under
	# Laser, Avatar: under FPSBody) — direct-children-only produced no chunks
	# for units.
	for child in root.find_children("*", "MeshInstance3D"):
		if child.name not in EXCLUDED_NAMES:
			_make_chunk(child)
	# TODO: MultiMeshInstance3D parts (AERIAL blades, VIRUS rings) and MCP_2's
	# CSGCombiner top sections bake no chunks — needs MultiMesh/CSG folded into
	# an ArrayMesh to add them.

func _make_chunk(mi: MeshInstance3D) -> void:
	var size := mi.mesh.get_aabb().size
	var body := RigidBody3D.new()
	body.name = "Chunk_" + str(mi.name)
	body.collision_layer = CHUNK_COLLISION_LAYER
	body.collision_mask = TILE_COLLISION_LAYER
	body.continuous_cd = true
	body.mass = maxf(_mass_floor, size.x * size.y * size.z)
	# add_child BEFORE setting the transform: a node outside the tree has no
	# parent context, so global_transform would be stored as-is and then the
	# FX's parent transform applied on top again — double-translating every
	# chunk by the parent's position + rotation, flinging it tiles away.
	add_child(body)
	body.global_transform = mi.global_transform
	var vis := MeshInstance3D.new()
	vis.name = "Mesh"
	vis.mesh = mi.mesh
	_copy_materials(mi, vis)
	body.add_child(vis)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	# Blast along the true 3D radial direction from the FX centre: a piece level
	# with the centre flies outward, a piece high above it pops upward and falls
	# back near the wreck. Speed scales with the piece's horizontal offset, so
	# debris scatters within about a tile instead of skittering across the map.
	var offset := mi.global_position - global_position
	var radial := Vector3(offset.x, 0.0, offset.z)
	var dir := offset
	if dir.length_squared() < 0.01:
		dir = Vector3.UP
	dir = dir.normalized()
	var speed := minf(_blast_speed_base + radial.length() * _blast_speed_radius_factor, _blast_speed_max)
	body.linear_velocity = dir * speed + Vector3.UP * randf_range(1.0, _blast_lift_max)
	body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	_chunks.append(body)

# Carry the dying mesh's runtime branding onto its debris chunk — player hull
# materials (Config.player_unit_material), zoomba eye shaders, chrome barrel,
# virus mats, infection rings. Only overrides are copied: the shared mesh's own
# base surface materials (scene-baked MCP player colours, chrome/glass) are
# already what the chunk displays. No-op when the source has no overrides.
static func _copy_materials(src: MeshInstance3D, dst: MeshInstance3D) -> void:
	if src.material_override:
		dst.material_override = src.material_override
	if src.material_overlay:
		dst.material_overlay = src.material_overlay
	if src.mesh:
		for i in src.mesh.get_surface_count():
			var m := src.get_surface_override_material(i)
			if m:
				dst.set_surface_override_material(i, m)

func _arm_cleanup() -> void:
	var t := create_tween().bind_node(self)
	t.tween_interval(_chunk_lifetime)
	t.tween_callback(_sink_chunks)

func _add_particles(building: Building) -> void:
	var p := BURST_SCENE.instantiate() as GPUParticles3D
	p.name = "Burst"
	# add_child BEFORE positioning (see _make_chunk): setting global_transform on
	# a parentless node stores it as local, then add_child re-applies the FX's
	# parent transform on top — translating the burst tiles away.
	add_child(p)
	# Erupt from the middle of the wreck: the tile's pathing centre at half the
	# Cairo tile height (a burst at ground level is half-inside the tile and
	# depth-culled).
	var centre: Vector3 = building.location.pathing_centre
	p.global_position = Vector3(centre.x, Cairo.HEIGHT * 0.5, centre.z)
	# emitting after add_child + restart: a one-shot created at runtime can
	# complete its emission cycle before it ever renders otherwise.
	p.emitting = true
	p.restart()

# Freeze the physics and sink every chunk below wherever it came to rest before
# freeing them, so debris appears to disappear into the floor rather than
# popping out (relative drop, so pieces on raised tiles sink below those too).
func _sink_chunks() -> void:
	var t := create_tween().bind_node(self)
	for i in _chunks.size():
		var body: RigidBody3D = _chunks[i]
		body.freeze = true
		if i > 0:
			t.parallel()
		t.tween_property(body, "global_position:y", body.global_position.y - _sink_depth, _sink_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)
