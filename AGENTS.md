# NeonFeverDreamMP — AGENTS.md

## Stack

- **Godot 4.7**, Jolt Physics, D3D12 renderer, Forward Plus
- Entrypoint: `scenes/menu/MainMenu.tscn`
- Autoloads (only two, see `project.godot`): `autoload/Global.gd` (holds `network_manager`, `game_config`, `my_player_number`, `level` preload) and `autoload/Config.gd` (all balance dicts + `get_damage()`).
- `Global.level` is a preload of `levels/skirmish_01.gd` — tile IDs, MCP positions, LOWERED/IMMUTABLE/INVISIBLE sets, seed. This is the only level.
- No tests, no lint, no typecheck config.

## World scene layout

`scenes/world/World.tscn` — managers are all siblings under the root, most marked `unique_name_in_owner`:

```
World
├── GameManager %       snapshot/interp + job tick (every 1s → assign_jobs + check_work)
├── BuildingManager %   blueprints, building dict, placement, empower, remove
├── EnergyManager %     energy sim (server only)
├── TileManager %       tile grid gen, selection sync, AoE recompute
│   └── PathingManager  AStar3D
├── UnitManager %       unit dict, spawn/remove, displacement
├── JobManager %        job pool + assignment
├── CombatManager %     target scanning + firing (server only)
├── CameraManager %     RTS↔FPS camera transitions, shake
│   ├── CameraRTS %
│   └── OmniLight3D_RTS %
├── ProjectilesHolder
└── HUD                 CanvasLayer, group "hud"
```

`%ManagerName` works in scene-owned scripts (unique_name_in_owner is set). Dynamically created nodes (TileElements) miss the owner lookup — gameplay code generally uses absolute `/root/World/...` paths or a stored ref instead.

## Multiplayer architecture

- ENet server-authoritative. `Server` node lives only on host (`scripts/core/network/Server.gd`).
- `NetworkManager` is **not** in any scene — instantiated at runtime by `MainMenu` and added to root.
- Host path: `Global.network_manager.server` (NOT a node path lookup — `get_node` fails due to dynamic parent). Remote path: `Global.network_manager` exists but `.server` is null.

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
- `send_command_me` uses `Global.my_player_number` and **no-ops when it's -1** (spectator / host with no LOCAL slot). Safe for host (set by `NetworkManager.start_server()` at LOCAL-slot creation) and remote (set by `NetworkManager.set_my_player_number` RPC).
- `send_command(pnum, ...)` is for AI controllers that know their own player number (`AIController` uses it for `toggle_tile`).
- The remote client's `pnum` is never trusted — the server always derives it from `peer_to_player`.
- Command handlers on `Server` are named `_cmd_<command>` and auto-dispatched via `callv` + `has_method`; `handle_command` validates arg count against the method signature. The `_cmd_` prefix is the allowlist. Adding a command = add `_cmd_<name>(player_number, ...)` to `Server.gd`, call it via `Global.send_command_me("<name>", [...])`.
- Full command surface (see `Server.gd`): `toggle_tile`, `place_blueprint`, `toggle_production`, `set_garage_ratio`, `set_beacon_ratio`, `set_nest_ratio`, `set_enemy_targets`, `set_building_targets`, `set_strike_priority`, `set_patrol_stance`, `set_virus_priority`, `empower`, `clear_empower`. Callers: `TileElement` mouse handlers, the building HUDs, `AIController`.

### Server-only guard pattern

All server-side simulation (`_process`/`_physics_process` in `EnergyManager`, `CombatManager`, `Building`, `Unit`, `GameManager`) guards the top:

```gdscript
func _process(delta):
	if not multiplayer.is_server():
		return
	...
```

Spawn/remove never run directly on clients — they're `@rpc("authority", "call_local")` (e.g. `UnitManager.rpc_spawn_unit`, `rpc_remove_unit`, `BuildingManager.broadcast_place_blueprint`, `rpc_remove_building`, `Building.rpc_constructed`), called via `rpc(...)` so the server executes locally and mirrors to peers. `TileManager._physics_process` runs on all peers — anything server-only called from it must self-guard.

### Snapshot / interpolation (`GameManager`)

