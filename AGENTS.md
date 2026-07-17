# NeonFeverDreamMP — AGENTS.md

## Stack

- **Godot 4.7**, Jolt Physics, D3D12 renderer, Forward Plus
- Entrypoint: `scenes/menu/MainMenu.tscn`
- Single autoload: `autoload/Global.gd` (holds `network_manager`, `game_config`)
- Additional autoload: `autoload/Config.gd` (static dicts for `BUILDING_AOE`, `UNIT_SPEED`, `HOME_TERRITORY_UNITS`)
- No tests, no lint, no typecheck config

## Multiplayer architecture

- ENet server-authoritative. `Server` node lives only on host (`scripts/core/network/Server.gd`).
- `NetworkManager` is **not** in any scene — instantiated at runtime by `MainMenu` and added to root.
- Host path: `Global.network_manager.server` (NOT a node path lookup — `get_node` fails due to dynamic parent).
- Remote path: `Global.network_manager` exists but `.server` is null.

### Unified command relay: `Global.send_command_me()` / `send_command()`

Every game action follows the same two-line pattern — no manual branching:

```gdscript
# Any caller, host or remote, human or AI:
Global.send_command_me("toggle_tile", [tile_id])
Global.send_command(ai_pnum, "toggle_cell", [x, z])
```

**Route**:
```
send_command_me / send_command
  ├─ Server exists? → Server.handle_command(pnum, command, args)
  │                     └─ reflection → _cmd_toggle_cell / _cmd_toggle_tile / ...
  └─ No server (remote client)? → rpc_id(1, "_on_remote_command", ...)
								   └─ Server._on_remote_command()
									  └─ peer_to_player[caller] → handle_command(pnum, ...)
```

**Key points**:
- `send_command_me` uses `Global.my_player_number` — safe for host (set by `NetworkManager` at LOCAL-slot creation) and remote (set by `NetworkManager.set_my_player_number` RPC)
- `send_command(pnum, ...)` is for AI controllers that know their own player number
- The remote client's `pnum` is never trusted — the server always derives it from `peer_to_player`
- Command handlers on `Server` are named `_cmd_<command>` and auto-dispatched via `callv` + `has_method`. The `_cmd_` prefix acts as an allowlist — arbitrary method names like `queue_free` won't match.
- No `human_controllers` group checks, no `rpc_id(1, ...)` scattered in game objects, no `HumanController` bridge methods. HumanController, GameGrid, and GridCell have been removed — replaced entirely by the tile system.

### Server-only guard pattern

Functions that must only run on the server use an early return guard at the top:

```gdscript
func new_unit_callback(new_unit):
	if not multiplayer.is_server():
		return
	...
```

This is used in `UnitManager.spawn_unit` and `UnitManager.new_unit_callback` to prevent duplicate unit creation on clients. The `_physics_process` in `TileManager` runs on all peers — any server-only logic called from there must be self-guarded.

## Key classes

