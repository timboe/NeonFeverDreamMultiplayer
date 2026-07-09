extends Node3D

@onready var blueprint_enabled : ShaderMaterial = preload("res://materials/blueprint_enabled.tres")
@onready var blueprint_disabled : ShaderMaterial = preload("res://materials/blueprint_disabled.tres")

func _ready():
	if name == "BlueprintsEnabled":
		recursive_set_blueprint(self, blueprint_enabled)
		get_child(0).queue_free()
	elif name == "BlueprintsDisabled":
		recursive_set_blueprint(self, blueprint_disabled)
		get_child(0).queue_free()

func recursive_set_blueprint(node, mat : ShaderMaterial):
	for c in range(node.get_child_count()):
		recursive_set_blueprint(node.get_child(c), mat)
	if node is MeshInstance3D and node.mesh:
		for i in range(node.mesh.get_surface_count()):
			node.set_surface_override_material(i, mat)
	elif node is CSGCombiner3D:
		node.material_override = mat
	elif node is GPUParticles3D or node is Zapper:
		node.queue_free()
