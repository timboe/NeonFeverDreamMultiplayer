extends Node3D

class_name Blueprints

# --- Materials ---

@onready var blueprint_enabled: ShaderMaterial = preload("res://materials/blueprint_enabled.tres")
@onready var blueprint_disabled: ShaderMaterial = preload("res://materials/blueprint_disabled.tres")

static func _disable_collision_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionShape3D:
			c.disabled = true
		_disable_collision_recursive(c)

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
		_disable_collision_recursive(terminal)

func _ready() -> void:
	if name == "BlueprintsEnabled":
		apply_blueprint_material(self, blueprint_enabled)
	elif name == "BlueprintsDisabled":
		apply_blueprint_material(self, blueprint_disabled)
	for c in get_children():
		c.position.y = BuildingManager.HIDE_DEPTH
		_disable_collision_recursive(c)
	_hide_controls(self)

func apply_blueprint_material(node: Node, mat: ShaderMaterial) -> void:
	# The Terminal isn't part of the ghost — hide it. (queue_free breaks
	# Node.duplicate() of the building templates, so we hide instead; the
	# visible=false override survives duplication into placed ghosts.)
	if node.name == "Terminal":
		node.visible = false
		return
	for c in node.get_children():
		apply_blueprint_material(c, mat)
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			node.set_surface_override_material(i, mat)
	elif node is CSGCombiner3D:
		node.material_override = mat
	elif node is GPUParticles3D or node is Zapper or node is CollisionShape3D:
		node.visible = false