- Server packs all units+buildings into one `PackedFloat64Array` every 0.05s (`SNAPSHOT_INTERVAL`), `rpc("apply_snapshot")` unreliable. Each entity = `SLOT_COUNT`(10) floats.
- Unit slots: pos x/y/z, rot.y, state, health, type-specific extras (ZOOMBA: zapper visible + target y; AERIAL: mode; VIRUS: cloaked), `combat_target` (0=none, +unit id, -building id), `combat_fire_event` (visual trigger). AVATAR packs its `FPSBody` transform, not the root.
- Clients buffer up to `MAX_SNAPSHOT_BUFFER`(4) and interpolate with `INTERPOLATION_DELAY`(0.075) render time.
- Avatars: each client sends `receive_avatar_snapshot` at 20Hz **only while `CameraManager.camera_status == FPS`**; the server interpolates per-pnum avatar snapshots for the other peers. Clients skip their own avatar in `_apply_interpolated`/`_apply_snapshot_entities` to avoid control cycles.
- `_apply_unit` asserts type match and is client-only — the server never mutates client state.

## Key classes

| Class | File | Role |
|---|---|---|
| `Global` | `autoload/Global.gd` | Singleton: `network_manager`, `my_player_number`, `level` preload, command relay, `MAX_PLAYERS=4` |
| `Config` | `autoload/Config.gd` | Static balance dicts (`BUILDING_AOE`, `BUILDING_MAX_HP`, `CONSTRUCTION_COST`, `UNIT_COST`, `PRODUCTION_COOLDOWNS`, `UNIT_SPEED`, `UNIT_MAX_HP`, `HOME_TERRITORY_UNITS`, `SELF_HEALING_UNITS`, `PLAYER_COLORS`, combat consts) + `get_damage()` |
| `NetworkManager` | `scripts/core/network/NetworkManager.gd` | Creates `Server` + local AI controllers, or ENet client; assigns LOCAL/AI player numbers; `set_my_player_number` RPC |
| `Server` | `scripts/core/network/Server.gd` | ENet server, `peer_to_player`/`player_to_peer`, `_cmd_*` dispatch |
| `TileManager` | `scripts/world/tiles/TileManager.gd` | Cairo pentagon grid gen, `State` enum, `apply_toggle`, `recompute_aoe` (+`player_aoe_totals`/`player_aoe_rings`/`gen_count`), `remove_tile_from_pathing`, tile selection broadcast |
| `TileElement` | `scripts/world/tiles/TileElement.gd` | One tile: state transitions, neighbours, `aoe`/`selected_by`, MultiMesh visuals, emission priority system, `_working_unit_dict` countdown chain, mouse input → `send_command_me` |
| `PathingManager` | `scripts/world/tiles/PathingManager.gd` | AStar3D, `connect_tiles`/`disconnect_tiles`/`disconnect_tile`, `pathfind`, debug renderer |
| `MonorailMultimesh` | `scripts/world/tiles/MonorailMultimesh.gd` | Active: monorail rail meshes + caps between tiles, tweened connect/disconnect |
| `GameConfig` | `scripts/core/game/GameConfig.gd` | Resource: `player_count`, `port`, `server_ip`, `slots` array (LOCAL/REMOTE/AI/CLOSED) |
| `GameManager` | `scripts/core/game/GameManager.gd` | Snapshots/interpolation, 1s job tick (`%JobManager.assign_jobs()` + each building `check_work()`), avatar relay |
| `EnergyManager` | `scripts/core/game/EnergyManager.gd` | Server-only energy sim (see Economy) |
| `CombatManager` | `scripts/core/game/CombatManager.gd` | Server-only target scan + firing (see Combat) |
| `AIController` | `scripts/core/ai/AIController.gd` | Random `toggle_tile` on a timer via `send_command(player_number, ...)` |
| `BuildingManager` | `scripts/world/buildings/BuildingManager.gd` | `Type` enum (MCP_1..4, GEN, VAT, GARAGE, BEACON, NEST), blueprints, building dict, `place_blueprint`/`place_building`/`rpc_remove_building`, empower tracking, `recompute_aoe` hookups |
| `Building` | `scripts/world/buildings/Building.gd` | Base: states BLUEPRINT→UNDER_CONSTRUCTION→CONSTRUCTED, `player_owner`, `get_aoe_radius()`, `check_work()` (adds REPAIR_BUILDING jobs), construction/production via energy, `apply_damage`, repair, terminal positioning, per-building HUD SubViewport |
| `MCP` | `scripts/world/buildings/MCP.gd` | Main Control Point: produces AVATAR first then ZOOMBA up to `zoomba_cap`; counts as generator+vat |
| `Generator` | `scripts/world/buildings/Generator.gd` | Energy output = sum of `gen_count` over its AoE tiles; hover shows catchment |
| `Vat` | `scripts/world/buildings/Vat.gd` | Capacity = 1000 + 100/adjacent same-owner Vat, ×1.2 if empowered; liquid-level visual |
| `Garage` | `scripts/world/buildings/Garage.gd` | Creates CONSUME_ZOOMBA jobs (zoomba → TANK conversion), `zoomba_tank_ratio`, patrol orders |
| `Beacon` | `scripts/world/buildings/Beacon.gd` | Produces AERIAL, patrol/strike orders, `patrol_strike_ratio`, strike priority/stance |
| `Nest` | `scripts/world/buildings/Nest.gd` | Produces VIRUS, attack orders, `_virus_tank_building_ratio`, priority |
| `Zapper` | `scripts/world/buildings/Zapper.gd` | Laser beam visual (ImmediateMesh + RayCast3D) |
| `Blueprints` | `scripts/world/buildings/Blueprints.gd` | Ghost preview, material assignment, collision enable |
| `UnitManager` | `scripts/world/units/UnitManager.gd` | `Type` enum (NONE, AVATAR, ZOOMBA, TANK, AERIAL, VIRUS), `spawn_unit` (via `rpc_spawn_unit`), `rpc_remove_unit`, `displace_units_on_tile`, `unit_count` |
| `Unit` | `scripts/world/units/Unit.gd` | Base unit: IDLE/PATHING/WORKING, job lifecycle, health, self-heal, scram, combat aim/fire-event visuals, `apply_damage` |
| `Zoomba` | `scripts/world/units/Zoomba.gd` | Basic unit, player-colour material |
| `Tank` | `scripts/world/units/Tank.gd` | Anti-air unit (only damages AERIAL) |
| `Aerial` | `scripts/world/units/Aerial.gd` | Flying, patrol/strike modes, projectile delay |
| `Virus` | `scripts/world/units/Virus.gd` | Cloaked attack unit |
| `Avatar` | `scripts/world/units/Avatar.gd` | FPS character: `FPSBody` (CharacterBody3D + FPSCamera), ignores job system, screen-cursor terminal clicks |
| `JobManager` | `scripts/world/units/JobManager.gd` | Job pool + worker-centric assignment, abandon timers, `personal` jobs, job-event notifications |
| `CameraManager` | `scripts/world/camera/CameraManager.gd` | CameraStatus (OVERHEAD/TO_FPS/FPS/TO_OVERHEAD), 2s transition tween, mouse capture, trauma shake. **Converted — no dead Godot 3 code.** |
| `CameraRTS` | `scripts/world/camera/CameraRTS.gd` | Overhead camera controls |
| `HUD` | `scripts/ui/HUD.gd` | Tile/build mode buttons, drag select, energy bar, FPS toggle, debug keys |
| `NotificationManager` | `scripts/ui/NotificationManager.gd` | Job-event on-screen notifications (`rpc_add_job_notification`) |
| `HealthBar3D` | `scripts/ui/HealthBar3D.gd` | Billboard health bars for units + buildings |