| Class | File | Role |
|---|---|---|
| `Global` | `autoload/Global.gd` | Singleton, holds `network_manager` ref, `send_command_me/send_command` relay |
| `Config` | `autoload/Config.gd` | Singleton, static dicts: `BUILDING_AOE` (radius per building type), `UNIT_SPEED`, `HOME_TERRITORY_UNITS` |
| `NetworkManager` | `scripts/core/network/NetworkManager.gd` | Creates Server/LocalClients or ENet client |
| `Server` | `scripts/core/network/Server.gd` | ENet server, peer→player mapping, command dispatch |
| `TileManager` | `scripts/world/tiles/TileManager.gd` | Cairo pentagon tile grid generation + multiplayer selection sync, AoE recomputation, `remove_tile_from_pathing` |
| `TileElement` | `scripts/world/tiles/TileElement.gd` | Single tile (StaticBody3D + MultiMesh instance) with hover/selection visual, `aoe` array, `working_unit` for job callback |
| `PathingManager` | `scripts/world/tiles/PathingManager.gd` | AStar3D pathfinding, `connect_tiles`/`disconnect_tiles`/`disconnect_tile`, debug renderer (ImmediateMesh) |
| `AIController` | `scripts/core/ai/AIController.gd` | Random timer-driven tile toggle |
| `GameConfig` | `scripts/core/game/GameConfig.gd` | Slot config: LOCAL, REMOTE, AI, CLOSED |
| `GameManager` | `scripts/core/game/GameManager.gd` | Snapshot/interpolation manager: server→client unit sync + client→server avatar relay, per-player avatar interpolation |
| `CameraController` | `scripts/world/camera/CameraRTS.gd` | Middle-click drag, scroll zoom, WASD pan, pitch/yaw limits |
| `CameraManager` | `scripts/world/camera/CameraManager.gd` | Stub (~99% commented dead code, not converted) |
| `BuildingManager` | `scripts/world/buildings/BuildingManager.gd` | Building type enum, placement validation, blueprint visibility, dictionary of all buildings, `new_building_instance()` returns correct scene per type |
| `Building` | `scripts/world/buildings/Building.gd` | Base building: states (BLUEPRINT→CONSTRUCTED→UNDER_DESTRUCTION), `player_owner`, `get_aoe_radius()`, `check_work()` stub, tween-driven construction |
| `MCP` | `scripts/world/buildings/MCP.gd` | Main Control Point: rotating top animation, energy generation |
| `Vat` | `scripts/world/buildings/Vat.gd` | Energy storage: liquid-level tween, capacity calculation, `contains` set/get with underscore-backed var |
| `Zapper` | `scripts/world/buildings/Zapper.gd` | Laser beam effect (ImmediateMesh + RayCast3D), jaggies animation |
| `Blueprints` | `scripts/world/buildings/Blueprints.gd` | Ghost building preview, duplicate material assignment |
| `UnitManager` | `scripts/world/units/UnitManager.gd` | Unit type enum, `spawn_unit`/`rpc_spawn_unit`, `rpc_remove_unit`, `displace_units_on_tile`, server guard on spawn |
| `Unit` | `scripts/world/units/Unit.gd` | Base unit: states (IDLE/PATHING/WORKING), pathing, rotation (Quaternion slerp), `abandon_job`, `job_finished`, `move_tween` |
| `Zoomba` | `scripts/world/units/Zoomba.gd` | Bot unit: `initialise`, player-colour material, most logic commented out (scram, pathing jobs) |
| `JobManager` | `scripts/world/units/JobManager.gd` | Job queue per player, worker-centric assignment (`assign_nearest_job`), abandoned-job delay, debug renderer |

## Job system

### Unit states

Every unit has exactly one of three states. State transitions are the core of the job system.

| State | Meaning |
|---|---|
| `IDLE` | No job. Unit wanders randomly between accessible tiles. |
| `PATHING` | Has a job. Unit is pathfinding toward the target tile. |
| `WORKING` | At target tile. Unit is performing the job action (e.g. toggle countdown). |

### State transitions

```
					┌──────────────────────────────────────────────────┐
					│                                                  │
  ┌─────────┐   assign_job()   ┌─────────┐   start_work()   ┌─────────┐
  │  IDLE   │ ───────────────→ │ PATHING │ ───────────────→ │ WORKING │
  └─────────┘                  └─────────┘                  └─────────┘
	   ↑                            │    │                        │  │
	   │                            │    │                        │  │
	   │  remove_job()              │    │  remove_job()          │  │  remove_job()
	   │  abandon_job()             │    │  abandon_job()         │  │  abandon_job()
	   │  job_finished()            │    │  job_finished()        │  │  job_finished()
	   │                            │    │                        │  │
	   └────────────────────────────┘    └────────────────────────┘  │
																	 │
	   ┌─────────────────────────────────────────────────────────────┘
	   │
	   └──→ IDLE (unit resumes wandering)
```

All transitions are server-only (`if not multiplayer.is_server(): return` guard at top of every function).

### Unit.gd functions

