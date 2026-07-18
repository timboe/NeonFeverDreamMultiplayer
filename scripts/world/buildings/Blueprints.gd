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

static func enable_collision_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is CollisionShape3D:
			c.disabled = false
		enable_collision_recursive(c)

func _ready() -> void:
	if name == "BlueprintsEnabled":
		apply_blueprint_material(self, blueprint_enabled)
	elif name == "BlueprintsDisabled":
		apply_blueprint_material(self, blueprint_disabled)
	for c in get_children():
		c.position.y = BuildingManager.HIDE_DEPTH
		_disable_collision_recursive(c)

func apply_blueprint_material(node: Node, mat: ShaderMaterial) -> void:
	for c in node.get_children():
		apply_blueprint_material(c, mat)
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			node.set_surface_override_material(i, mat)
	elif node is CSGCombiner3D:
		node.material_override = mat
	# TODO node.name == "Terminal" is not working here
	elif node is GPUParticles3D or node is Zapper or node is CollisionShape3D or node.name == "Terminal":
		node.visible = false