## Level system

- `Global.level` = `levels/skirmish_01.gd`. It defines `SEED`, `TRIPLETS`/`BORDER_TRIPLETS` (arena size), `MCP_ARRAY` (tile ids; index+1 = player number), `LOWERED`, `IMMUTABLE`, `INVISIBLE`.
- `TileManager.populate()` marks tiles IMMUTABLE/INVISIBLE as DISABLED (`disabled`/`invisible` groups) vs `interactive`. `apply_loaded_level()` places each MCP via `BuildingManager.place_building(...)` and lowers the LOWERED tiles, then `recompute_aoe()`.
- Tile IDs are the deterministic generation order — editing the level means editing these ID arrays.

## Tile system

- `TileManager.State` = RAISED, FALLING, LOWERED, RISING, DISABLED. Tiles are `StaticBody3D` + one MultiMesh instance (`enabled_tiles_to_multimesh`), 5 pentagon neighbours, `pathing_centre` for pathfinding, `location` for units/buildings.
- `apply_toggle(pnum, tile_id)` (server only, **never called directly** — go through `send_command`) toggles a player's `selected_by` claim. RAISED/LOWERED only; LOWERED+has building is rejected; returns false on deselect → `JobManager.cancel_job`. Selection broadcast via `broadcast_tile_selection`.
- Access tiles: `get_access_tiles(require_aoe=0)` — LOWERED neighbours with no building, optionally filtered to own AoE. Used everywhere (wandering, pathing targets, terminal placement, displacement).
- AoE: `recompute_aoe()` BFS from each building's `get_aoe_radius()`, deterministic on all peers. Fills `tile.aoe`, `tile.gen_count` (for GEN), `player_aoe_totals` (split shares), `player_aoe_rings`, then pokes generators/vats + `EnergyManager.recalculate_capacity()` and un-selects tiles no longer under AoE. Re-run after building place/remove.

