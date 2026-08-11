extends Node3D

class_name DestructionFX

# --- Constants ---

# How long chunks tumble before cleanup sinks them below the ground.
const CHUNK_LIFETIME: float = 6.0
# Duration of the below-ground sink that ends each chunk's life.
const SINK_TIME: float = 1.0
# How far below its resting spot a chunk sinks before being freed (relative, so
# chunks resting on raised tiles drop below them too).
const SINK_DEPTH: float = 18.0
# Debris speed = base + radius-factor × horizontal distance from the building
# centre, capped — pieces near the centre (or high above it) blast mostly
# upward and fall back onto the wreck, so nothing is flung across the map.
const BLAST_SPEED_BASE: float = 3.0
const BLAST_SPEED_RADIUS_FACTOR: float = 0.5
const BLAST_SPEED_MAX: float = 8.0
# Random upward kick added to the radial blast.
const BLAST_LIFT_MAX: float = 3.0
# Debris lives on its own physics layer and only collides with tiles, so it
# never disturbs units/buildings while it tumbles.
const CHUNK_COLLISION_LAYER: int = 4
const TILE_COLLISION_LAYER: int = 1
# Mesh-instance names that must never become debris (terminal HUD subtree,
# Vat liquid — the liquid is a shader-driven fill, not a solid chunk).
const EXCLUDED_NAMES := ["Terminal", "Screen", "Liquid"]

# Ember burst scene (scene-authored like every working particle system in the
# project — code-built GPUParticles3D never rendered here).
const BURST_SCENE = preload("res://scenes/world/buildings/DestructionFXBurst.tscn")

# --- State ---

var _chunks: Array[RigidBody3D] = []

# Spawns a one-shot destruction effect for a CONSTRUCTED building, chunking its
# own mesh children into physics debris. Cosmetic only — callers run it locally
# on every peer simultaneously (driven from the call_local rpc_remove_building),
# so no networking is involved.
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
	fx.setup(building)

func setup(building: Building) -> void:
	for child in building.get_children():
		if child is MeshInstance3D and child.name not in EXCLUDED_NAMES:
			_make_chunk(child)
	_add_particles(building)
	Global.VM.add_trauma(0.35, global_position, 0.2)
	var t := create_tween().bind_node(self)
	t.tween_interval(CHUNK_LIFETIME)
	t.tween_callback(_sink_chunks)

func _make_chunk(mi: MeshInstance3D) -> void:
	var size := mi.mesh.get_aabb().size
	var body := RigidBody3D.new()
	body.name = "Chunk_" + str(mi.name)
	body.collision_layer = CHUNK_COLLISION_LAYER
	body.collision_mask = TILE_COLLISION_LAYER
	body.continuous_cd = true
	body.mass = maxf(1.0, size.x * size.y * size.z)
	# add_child BEFORE setting the transform: a node outside the tree has no
	# parent context, so global_transform would be stored as-is and then the
	# FX's (building) transform applied on top again — double-translating every
	# chunk by the tile position + pentagon rotation, flinging it tiles away.
	add_child(body)
	body.global_transform = mi.global_transform
	var vis := MeshInstance3D.new()
	vis.name = "Mesh"
	vis.mesh = mi.mesh
	body.add_child(vis)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	# Blast along the true 3D radial direction from the building centre: a piece
	# level with the centre flies outward, a piece high above it pops upward and
	# falls back near the wreck. Speed scales with the piece's horizontal offset,
	# so debris scatters within about a tile instead of skittering across the map.
	var offset := mi.global_position - global_position
	var radial := Vector3(offset.x, 0.0, offset.z)
	var dir := offset
	if dir.length_squared() < 0.01:
		dir = Vector3.UP
	dir = dir.normalized()
	var speed := minf(BLAST_SPEED_BASE + radial.length() * BLAST_SPEED_RADIUS_FACTOR, BLAST_SPEED_MAX)
	body.linear_velocity = dir * speed + Vector3.UP * randf_range(1.0, BLAST_LIFT_MAX)
	body.angular_velocity = Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0))
	_chunks.append(body)
	# TODO (MCP_2): its top sections are CSGShapes inside a CSGCombiner, which
	# isn't a MeshInstance3D, so they bake no chunks. Needs CSGShape3D.get_meshes()
	# (returns ArrayMesh + transform) split into debris to fix.

func _add_particles(building: Building) -> void:
	var p := BURST_SCENE.instantiate() as GPUParticles3D
	p.name = "Burst"
	# add_child BEFORE positioning (see _make_chunk): setting global_transform on
	# a parentless node stores it as local, then add_child re-applies the FX's
	# building transform on top — translating the burst tiles away.
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
		t.tween_property(body, "global_position:y", body.global_position.y - SINK_DEPTH, SINK_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)
