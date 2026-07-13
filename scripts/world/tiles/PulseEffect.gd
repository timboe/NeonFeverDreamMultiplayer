extends Node3D

const PLAYER_COLORS : Array[Color] = [
	Color.RED,
	Color.PURPLE,
	Color.YELLOW,
	Color.GREEN,
]

const CYCLE_TIME := 1.0
const BASE_TICK_TIME := 0.1
const MIN_TICK_TIME := 0.04
const BASE_EMISSION := 0.1
const MIN_EMISSION := 0.05

var tile_manager : TileManager

var _cycle_timers : Dictionary = {}
var _ring_timers : Dictionary = {}
var _ring_index : Dictionary = {}
var _active : Dictionary = {}

func _ready():
	set_physics_process(true)

func _physics_process(delta : float):
	if tile_manager == null:
		tile_manager = get_parent() as TileManager
		if tile_manager == null:
			return

	for pnum in range(1, Global.MAX_PLAYERS + 1):
		_tick(pnum, delta)

func _tick(pnum : int, delta : float):
	if not _active.get(pnum, false):
		_cycle_timers[pnum] = _cycle_timers.get(pnum, CYCLE_TIME) - delta
		if _cycle_timers[pnum] <= 0.0:
			_start(pnum)
		return

	_ring_timers[pnum] -= delta
	if _ring_timers[pnum] <= 0.0:
		_advance(pnum)

func _get_rings(pnum : int) -> Array:
	return tile_manager.player_aoe_rings.get(pnum, [])

func _start(pnum : int):
	var rings := _get_rings(pnum)
	if rings.is_empty():
		_cycle_timers[pnum] = CYCLE_TIME
		return
	_active[pnum] = true
	_ring_index[pnum] = 0
	_ring_timers[pnum] = _tick_time(0, rings.size())
	_flash_ring(pnum, 0)

func _advance(pnum : int):
	var rings := _get_rings(pnum)
	var prev : int = _ring_index.get(pnum, 0)
	_clear_ring(pnum, prev, rings)

	var next := prev + 1
	if next >= rings.size():
		_finish(pnum)
		return

	_ring_index[pnum] = next
	_ring_timers[pnum] = _tick_time(next, rings.size())
	_flash_ring(pnum, next)

func _finish(pnum : int):
	_active[pnum] = false
	_cycle_timers[pnum] = CYCLE_TIME

func _flash_ring(pnum : int, idx : int):
	var rings := _get_rings(pnum)
	if idx >= rings.size():
		return
	var color : Color = PLAYER_COLORS[pnum - 1]
	var em := _emission(idx, rings.size())
	for tile in rings[idx]:
		if _can_modify(tile):
			tile.set_tile_mm_color(color)
			tile.set_tile_mm_emission(em)

func _clear_ring(pnum : int, idx : int, rings : Array):
	if idx >= rings.size():
		return
	for tile in rings[idx]:
		if _can_modify(tile):
			tile.set_tile_mm_emission(0.0)

func _can_modify(tile : TileElement) -> bool:
	return not (tile.toggle_tween and tile.toggle_tween.is_valid() and tile.toggle_tween.is_running()) \
		and not (Global.my_player_number in tile.selected_by)

func _tick_time(idx : int, max_rings : int) -> float:
	if max_rings <= 1:
		return BASE_TICK_TIME
	return lerpf(BASE_TICK_TIME, MIN_TICK_TIME, float(idx) / float(max_rings - 1))

func _emission(idx : int, max_rings : int) -> float:
	if max_rings <= 1:
		return BASE_EMISSION
	return lerpf(BASE_EMISSION, MIN_EMISSION, float(idx) / float(max_rings - 1))