### Per-instance visual data (MultiMesh)

Three independent channels on each tile instance:

| Channel | Written by | Read by | Purpose |
|---|---|---|---|
| `INSTANCE_CUSTOM.rgba` | `set_tile_mm_selecting_mask` | `aluminium.tres` vertex→`selecting_mask` | Band stripes — player AoE claims (r=g=p1 etc.) |
| `COLOR.rgb` | `set_tile_mm_color` | `grid_edges.tres` fragment → `ALBEDO` | Edge color — hover indicator |
| `COLOR.a` | `set_tile_mm_emission` | `aluminium.tres` fragment → `EMISSION`+`EMISSION_ENERGY` | White glow intensity |

`set_tile_mm_color` preserves `a`, `set_tile_mm_emission` preserves `rgb`. On top sits an **emission priority system**: `TileElement.EmissionEffect` (GENERATOR_CATCHMENT > TILE_SELECTED > TILE_HOVER > PULSE_ANIMATION) with `request_emission`/`release_emission` writing the active effect into COLOR.a; `_apply_emission` skips while the toggle tween/countdown tweens run.

## Job system

### Unit states

Every unit has exactly one of three states. State transitions are the core of the job system.

| State | Meaning |
|---|---|
| `IDLE` | No job. Unit wanders randomly between accessible tiles (own-AoE preferred for `HOME_TERRITORY_UNITS`). |
| `PATHING` | Has a job. Unit is pathfinding toward the target tile. |
| `WORKING` | At target tile. Unit is performing the job action. |

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

### Job types

`JobManager.Type` = CONSTRUCT_BUILDING, REPAIR_BUILDING, TOGGLE_TILE, CONSUME_ZOOMBA. `start_work()` routes:
- `TOGGLE_TILE` → `tile.do_toggle_countdown(self)` (tile owns the callback chain)
- `CONSTRUCT_BUILDING` → `building.start_construction(self)`
- `REPAIR_BUILDING` → `building.start_repair(self)`
- `CONSUME_ZOOMBA` → `_consume_for_tank()` (spawns a TANK at the garage, then removes this zoomba)

### Unit.gd functions

