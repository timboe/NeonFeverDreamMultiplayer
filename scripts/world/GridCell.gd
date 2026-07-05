extends Node3D
class_name GridCell

@onready var label: Label3D = $Label3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var cell_x: int
var cell_z: int

func set_owners(owners: Array):
	if owners.is_empty():
		label.text = ""
	else:
		var parts = []
		for n in owners:
			parts.append(str(n))
		label.text = ", ".join(parts)

func get_cell_pos() -> Vector2i:
	return Vector2i(cell_x, cell_z)