**`idle_callback()`** — The idle loop entry point. Called after spawn, after `remove_job()`, and after each wander move.
- If `job` is non-empty (unit was assigned while idle): asserts `PATHING`, clears path, calls `pathing_callback()`.
- If `job` is empty (true idle): picks a random accessible tile (preferring AoE tiles for HOME_TERRITORY_UNITS), avoids backtracking, calls `move(idle_callback)`.

**`pathing_callback()`** — Runs each step of pathfinding toward the job target.
1. Asserts `PATHING` state.
2. `check_job_still_valid()` — if job was removed externally, calls `job_finished()` (early-out).
3. Checks if unit reached `path_dest` — if so, calls `start_work()`.
4. `check_pathing_valid()` — if no path exists or it's empty, calls `abandon_job()`.
5. Re-checks `path_dest` (may have changed to current location after re-pathing).
6. Moves to next node in path via `move(pathing_callback)`.

**`check_pathing_valid()`** — If `path` is empty, re-runs pathfinding from current location to all access tiles of the job target. Sets `path_dest` to the closest access tile. Returns `false` if no reachable path exists (triggers `abandon_job`). Returns `true` if a valid path exists (path was already computed and hasn't been invalidated).

**`start_work()`** — Transitions PATHING → WORKING.
- Sets `state = WORKING`, rotates unit toward target, enables zapper visual.
- For `TOGGLE_TILE`: calls `job["location"].do_toggle_countdown(self)` — the tile now owns the callback chain.

**`job_finished()`** — Called when work completes or the job is no longer valid.
- Early-out if `job` is empty (idempotent).
- Sets `state = IDLE`.
- Calls `JobManager.remove_job(job["id"])` which calls `Unit.remove_job()` → handles tile cleanup and idle resumption.

**`remove_job()`** — Called by `JobManager.remove_job()` when a job is deleted from the pool.
- If `state == WORKING`: calls `_cleanup_working_state()` (cancels tile countdown / construction).
- Sets `state = IDLE`, hides zapper, kills `move_tween`, clears `job`.
- Calls `idle_callback()` unconditionally (tween is killed, no stale callback risk).

**`_cleanup_working_state()`** — Shared helper used by both `remove_job` and `abandon_job` when `state == WORKING`. Cancels tile countdown via `cancel_toggle_countdown(self)` or cancels building construction.

**`abandon_job()`** — Inlined logic for both pathing and working states:
- If `state == WORKING`: calls `_cleanup_working_state()` (hides zapper, cancels tile countdown / construction).
- Sets `state = IDLE`, clears `job`, kills `move_tween` (prevents stale `pathing_callback` from firing after state change).
- Calls `JobManager.abandon_job(id)` (job stays in pool, reassignable after timer).
- Calls `idle_callback()` unconditionally.

**`move(callback)`** — Creates a tween that slerps rotation and moves to `location.pathing_centre`. Calls `callback` when done. IDLE units move at 2x speed.

### JobManager.gd

**`add_job(pnum, type, location)`** — Deduplicates: if a job with the same `type` and `location` already exists, no-op. Otherwise creates a job dict and adds to `jobs_dict`.

**`cancel_job(pnum, type, location)`** — Finds the matching job by pnum/type/location and calls `remove_job(id)`. Used when a human deselects a tile (`TileManager.apply_toggle` → `toggle_selected_by` returns false → `cancel_job`).

**`remove_job(id)`** — If the job has an `assigned` unit, calls `unit.remove_job()` (which handles tile cleanup and idle resumption). Then erases the job from `jobs_dict`. The job is permanently deleted — it cannot be reassigned.

**`abandon_job(id)`** — Job stays in the pool. Clears `assigned`, increments `abandoned_n`, sets `abandoned_timer = min(60, abandoned_n × 11)`. The job becomes eligible for reassignment after the timer expires.

**`assign_jobs()`** — Called every 1s by `GameManager._process`. Two passes:
1. Decrements `abandoned_timer` by 1.0 for all unassigned jobs.
2. Iterates all units in the `"unit"` group. For each unit with empty `job`, calls `assign_nearest_job(unit)`.

**`assign_nearest_job(unit)`** — For each unassigned job matching the unit's player, with expired abandon timer, computes path length. Picks the shortest. Sets `job["assigned"] = unit` and calls `unit.assign_job(job)`.

### TileElement.gd (tile-side job support)

**`do_toggle_countdown(z)`** — Server-only. Stores `working_unit = z` and `toggle_zoomba_player`. Starts a 2s countdown tween (`_countdown_tween`) that calls `begin_toggle`. Sends RPC mode 0 (visual countdown to all peers).

**`cancel_toggle_countdown(z)`** — Server-only. Clears `toggle_zoomba_player` and `working_unit`. Kills `_countdown_tween` (prevents `begin_toggle` from firing). Sends RPC mode 1 (kills visual countdown on all peers).

**`begin_toggle()`** — Server-only. Fired by `_countdown_tween` after 2s delay.
- If tile state is no longer RAISED/LOWERED (state changed during countdown): calls `working_unit.job_finished()` and cleans up. The toggle is aborted.
- Otherwise: transitions tile state (RAISED → FALLING, or LOWERED → RISING via `set_rising()`), erases player from `selected_by`, sends RPC broadcast. Creates a second tween (`fall_time + thunk_time`) that calls `done_toggle`.

**`done_toggle()`** — Server-only. Fired after the fall/rise animation completes.
- RAISED→FALLING: calls `set_lowered()`. LOWERED→RISING: sets state = RAISED.
- Calls `working_unit.job_finished()` if unit is still valid, then clears `working_unit`.

### Tween separation on TileElement

Two independent tweens exist on each tile during a toggle:

| Tween | Scope | Purpose |
|---|---|---|
| `_countdown_tween` | Server-only | Drives the 2s countdown → `begin_toggle`. Never synced to clients. |
| `toggle_tween` | All peers (via RPC) | Visual countdown animation (color lerp). Created by `rpc_toggle_animation` mode 0. Read by `update_selection_and_aoe_visual` to avoid overwriting emission during work. |

### Job finish vs abandon vs cancel

| Outcome | Who triggers | Job lifecycle | Unit lifecycle | Tile lifecycle |
|---|---|---|---|---|
| **Finish** | Tile animation completes → `done_toggle` → `job_finished()` | Removed from pool (`remove_job`) | → IDLE via `remove_job` → `idle_callback` | `done_toggle` completes state change, clears `working_unit` |
| **Cancel** | Human deselects tile → `cancel_job` → `remove_job` | Removed from pool | → IDLE via `remove_job` → `idle_callback` | `remove_job` calls `cancel_toggle_countdown` if WORKING |
| **Abandon (pathing)** | Path invalid → `abandon_job()` | Stays in pool (`JobManager.abandon_job`), reassignable after timer | → IDLE → `idle_callback` | N/A (unit never reached tile) |
| **Abandon (working)** | Unit gives up → `abandon_job()` | Stays in pool (`JobManager.abandon_job`), reassignable after timer | → IDLE → `idle_callback` | Countdown cancelled, `working_unit` cleared |
| **Displacement** | Tile removed from pathing → `_displace_unit` | Stays in pool (`abandon_job`) | Teleported to adjacent tile or destroyed | N/A |

### Tile disconnection / unit displacement

When a tile leaves the pathing grid (`set_rising` or building placement), `TileManager.remove_tile_from_pathing(tile)` is called:

1. `PathingManager.disconnect_tile(tile)` — removes all AStar edges from this tile
2. `UnitManager.displace_units_on_tile(tile)` — for each unit on the tile:
   - If unit has a job → `unit.abandon_job()` (job goes back to pool)
   - Kill active `move_tween`
   - Find first `LOWERED` neighbour with no building → teleport unit there
   - If no valid neighbour exists → `rpc("rpc_remove_unit", unit.id)` (destroy)

### Path re-routing

`check_pathing_valid()` re-computes the path whenever the unit reaches a node and the current path is empty (or was invalidated). It tries all access tiles of the job target and picks the shortest path. This handles:
- Other tiles being lowered/raised mid-path
- Pathing edges being disconnected by tile displacement
- The access tile changing if a building was placed/removed next to the target

### Job dict fields

| Field | Type | Meaning |
|---|---|---|
| `id` | int | Unique job ID (monotonically increasing) |
| `pnum` | int | Player who owns this job |
| `type` | JobManager.Type | `TOGGLE_TILE`, `CONSTRUCT_BUILDING`, etc. |
| `location` | TileElement | The tile this job targets |
| `assigned` | Unit or null | Unit currently working on this job (null if unassigned) |
| `abandoned_by` | Unit or null | Last unit that abandoned this job |
| `abandoned_n` | int | How many times this job has been abandoned |
| `abandoned_timer` | float | Seconds until eligible for reassignment (0 = eligible) |

## Per-instance visual data (MultiMesh)

Each tile instance packs three independent visuals into `set_instance_color` and `set_instance_custom_data`:

| Channel | Written by | Read by | Purpose |
|---|---|---|---|
| `INSTANCE_CUSTOM.rgba` | `set_tile_mm_selecting_mask` | `aluminium.tres` vertex→`selecting_mask` | Band stripes — which players claim this tile and which have AoE |
| `COLOR.rgb` | `set_tile_mm_color` | `grid_edges.tres` fragment → `ALBEDO` | Edge color — local hover indicator |
| `COLOR.a` | `set_tile_mm_emission` | `aluminium.tres` fragment → `EMISSION` + `EMISSION_ENERGY` | White glow — local-selection highlight (RGB=color, A=intensity) |

All three are independent: `set_tile_mm_color` preserves `a`, `set_tile_mm_emission` preserves `rgb`, and `set_tile_mm_selecting_mask` writes custom data.

### AoE (Area of Effect)

- `TileElement.aoe` array lists which players have AoE on this tile
- `TileManager.recompute_aoe()` runs BFS per building from `Config.BUILDING_AOE` radii
- Called once after `apply_loaded_level()` — deterministic on all peers, no AoE-specific network traffic
- `Building.get_aoe_radius()` reads from `Config.BUILDING_AOE[type]`

## Godot 4 conversion patterns

### Tween (RefCounted, not Node)

- Use `create_tween()` instead of `$Tween`/`get_node("Tween")`
- Chaining API: `tween_property()`, `tween_method()`, `tween_callback().set_delay(n)`
- Auto-starts — no `.start()` needed
- Kill with `tween.kill()` + guard with `tween and tween.is_valid()`
- Store in a local var, not `@onready` (tweens are RefCounted, not Nodes)
- For tween-created-as-child pattern (e.g. TileElement): `active_tween.kill(); active_tween = create_tween()`

### `setget` → `set`/`get` blocks

```gdscript
# Godot 3
var value: int = 0 setget set_value, get_value
# Godot 4
var value: int = 0:
	set(v):
		value = v
	get:
		return value
```

Use underscore-backed var to avoid recursion: `var _contains_val` backed by `contains` set/get.

### `var` keyword on function parameters

Removed in Godot 4. `func foo(var x: int)` → `func foo(x: int)`.

### `@rpc` annotations

```gdscript
@rpc("authority", "call_local")  # server calls → runs on all peers
@rpc("any_peer", "call_remote")  # any peer calls → runs on server only
```

### `call_deferred` for next-frame execution

```gdscript
call_deferred("my_function")
my_function.call_deferred(arg1, arg2)
```

### `ImmediateGeometry` → `ImmediateMesh` + `MeshInstance3D`

```gdscript
# Godot 3: ImmediateGeometry (node)
dr.clear()
dr.begin(Mesh.PRIMITIVE_LINES)
dr.set_color(Color.red)
dr.add_vertex(...)
dr.end()

# Godot 4: ImmediateMesh (resource) on MeshInstance3D
dr_mesh.clear_surfaces()
dr_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
dr_mesh.surface_set_color(Color.RED)
dr_mesh.surface_add_vertex(...)
dr_mesh.surface_end()
```

## Converted scripts

### Tile scripts

- `TileElement.gd`: `tween.remove`→`active_tween.kill`, `interpolate_method`→`tween_method`, `interpolate_property`→`tween_property`, `interpolate_callback`→`tween_callback`, signals use `.connect()`, `BUTTON_LEFT`→`MOUSE_BUTTON_LEFT`, `GlobalVars`→`Global`. `transform.origin.y = val`→copy-modify-set pattern. Added `aoe` array, `add_to_aoe(player_n)`, `pathing_manager` stored reference. Added `working_unit` for job callback, `done_toggle` calls `working_unit.job_finished()`, `begin_toggle` guards against invalid tile state. Added `rpc_toggle_animation` for network-synced toggle visuals. Added `_countdown_tween` (server-only) to store the countdown tween so it can be killed by `cancel_toggle_countdown`. `toggle_tween` is the visual tween synced to all peers via RPC.
- `TileManager.gd`: `BaseMaterial3D`→`StandardMaterial3D`, `set_surface_material`→`set_surface_override_material`, `set_multimesh()`→`.multimesh =`, `translation`→`position`, `use_in_baked_light` removed. `translate()`→`position` (lines 60, 86, 96-101). Added `tiles()`, `recompute_aoe()`, `set_neighbours` assigns `pathing_manager` ref. Added `remove_tile_from_pathing(tile)`. `recompute_aoe()` runs once after `apply_loaded_level()` (not per-tile).
- `TileManager.tscn`: both `[node name="Tween"]` children removed.
- `PathingManager.gd`: `PackedInt32Array`→`PackedInt64Array`, added debug ImmediateMesh renderer with `toggle_debug()`. Added `disconnect_tile(tile)` for removing all edges from a tile.
- `Cairo.gd`: `GENERATE = false` with "do not regenerate" note.
- `MonorailMultimesh.gd`: not yet reviewed (entire body commented out).

### Building scripts

- `Building.gd`: `player_owner`, `get_aoe_radius()`, `check_work()` stub. Removed `@onready var tween` — uses `create_tween()` + `_build_tween` var with `.kill()`/`.is_valid()`. `setget`→`set`/`get` blocks for `spawn_start_loc` and `my_blueprint`. `initialise(pnum, tile)` — subclasses call `super.initialise(pnum, tile)` then set `self.type` and add their own groups. Fixed `UNDER_DESTRUCTIOfN` typo.
- `Vat.gd`: `contains`→`_contains_val` set/get. `tween.remove(liquid)`→`_liquid_tween.kill()` + `create_tween().tween_property(...)`. `location.player`→`self.player_owner`.
- `BuildingManager.gd`: `StaticBody`→`StaticBody3D`, `DESTROYED`→`LOWERED`, `tile.set_destroyed()`→`tile.set_lowered()`, added `buildings()` returning `building_dictionary.values()`. `initalise`→`initialise`. `tile.under_aoe`→`Global.my_player_number in tile.aoe`. `new_building_instance()` returns correct scene per type (MCP_3/4 use MCP.gd, GARAGE/BEACON/NEST use Building.gd).
- `Zapper.gd`: `ImmediateGeometry`→`MeshInstance3D` + `ImmediateMesh`, `cast_to`→`target_position`, removed `tween.remove`/`tween.start`. Removed duplicate `Vector3.ZERO` first vertex.
- `Zapper.tscn`: `type="ImmediateGeometry"`→`type="MeshInstance3D"`.
- `Blueprints.gd`: `get_name()`→`name`, `set_surface_material`→`set_surface_override_material`, `get_surface_material_count()`→`node.mesh.get_surface_count()` with null guard.
- `Blueprints.tscn`: removed orphan Tween node.
- `MCP.gd`: `push_back`→`append` (4 calls in `_ready`).
- `BuildingConstructedParticles.tscn`: full `format=2`→Godot 4 rewrite.
- Materials (`blueprint_enabled.tres`, `blueprint_disabled.tres`): removed `diffuse_burley,specular_schlick_ggx` from `render_mode`; `hint_color`→`source_color`; removed `SPECULAR = specular;`; added `SCREEN_TEXTURE : hint_screen_texture`.

### Unit scripts

- `Unit.gd`: `@rpc("authority", "call_local")` on `assign_job`, `idle_callback`, `move`, `quat_transform`, `setup_rotation`. `PackedInt32Array`→`PackedInt64Array`, `Quat`→`Quaternion`, `transform.origin` used correctly, `create_tween()` for movement/rotation. `abandon_job()` inlines both pathing and working cleanup, kills `move_tween` to prevent stale callbacks. `_cleanup_working_state()` shared helper for tile countdown / construction cancellation. `remove_job` uses same helper, kills tween unconditionally. `pathing_callback` returns `abandon_job()` on invalid path, `job_finished()` on invalid job. `initialise(b)` — subclasses call `super.initialise(b)` then set `self.type` and add their own groups.
- `Zoomba.gd`: Removed `@onready var tween`, added `pathing_manager`. `PoolIntArray`→`PackedInt64Array`. `interpolate_method`→`create_tween().tween_method`, `interpolate_property`→`tween_property`, `interpolate_callback`→`tween_callback().set_delay()`. `Quat`→`Quaternion`, `translation`→`position`, `GlobalVars`→`Global`, `push_back`→`append`, `remove`→`remove_at`, `cast_to`→`target_position`. Most pathing/work logic is commented out.
- `UnitManager.gd`: Added `units()`, `_next_unit_id`, `rpc_remove_unit` (replaces `remove_unit`) with `@rpc("authority", "call_local")`, `displace_units_on_tile` + `_displace_unit` for tile disconnection handling. Server guard on `spawn_unit`.
- `JobManager.gd`: `GlobalVars`→`Global`, `push_back`→`append`, removed `var` on parameters, ImmediateGeometry→ImmediateMesh for debug renderer. Flipped assignment to worker-centric: `try_and_assign(job)` → `assign_nearest_job(unit)`. `assign_jobs()` now has two-pass structure (timer decrement then worker iteration).

### Camera / Floor scripts

- `OmniLight.gd`: `translation`→`position`, `GlobalVars`→`Global`, `get_world()`→`get_world_3d()`, `intersect_ray(old_args)`→`PhysicsRayQueryParameters3D.create()`, `result.empty()`→`result.is_empty()`.
- `CameraRTS.gd`: already Godot 4.
- `GridMultiMesh.gd`: `push_back`→`append` (lines 56, 57, 96).
- `Monument.gd` + `MonumentHelper.gd`: converted. `translate()`→`position` (lines 76, 79).

### Core / Network scripts

- `GameManager.gd`: `_apply_unit()` — client only; server never reaches it (early return in `_process` + `apply_snapshot` is `call_remote`). Client no longer mutates `server_state` or `health` — those fields only written by server. Client→avatar relay: clients send `receive_avatar_snapshot` (20 Hz, `camera_status == FPS` only) via `rpc_id(1, ...)`. Server stores per-pnum snapshots and interpolates with `_interpolate_avatars()`. Clients skip their own avatar in `_apply_interpolated`/`_apply_snapshot_units` to avoid control cycles.
- `AIController.gd`: Filters to `interactive` group tiles instead of random from all tiles.
- `Lobby.gd`: Guards `disconnect()` calls with `is_connected()` checks.
- `Global.gd`: Fixed comment typo "of time" → "of tile".

### Placeholder buildings

Placeholder `.tscn` files created for MCP_3, MCP_4, Garage, Beacon, Nest under `scenes/world/buildings/`. MCP_3/4 use `MCP.gd`; Garage/Beacon/Nest use `Building.gd`. All have `StaticBody3D` root, `BuildingConstructedParticles`, `Plinth` with `Plinth.gd`, `CollisionShape3D`. Added to `Blueprints.tscn` so `new_building_instance()` can reference them as `$BuildingFactory/<Name>.duplicate()`.

### Floor materials

- Floor materials: `grid_faces.tres` and `grid_edges.tres` — `albedo` texture with `source_color`, `grid_edges.tres` has `use_instance_color` uniform for per-instance edge colour.

### Remaining Godot 3 patterns (active bugs)

| Pattern | File | Line(s) | Fix |
|---|---|---|---|
| Massive commented Godot 3 code | `CameraManager.gd` | most of file | Dead code, not converted |

## Running

- Pass `--client` as CLI arg to launch second instance on the Connect tab (skips Host tab).
- Default config for instances: `"Run Instances"` in Godot editor with `--client` on the second.

## Gotchas

- `Server.next_player_num` is set by `NetworkManager.start_server()` before creating local clients — do not hard-code it.
- `rpc_id(1, ...)` targets the server (peer 1 is always the server in ENet).
- `TileManager.apply_toggle` validates `tile.state == RAISED` before toggling — tiles in FALLING/LOWERED/DISABLED are skipped.
- `Global.my_player_number` is set at slot-creation time for the host human, or by `NetworkManager.set_my_player_number` RPC for remotes. If `my_player_number == -1`, the multi-selector fallback uses `selecting.min()`.
- `%` unique node lookup requires the caller's node `owner` to be set. Dynamically created TileElements miss this → use a stored `pathing_manager` reference set by TileManager instead of `%PathingManager`.
- `TileElement` no longer has `.player` — use `.selected_by` array or `.aoe` array for player ownership checks.
- Server-only functions called from `_physics_process` (which runs on all peers) must self-guard with `if not multiplayer.is_server(): return`.
- `create_tween()` returns a `RefCounted` Tween — store in a local var, use `.kill()` + `.is_valid()` guard, and do not use `@onready`.
- `ImmediateMesh.clear_surfaces()` replaces `ImmediateGeometry.clear()`.

## Lobby flow

- When any REMOTE slot exists, "Start Lobby" loads `scenes/menu/Lobby.tscn` instead of going straight to World.
- Lobby shows slot config, waits for all REMOTE peers to connect, then auto-starts World when `Server.peer_to_player.size()` equals the REMOTE slot count.
- Host broadcasts `rpc("remote_start_game")` to all clients before transitioning; clients receive it via `Lobby.remote_start_game()` and load World.
- Remote clients also load `Lobby.tscn` (not World.tscn) on connect, and wait for the host's RPC.
- AI controllers check for `/root/World/TileManager` existence and skip actions during lobby (the node doesn't exist yet).
- Back button calls `Global.network_manager.stop()` + `queue_free()` and returns to MainMenu.
- `NetworkManager.stop()` also closes the client ENet peer (`multiplayer.multiplayer_peer.close()`) in client mode — not just the server peer.

## Floor (decorative only, no multiplayer sync)

- `scenes/world/floor/Floor.tscn` — 50×50 tile visual floor with animated mountains
- `scripts/world/floor/GridMultiMesh.gd` — `MultiMeshInstance3D` driving vertex-displacement mountains via per-instance custom data (Color stores 4 height values per column)
- `scripts/world/floor/Grid.gd` — procedural grid mesh generator (generation disabled, uses `res://meshes/grid.tres`)
- `scripts/world/floor/Monument.gd` + `MonumentHelper.gd` — procedural monuments with pulsing beacon
- Materials: `res://materials/floor/grid_faces.tres` (lit, `source_color`) and `grid_edges.tres` (unshaded cyan edges)
- 5s timer triggers mountain morph via `create_tween()` → `tween_method()` → `update_mountain(idx, color)`
- No collision, no Area3D, no RPC involvement

## UI rules

- Only one slot can be "Host (Local)" — selecting LOCAL on a second slot snaps the first LOCAL back to Remote.
- Zero LOCAL slots is allowed (Spectator mode): the host can watch but has no AIController, so host clicks route through `send_command_me` but get dropped by Server (no `peer_to_player` entry for the host).