**`idle_callback()`** — Idle loop entry. If `job` non-empty: asserts PATHING, clears path, calls `pathing_callback()`. If empty: picks a random accessible tile (own-AoE preferred for HOME_TERRITORY_UNITS; PATROL+HOLD units restricted to their building's `_aoe_tiles`), avoids backtracking, calls `move(idle_callback)`. Scrammed units (`scram_count > 0`) head toward their MCP instead.

**`pathing_callback()`** — Each pathfinding step: checks scram first (→ IDLE + `idle_callback`), `JobManager.check_job_still_valid` (→ `job_finished()`), reached `path_dest` (→ `start_work()`), `check_pathing_valid()` (→ `abandon_job()`), then moves to next node.

**`check_pathing_valid()`** — Validates remaining path nodes are still LOWERED (else invalidates). If path empty, re-paths from current location to all access tiles of the target, picking the shortest; sets `job["path_dest"]`. Returns false (→ abandon) if unreachable. Handles tiles lowered/raised mid-path, displaced edges, and access tiles changing.

**`start_work()`** — PATHING → WORKING, quick-rotate, zapper on, dispatch by job type (above).

**`job_finished()`** — Job completed/removed: hides zapper, state=IDLE, `JobManager.remove_job(job["id"])` (which calls our `remove_job()`).

**`remove_job()`** — Called by `JobManager.remove_job()`. If WORKING → `_cleanup_working_state()`. Sets IDLE, kills `move_tween` (prevents stale callbacks), clears `job`, calls `idle_callback()` unconditionally.

**`_cleanup_working_state()`** — Shared by `remove_job`/`abandon_job` when WORKING: hides zapper, kills `_rotate_tween`, cancels tile countdown (`cancel_toggle_countdown`) or building construction.

**`abandon_job()`** — Cleans working state if WORKING, sets IDLE, kills tween, `JobManager.abandon_job(id)` (job stays in pool), `idle_callback()`.

**`move(callback)`** — Kills previous tween, slerps rotation + moves to `location.pathing_centre`, calls callback. IDLE moves at 2x speed; scram at 0.5x. `move_tween` is a plain var (Tween is RefCounted).

**`scram()`** — `ui_scram` key (C): `scram_count = SCRAM`; if busy, `abandon_job()`. Scrambled units aren't assigned jobs and aren't eligible during `assign_jobs`.

### JobManager.gd

- **`add_job(pnum, type, location, personal=false)`** — dedupes identical pnum/type/location jobs. `personal` jobs can't be reassigned — they're erased on abandon.
- **`cancel_job`** — deselect → `remove_job`. **`remove_job(id)`** — permanent deletion; if assigned, calls `unit.remove_job()`. **`abandon_job(id)`** — stays in pool, `abandoned_n`++, timer `min(60, abandoned_n × 11)`, clears `assigned`; personal jobs are erased instead.
- **`assign_jobs()`** (every 1s from GameManager) — two passes: decrement abandon timers, then for each idle unit (skipping AVATAR and `scram_count > 0`) → `assign_nearest_job(unit)` (shortest path length among eligible unassigned jobs for that player).
- **`check_job_still_valid(job)`** — per-type: CONSTRUCT_BUILDING (blueprint present), TOGGLE_TILE (state RAISED/LOWERED + still `selected_by`), REPAIR_BUILDING (damaged), CONSUME_ZOOMBA (constructed GARAGE). New job types extend this `match`.
- **`_notify_job_event`** — server-side job add/assign/abandon/finish → `NotificationManager.rpc_add_job_notification`.

### TileElement.gd (tile-side job support)

- **`do_toggle_countdown(z)`** — server-only. Adds entry to `_working_unit_dict[pnum]` with unit/job and a 2s countdown tween → `begin_toggle`. RPC mode 0 = visual countdown.
- **`cancel_toggle_countdown(pnum)`** — server-only. Removes entry, kills its tween, RPC mode 1.
- **`_cancel_other_workers(except_pnum)`** — `begin_toggle` kills all other workers' countdowns, calls `job_finished()` on their units, RPC mode 1 each.
- **`begin_toggle()`** — server-only. First countdown fires: if tile state changed during countdown → `job_finished()` all workers (abort). Else cancel others, transition RAISED→FALLING / LOWERED→RISING, clear `selected_by`, broadcast, second tween (`fall_time + thunk_time`) → `done_toggle`.
- **`done_toggle()`** — server-only. Completes state change (set_lowered / RAISED + position reset). For each worker whose job is still assigned to its unit → `JobManager.remove_job`. Clears `_working_unit_dict`.

Two tweens per tile: `_countdown_tweens` (server-only per-player countdown → begin_toggle) and `toggle_tween` (synced visual, created by `rpc_toggle_animation` modes 0/2; `_apply_emission` skips while it runs).

### Job finish vs abandon vs cancel

| Outcome | Who triggers | Job lifecycle | Unit lifecycle | Tile lifecycle |
|---|---|---|---|---|
| **Finish** | Tile animation → `done_toggle` → `job_finished()` | Removed (`remove_job`) | → IDLE → `idle_callback` | State change completed, dict cleared |
| **Cancel** | Human deselects → `cancel_job` → `remove_job` | Removed | → IDLE → `idle_callback` | `remove_job` cancels countdown if WORKING |
| **Abandon (pathing)** | Path invalid → `abandon_job()` | Stays in pool, reassignable after timer | → IDLE → `idle_callback` | N/A |
| **Abandon (working)** | Unit gives up → `abandon_job()` | Stays in pool | → IDLE → `idle_callback` | Countdown cancelled, dict entry removed |
| **Displacement** | Tile leaves pathing → `_displace_unit` | Stays in pool (`abandon_job`) | Teleported to adjacent tile or destroyed | N/A |

### Tile disconnection / displacement

`TileManager.remove_tile_from_pathing(tile)` (from `set_rising` or building placement):
1. `PathingManager.disconnect_tile(tile)` — drops AStar edges.
2. `UnitManager.displace_units_on_tile(tile)` — per unit on the tile: cleanup job without `idle_callback` (IDLE, `JobManager.abandon_job`), kill `move_tween`, teleport to first LOWERED neighbour with no building, then one `idle_callback()`; if no valid neighbour → `rpc_remove_unit`.

### Job dict fields

`id`, `pnum`, `type`, `location` (TileElement), `assigned` (Unit/null), `personal` (bool), `abandoned_by`, `abandoned_n`, `abandoned_timer`. Plus transient `path_dest` set during pathing.

## Economy & production

- **EnergyManager** (server-only): 0.05s tick sums `get_energy()` over CONSTRUCTED `generator`-group buildings (MCP=27 fixed, Generator=sum of `gen_count` on its AoE tiles), fills `energy[p]` up to `capacity[p]`; 1s tick computes `rate_of_change` and shortfall ratio. `request_energy(pnum, amount)` deducts (returns allocated). `recalculate_capacity()` sums CONSTRUCTED `vat`-group `get_capacity()`. Broadcasts `apply_energy` (unreliable) per player. **Dicts are 1-based** — iterate `range(1, Global.MAX_PLAYERS + 1)`, never `for p in Global.MAX_PLAYERS`.
- **Construction**: BLUEPRINT building's `_process` consumes energy at `CONSTRUCTION_COST / CONSTRUCTION_TIME`; at full → `set_constructed()` (`rpc_constructed` removes the blueprint and reveals the building).
- **Production**: CONSTRUCTED building accumulates `_production_energy` via `request_energy`; at `UNIT_COST` → spawn via `um.rpc("rpc_spawn_unit", uid, type, building_id)`; cooldown from `Config.PRODUCTION_COOLDOWNS`. MCP overrides: AVATAR first, then ZOOMBA up to `zoomba_cap = floor(sqrt(player_aoe_totals[pnum]))`. Garage overrides: issues CONSUME_ZOOMBA jobs instead of spawning directly. Beacon → AERIAL, Nest → VIRUS.
- **Empower**: `BuildingManager.set_empowered_for_player` (one building per player, swap clears the previous), `rpc_set_empowered`, subclasses react in `_empower_changed` (Vat ×1.2 capacity).
- Building HUDs: each building gets its own `SubViewport` + HUD scene (`_setup_hud`), rendered into the `Terminal/Screen` material; terminal positioned at the access tile nearest the MCP (`position_terminal`).

## Combat

- **CombatManager** (server-only): every 0.5s re-scan TANK/AERIAL units; score = `dmg × 10 - health`, must pass range (40) and line-of-sight (raycast that ignores LOWERED/FALLING tiles and self/target). Units without `orders["enemy"]` target any other player.
- Firing: when weapon aligned (`Unit.is_weapon_aligned()`, slerped in `update_weapon_aim`), bursts of `WEAPON_BURST_DURATION`(0.4) with damage ticks every 0.1s. TANK fires an instant burst; AERIAL applies a projectile delay (`update_projectile_delay`). `combat_fire_event` is bumped server-side and drives client visuals (`_update_combat_visuals`).
- **Damage** via `Config.get_damage(attacker_type, target, mode)`: TANK damages only AERIAL (×6 patrol / ×5 strike). AERIAL damages VIRUS ×5 (patrol) / BUILDING ×2 (strike), plus mode-vs-mode multipliers. `apply_damage(amount, delay)` on server → health; ≤0 removes unit/building. `SELF_HEALING_UNITS` (ZOOMBA, TANK) heal server-side.
- Health bars: `HealthBar3D` for units and buildings. Debug keys in HUD: `ui_damage_building` (P), `ui_damage_unit` (L) deal 40% max health.

## Avatar / FPS camera

- `CameraManager.CameraStatus` = OVERHEAD → TO_FPS → FPS → TO_OVERHEAD. Toggle via HUD button or `ui_capture_toggle`; 2s transition tween, mouse captured in FPS. Trauma/shake via `add_trauma`.
- `Avatar` (`scenes/world/units/Avatar.tscn`) = Unit with `FPSBody` (CharacterBody3D + `Rotation_Helper`/`FPSCamera`). WASD + `ui_movement_jump` movement, mouse look, ray for tile selection (jagged beam), `ScreenRay` for clicking the MCP terminal HUD (`ScreenBody` collision → `Cursor3D`-style cursor + click).
- Avatars skip the job system entirely (`idle_callback` no-op; `assign_jobs` skips AVATAR; not in `HOME_TERRITORY_UNITS`). Avatar snapshots are relayed separately (see Snapshot section).

## Godot 4 conversion patterns

- **Tween** is RefCounted, not a Node: `create_tween()`, chained `tween_property/tween_method/tween_callback`, auto-starts. Store in a local/plain var, kill with `tween.kill()` + guard `tween and tween.is_valid()`, never `@onready`.
- **`setget` → set/get blocks** with underscore-backed var (`var _contains_val` backed by `contains`).
- **`@rpc` annotations**: `@rpc("authority", "call_local")` (server call runs everywhere), `@rpc("any_peer", "call_remote")` (client→server, derive caller via `get_remote_sender_id()`), plus `"reliable"`/`"unreliable"`.
- **ImmediateMesh**: `clear_surfaces()` / `surface_begin()` / `surface_add_vertex()` instead of ImmediateGeometry.
- **Materials**: player colour at `res://materials/player/player<N>_material.tres` (1..4, matches `PLAYER_COLORS`). Floor: `res://materials/floor/grid_faces.tres` (lit) + `grid_edges.tres` (unshaded cyan, `use_instance_color`).
- The whole codebase is converted — no Godot 3 syntax remains (this file's old "Remaining patterns" list is resolved).

## Gotchas

- `Server.next_player_num` is set by `NetworkManager.start_server()` after LOCAL/AI slots claim numbers — do not hard-code it.
- `rpc_id(1, ...)` targets the server (peer 1 is always the server in ENet).
- `TileManager.apply_toggle` validates `tile.state == RAISED` and LOWERED-with-no-building before toggling. Never call it directly — use `Global.send_command*`.
- `Global.my_player_number` = -1 for a host with no LOCAL slot (spectator); `send_command_me` no-ops and HUD energy reads 0.
- `%` unique-node lookup requires caller `owner`. Dynamically created TileElements miss this → use a stored `pathing_manager` ref (set by `TileManager.set_neighbours`) instead of `%PathingManager`.
- `TileElement` has no `.player` — check `.selected_by` / `.aoe` / `player_owner` on buildings/units.
- Server-only functions called from `_process`/`_physics_process` (which run on all peers) must self-guard.
- `create_tween()` returns RefCounted — local var, `.kill()` + `.is_valid()` guard, no `@onready`.
- Unit/buildings are spawned/removed only via `@rpc("authority","call_local")` RPCs; never add children directly on a client.
- `EnergyManager`/job/player dicts are 1-based (1..`MAX_PLAYERS`). Loops: `range(1, Global.MAX_PLAYERS + 1)`.

## Lobby flow

- When any REMOTE slot exists, "Start Lobby" loads `scenes/menu/Lobby.tscn`; otherwise straight to `World.tscn`. Remote clients always land on `Lobby.tscn` and wait.
- Lobby waits until `Server.peer_to_player.size()` == REMOTE slot count, then host `rpc("remote_start_game")` + everyone loads World.
- AI controllers check `/root/World/TileManager` existence and skip actions while it's absent (lobby).
- Back button: `Global.network_manager.stop()` + `queue_free()` + null it, then MainMenu.
- `NetworkManager.stop()` closes the client ENet peer too (`multiplayer.multiplayer_peer.close()`), not just the server peer.

## Floor (decorative only, no multiplayer sync)

- `scenes/world/floor/Floor.tscn` — 50×50 visual floor with animated mountains (vertex displacement via per-instance custom data), monuments with pulsing beacon, no collision, no RPCs. Timer morphs mountains via `create_tween()` → `tween_method()` → `update_mountain(idx, color)`.

## UI rules

- One LOCAL slot max — selecting LOCAL on a second slot snaps the first back to Remote (`MainMenu._on_slot_selected`). Zero LOCAL slots = Spectator mode.
- HUD modes: RAISE/LOWER (tile toggle, drag-select via `begin_drag`/`should_toggle`) and building placement (GEN/VAT/GARAGE/BEACON/NEST) → `TileElement` click sends `place_blueprint`. Building HUDs (SubViewports) send all building commands via `send_command_me` — commands carry `building_id`, never a node reference.

## Running

- Pass `--client` as CLI arg to launch a second instance on the Connect tab (`MainMenu` checks `OS.get_cmdline_args()`).
- Default config for instances: "Run Instances" in the Godot editor with `--client` on the second.
