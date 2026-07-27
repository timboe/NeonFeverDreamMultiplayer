extends Unit

class_name Tank

func initialise(b: Building) -> void:
	super.initialise(b)
	type = UnitManager.Type.TANK
	_health_bar.position.y = 3.0
	health = Config.UNIT_MAX_HP.get(type, 100.0)
	add_to_group("tank")
	add_to_group("tank_player" + str(player_owner))
	var updated_mat = load("res://materials/player/player" + str(player_owner) + "_material.tres")
	$Body/CSG.set_surface_override_material(0, updated_mat)
