extends Node3D

@onready var blueprint_enabled : ShaderMaterial = preload("res://materials/blueprint_enabled.tres")
@onready var blueprint_disabled : ShaderMaterial = preload("res://materials/blueprint_disabled.tres")

func _ready():
	if name == "BlueprintsEnabled":
		get_parent().apply_blueprint_material(self, blueprint_enabled)
	elif name == "BlueprintsDisabled":
		get_parent().apply_blueprint_material(self, blueprint_disabled)
	for c in get_children(): # Hide
		c.transform.origin.y = BuildingManager.HIDE_DEPTH
