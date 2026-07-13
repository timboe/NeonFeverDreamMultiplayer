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
| `GameManager` | `scripts/core/game/GameManager.gd` | Snapshot/interpolation manager for network state |
| `CameraController` | `scripts/world/camera/CameraRTS.gd` | Middle-click drag, scroll zoom, WASD pan, pitch/yaw limits |
| `CameraManager` | `scripts/world/camera/CameraManager.gd` | Stub (~99% commented dead code, not converted) |
| `BuildingManager` | `scripts/world/buildings/BuildingManager.gd` | Building type enum, placement validation, blueprint visibility, dictionary of all buildings |
| `Building` | `scripts/world/buildings/Building.gd` | Base building: states (BLUEPRINT→CONSTRUCTED→UNDER_DESTRUCTION), `player_owner`, `get_aoe_radius()`, tween-driven construction |
| `MCP` | `scripts/world/buildings/MCP.gd` | Main Control Point: rotating top animation, energy generation |
| `Vat` | `scripts/world/buildings/Vat.gd` | Energy storage: liquid-level tween, capacity calculation, `contains` set/get with underscore-backed var |
| `Zapper` | `scripts/world/buildings/Zapper.gd` | Laser beam effect (ImmediateMesh + RayCast3D), jaggies animation |
| `Blueprints` | `scripts/world/buildings/Blueprints.gd` | Ghost building preview, duplicate material assignment |
| `UnitManager` | `scripts/world/units/UnitManager.gd` | Unit type enum, `spawn_unit`/`rpc_spawn_unit`, `rpc_remove_unit`, `displace_units_on_tile`, server guard on spawn |
| `Unit` | `scripts/world/units/Unit.gd` | Base unit: states (IDLE/PATHING/WORKING), pathing, rotation (Quaternion slerp), `abandon_job`, `job_finished`, `move_tween` |
| `Zoomba` | `scripts/world/units/Zoomba.gd` | Bot unit: `initialise`, player-colour material, most logic commented out (scram, pathing jobs) |
| `JobManager` | `scripts/world/units/JobManager.gd` | Job queue per player, worker-centric assignment (`assign_nearest_job`), abandoned-job delay, debug renderer |

## Job system

### Lifecycle

```
Player clicks tile → apply_toggle → JobManager.add_job(TOGGLE_TILE, tile)
                                         ↓
GameManager._process (every 1s) → JobManager.assign_jobs()
                                         ↓
                          For each idle unit → assign_nearest_job(unit)
                                         ↓
                          Unit.assign_job(job) → state=PATHING
                                         ↓
                          pathing_callback → check_pathing_valid → start_work
                                         ↓
                          Unit.state=WORKING → tile.do_toggle_countdown(self)
                                         ↓
                          begin_toggle → done_toggle → unit.job_finished(true)
                                         ↓
                          JobManager.remove_job → Unit.remove_job → idle_callback
```

### Job states

| Job field | Meaning |
|---|---|
| `assigned` | Unit currently working on this job (null if unassigned) |
| `abandoned_n` | How many times this job has been abandoned (escalates retry delay) |
| `abandoned_timer` | Seconds until job is eligible for reassignment (11s × abandon_n, capped at 60s) |

### Abandon vs finish vs cancel

- **`unit.job_finished(work_was_done)`**: Job completed successfully. Removes job from pool entirely. Called by `TileElement.done_toggle()` (via `working_unit` ref) when toggle animation completes.
- **`unit.abandon_job()`**: Unit gives up but job stays in pool. Dispatches to `abandon_job_while_pathing()` or `abandon_job_while_working()`. Calls `JobManager.abandon_job(id)` which increments `abandoned_n` and sets `abandoned_timer`. Job is reassignable after timer expires.
- **`JobManager.cancel_job(pnum, type, tile)`**: Human deselects a tile. Removes job from pool entirely via `remove_job`.

### Tile disconnection / unit displacement

When a tile leaves the pathing grid (`set_rising` or building placement), `TileManager.remove_tile_from_pathing(tile)` is called:

1. `PathingManager.disconnect_tile(tile)` — removes all AStar edges from this tile
2. `UnitManager.displace_units_on_tile(tile)` — for each unit on the tile:
   - If unit has a job → `unit.abandon_job()` (job goes back to pool)
   - Kill active `move_tween`
   - Find first `LOWERED` neighbour with no building → teleport unit there
   - If no valid neighbour exists → `rpc("rpc_remove_unit", unit.id)` (destroy)

### Worker-centric assignment

`JobManager.assign_jobs()` runs two passes:
1. Decrement `abandoned_timer` for all unassigned jobs
2. For each idle unit (from `"unit"` group), call `assign_nearest_job(unit)` which finds the closest eligible job (matching `pnum`, unassigned, timer expired)

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

- `TileElement.gd`: `tween.remove`→`active_tween.kill`, `interpolate_method`→`tween_method`, `interpolate_property`→`tween_property`, `interpolate_callback`→`tween_callback`, signals use `.connect()`, `BUTTON_LEFT`→`MOUSE_BUTTON_LEFT`, `GlobalVars`→`Global`. `transform.origin.y = val`→copy-modify-set pattern. Added `aoe` array, `add_to_aoe(player_n)`, `pathing_manager` stored reference. Added `working_unit` for job callback, `done_toggle` calls `working_unit.job_finished(true)`, `begin_toggle` guards against invalid tile state.
- `TileManager.gd`: `BaseMaterial3D`→`StandardMaterial3D`, `set_surface_material`→`set_surface_override_material`, `set_multimesh()`→`.multimesh =`, `translation`→`position`, `use_in_baked_light` removed. Added `tiles()`, `recompute_aoe()`, `set_neighbours` assigns `pathing_manager` ref. Added `remove_tile_from_pathing(tile)`.
- `TileManager.tscn`: both `[node name="Tween"]` children removed.
- `PathingManager.gd`: `PackedInt32Array`→`PackedInt64Array`, added debug ImmediateMesh renderer with `toggle_debug()`. Added `disconnect_tile(tile)` for removing all edges from a tile.
- `Cairo.gd`: `GENERATE = false` with "do not regenerate" note.
- `MonorailMultimesh.gd`: not yet reviewed (entire body commented out).

