extends Unit

class_name Zoomba

func _ready() -> void:
	$Zapper.visible = false

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.ZOOMBA
	_health_bar.position.y = 2.5
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("zoomba")
	var updated_mat = load("res://materials/player/player" + str(player_owner) + "_material.tres")
	$Body/CSGBody/CSGMesh.material = updated_mat
