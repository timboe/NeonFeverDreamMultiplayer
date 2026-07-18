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
		get_parent().apply_blueprint_material(self, blueprint_enabled)
	elif name == "BlueprintsDisabled":
		get_parent().apply_blueprint_material(self, blueprint_disabled)
	for c in get_children():
		c.position.y = BuildingManager.HIDE_DEPTH
		_disable_collision_recursive(c)
