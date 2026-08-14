extends Node3D

class_name Blueprints

# --- Materials ---

@onready var blueprint_enabled: ShaderMaterial = preload("res://materials/blueprint_enabled.tres")
@onready var blueprint_disabled: ShaderMaterial = preload("res://materials/blueprint_disabled.tres")
# Fully invisible override for vertex-edge line surfaces (cyan plinth outlines,
# meshes/plinth.tres surface 1): the blueprint shaders don't render PRIMITIVE_LINES
# correctly, so blueprint setup hides them instead.
static var _hidden_line_mat: StandardMaterial3D = preload("res://materials/blueprint_line_hidden.tres")

static func disable_collision_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionShape3D:
			c.disabled = true
		disable_collision_recursive(c)

static func _hide_controls(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			c.visible = false
		_hide_controls(c)

static func enable_collision_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionShape3D:
			c.disabled = false
		enable_collision_recursive(c)

# Toggle every collision shape under a building's Terminal subtree. A building
# in BLUEPRINT/UNDER_CONSTRUCTION state is invisible yet its Terminal's
# ScreenBody collider would otherwise sit as an invisible wall on an access
# tile; it only gains collision once constructed (rpc_constructed).
static func set_terminal_collision(building: Node, enabled: bool) -> void:
	var terminal := building.get_node_or_null("Terminal")
	if not terminal:
		return
	if enabled:
		enable_collision_recursive(terminal)
	else:
		disable_collision_recursive(terminal)

func _ready() -> void:
	if name == "BlueprintsEnabled":
		apply_blueprint_material(self, blueprint_enabled)
	elif name == "BlueprintsDisabled":
		apply_blueprint_material(self, blueprint_disabled)
	for c in get_children():
		c.position.y = BuildingManager.HIDE_DEPTH
		disable_collision_recursive(c)
	_hide_controls(self)

# Build a placement ghost from a freshly instantiated building scene — mirrors
# everything _ready() applies to the live BlueprintsEnabled/Disabled templates
# (blueprint materials, hidden Terminal/particles/collision, hidden Controls),
# so per-placement ghosts never need Node.duplicate() of a live template.
static func prepare_ghost(ghost: Node, mat: ShaderMaterial) -> void:
	apply_blueprint_material(ghost, mat)
	disable_collision_recursive(ghost)
	_hide_controls(ghost)

static func apply_blueprint_material(node: Node, mat: ShaderMaterial) -> void:
	# The Terminal isn't part of the ghost — hide it. (queue_free breaks
	# Node.duplicate() of the building templates, so we hide instead; the
	# visible=false override survives duplication into placed ghosts.)
	if node.name == "Terminal":
		node.visible = false
		return
	for c in node.get_children():
		apply_blueprint_material(c, mat)
	apply_mesh_material(node, mat)
	if node is GPUParticles3D or node is Zapper or node is CollisionShape3D:
		node.visible = false

# Mesh-only material swap (no Terminal/particle hiding) — used by the
# remove-mode hover, which paints a live building red instead of overlaying a
# ghost. Skipping the Terminal leaves the HUD screen material untouched.
static func apply_mesh_material(node: Node, mat: ShaderMaterial) -> void:
	if node.name == "Terminal":
		return
	for c in node.get_children():
		apply_mesh_material(c, mat)
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			# Only ArrayMesh carries primitive types; primitives (CylinderMesh
			# etc.) are always triangles and have no surface_get_primitive_type.
			if node.mesh is ArrayMesh and node.mesh.surface_get_primitive_type(i) == Mesh.PRIMITIVE_LINES:
				node.set_surface_override_material(i, _hidden_line_mat)
				continue
			node.set_surface_override_material(i, mat)
	elif node is CSGCombiner3D:
		node.material_override = mat

# Record every mesh material override under a live building, so the remove-mode
# red paint can be reverted exactly (Vat sets a runtime player-material override
# on its Liquid; a blanket null-restore would wipe it).
static func capture_mesh_materials(node: Node, into: Array) -> void:
	if node.name == "Terminal":
		return
	for c in node.get_children():
		capture_mesh_materials(c, into)
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			into.append([node, i, node.get_surface_override_material(i)])
	elif node is CSGCombiner3D:
		into.append([node, -1, node.material_override])

static func restore_mesh_materials(captured: Array) -> void:
	for entry in captured:
		var mesh: Node = entry[0]
		var surface: int = entry[1]
		var mat = entry[2]
		if not is_instance_valid(mesh):
			continue
		if surface >= 0:
			mesh.set_surface_override_material(surface, mat)
		else:
			mesh.material_override = mat