### Building scripts

- `Building.gd`: `player_owner`, `get_aoe_radius()`. Removed `@onready var tween` — uses `create_tween()` + `_build_tween` var with `.kill()`/`.is_valid()`. `setget`→`set`/`get` blocks for `spawn_start_loc` and `my_blueprint`.
- `Vat.gd`: `contains`→`_contains_val` set/get. `tween.remove(liquid)`→`_liquid_tween.kill()` + `create_tween().tween_property(...)`.
- `BuildingManager.gd`: `StaticBody`→`StaticBody3D`, `DESTROYED`→`LOWERED`, `tile.set_destroyed()`→`tile.set_lowered()`, added `buildings()` returning `building_dictionary.values()`.
- `Zapper.gd`: `ImmediateGeometry`→`MeshInstance3D` + `ImmediateMesh`, `cast_to`→`target_position`, removed `tween.remove`/`tween.start`.
- `Zapper.tscn`: `type="ImmediateGeometry"`→`type="MeshInstance3D"`.
- `Blueprints.gd`: `get_name()`→`name`, `set_surface_material`→`set_surface_override_material`, `get_surface_material_count()`→`node.mesh.get_surface_count()` with null guard.
- `Blueprints.tscn`: removed orphan Tween node.
- `MCP.gd`: `push_back`→`append` (4 calls in `_ready`).
- `BuildingConstructedParticles.tscn`: full `format=2`→Godot 4 rewrite.
- Materials (`blueprint_enabled.tres`, `blueprint_disabled.tres`): removed `diffuse_burley,specular_schlick_ggx` from `render_mode`; `hint_color`→`source_color`; removed `SPECULAR = specular;`; added `SCREEN_TEXTURE : hint_screen_texture`.

### Unit scripts

- `Unit.gd`: `@rpc("authority", "call_local")` on `assign_job`, `idle_callback`, `move`, `quat_transform`, `setup_rotation`. `PackedInt32Array`→`PackedInt64Array`, `Quat`→`Quaternion`, `transform.origin` used correctly, `create_tween()` for movement/rotation. Added `abandon_job`, `abandon_job_while_pathing`, `abandon_job_while_working`, `move_tween` var. `pathing_callback` returns `abandon_job()` on invalid path, `job_finished()` on invalid job.
- `Zoomba.gd`: Removed `@onready var tween`, added `pathing_manager`. `PoolIntArray`→`PackedInt64Array`. `interpolate_method`→`create_tween().tween_method`, `interpolate_property`→`tween_property`, `interpolate_callback`→`tween_callback().set_delay()`. `Quat`→`Quaternion`, `translation`→`position`, `GlobalVars`→`Global`, `push_back`→`append`, `remove`→`remove_at`, `cast_to`→`target_position`. Most pathing/work logic is commented out.
- `UnitManager.gd`: Added `units()`, `_next_unit_id`, `rpc_remove_unit` (replaces `remove_unit`) with `@rpc("authority", "call_local")`, `displace_units_on_tile` + `_displace_unit` for tile disconnection handling. Server guard on `spawn_unit`.
- `JobManager.gd`: `GlobalVars`→`Global`, `push_back`→`append`, removed `var` on parameters, ImmediateGeometry→ImmediateMesh for debug renderer. Flipped assignment to worker-centric: `try_and_assign(job)` → `assign_nearest_job(unit)`. `assign_jobs()` now has two-pass structure (timer decrement then worker iteration).

### Camera / Floor scripts

- `OmniLight.gd`: `translation`→`position`, `GlobalVars`→`Global`, `get_world()`→`get_world_3d()`, `intersect_ray(old_args)`→`PhysicsRayQueryParameters3D.create()`, `result.empty()`→`result.is_empty()`.
- `CameraRTS.gd`: already Godot 4.
- `GridMultiMesh.gd`: `push_back`→`append` needed (lines 56, 57, 96).
- `Monument.gd` + `MonumentHelper.gd`: converted.
- Floor materials: `grid_faces.tres` and `grid_edges.tres` — `albedo` texture with `source_color`, `grid_edges.tres` has `use_instance_color` uniform for per-instance edge colour.

### Remaining Godot 3 patterns (active bugs)

| Pattern | File | Line(s) | Fix |
|---|---|---|---|
| `push_back` | `GridMultiMesh.gd` | 56, 57, 96 | `append()` |
| `push_back` | `TileElement.gd` | 336 | `append()` |
| `location.player` (nonexistent) | `Vat.gd` | 32 | `TileElement` has no `.player` |
| `tile.under_aoe` (nonexistent) | `BuildingManager.gd` | 37 | Should be `tile.aoe` |
| `empty()` on Dictionary | `JobManager.gd` | removed | Use `is_empty()` |
| Massive commented Godot 3 code | `CameraManager.gd` | most of file | Dead code, not converted |
| `translate()` (deprecated) | `TileManager.gd` | 50, 76, 86-91 | Prefer `position +=` |
| `translate()` (deprecated) | `Monument.gd` | 76, 79 | Prefer `position +=` |

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
