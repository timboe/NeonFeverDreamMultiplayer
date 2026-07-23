extends Unit

class_name Zoomba

func _ready() -> void:
	$Zapper.visible = false

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.ZOOMBA
	_health_bar.position.y = 2.5
	add_to_group("zoomba")
	var updated_mat = load("res://materials/player/player" + str(player_owner) + "_material.tres")
	$Body/CSGBody/CSGMesh.material = updated_mat
