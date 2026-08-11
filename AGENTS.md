# NeonFeverDreamMP — AGENTS.md

## Stack

- **Godot 4.7**, Jolt Physics, D3D12 renderer, Forward Plus
- Entrypoint: `scenes/menu/MainMenu.tscn`
- `DESIGN.md` is the game design doc (unit/building tables, combat matrix, economy intent) — gameplay code comments cite it as "per DESIGN".
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
├── StatisticsManager % 1s stat sampling + per-player history sync (server only)
├── VideoManager %      RTS↔FPS camera transitions, shake
│   ├── CameraRTS %
│   └── OmniLight3D_RTS %
├── ProjectilesHolder
├── HUD                 CanvasLayer, group "hud"
├── StatisticsWindow    CanvasLayer (layer 50), group "statistics_window"; modal stats graphs (M-key in RTS)
└── LoadingOverlay      group "loading_overlay"; World-load progress, hidden by GameManager at game start
```

Managers are accessed via the typed `Global` aliases above (all null until World loads). `%ManagerName` unique-name lookup still works in scene-owned scripts but is deprecated in favour of the `Global` aliases. Dynamically created nodes (TileElements) miss the owner lookup — gameplay code should use the `Global` aliases or a stored ref instead.

Every manager registers itself in its `_ready()` on `Global` with a short alias: `Global.GM` (GameManager), `Global.BM` (BuildingManager), `Global.EM` (EnergyManager), `Global.TM` (TileManager), `Global.UM` (UnitManager), `Global.JM` (JobManager), `Global.CM` (CombatManager), `Global.SM` (StatisticsManager), `Global.VM` (VideoManager), `Global.PM` (PathingManager), `Global.NM` (NotificationManager). All are null until World loads. Prefer these over `get_node_or_null("/root/World/...")`.

### Manager null-safety — when guards are allowed

Once World's `_ready()` cascade has completed, every `Global.X` alias is guaranteed non-null for any `_process`/`_physics_process`/RPC/input/signal handler. Godot runs all `_ready()`s synchronously during scene-tree entry (in scene order), before the first frame of `_process`/`_physics_process`; level setup (`TileManager` first-physics-frame generation, MCP placement, `recompute_aoe`, `recalculate_capacity`) runs after all managers have registered; server-only sims additionally gate on `Global.game_started`; and the game-start gate (`GameManager`) holds RPCs until every client confirms World is ready (server force-starts after `READY_TIMEOUT` 15s regardless). **Do not write `if Global.X:` / `if not <manager-var>:` null guards in gameplay code — access `Global.X` directly.**

Guard only where a manager may genuinely be absent:

- `Server.gd` `_cmd_*` handlers — the `Server` node exists from MainMenu, before World; commands can arrive pre-World (lobby, premature/malicious clients). Keep `var tm = Global.TM; if not tm: return`.
- `AIController._on_timer` — runs during the lobby, before World/game exists (documented lobby-skip).
- `_exit_tree` teardown paths touching a manager — during World unload `Global.X` may reference a freed node; use `is_instance_valid(Global.X)` rather than a truthiness guard.

When code legitimately needs a manager twice or more in one function, hoist it once into a local (`var um = Global.UM`); otherwise inline `Global.X.method()`.

## Multiplayer architecture

- ENet server-authoritative. `Server` node lives only on host (`scripts/core/network/Server.gd`).
- `NetworkManager` is **not** in any scene — instantiated at runtime by `MainMenu` and added to root.
- Host path: `Global.network_manager.server` (NOT a node path lookup — `get_node` fails due to dynamic parent). Remote path: `Global.network_manager` exists but `.server` is null.

### Unified command relay: `Global.send_command_me()` / `send_command()`

Every game action follows the same two-line pattern — no manual branching:

```gdscript
# Any caller, host or remote, human or AI:
Global.send_command_me("toggle_tile", [tile_id])
Global.send_command(ai_pnum, "toggle_tile", [tile.get_id()])  # AIController pattern
```

**Route**:
```
send_command_me / send_command
  ├─ Server exists? → Server.handle_command(pnum, command, args)
  │                     └─ reflection → _cmd_toggle_tile / _cmd_place_blueprint / ...
  └─ No server (remote client)? → rpc_id(1, "_on_remote_command", ...)
								   └─ Server._on_remote_command()
									  └─ peer_to_player[caller] → handle_command(pnum, ...)
```

**Key points**:
- `send_command_me` uses `Global.my_player_number` and **no-ops when it's -1** (spectator / host with no LOCAL slot). Safe for host (set by `NetworkManager.start_server()` at LOCAL-slot creation) and remote (set by `NetworkManager.set_my_player_number` RPC).
- `send_command(pnum, ...)` is for AI controllers that know their own player number (`AIController` uses it for `toggle_tile`).
- The remote client's `pnum` is never trusted — the server always derives it from `peer_to_player`.
- Command handlers on `Server` are named `_cmd_<command>` and auto-dispatched via `callv` + `has_method`; `handle_command` validates arg count against the method signature. The `_cmd_` prefix is the allowlist. Adding a command = add `_cmd_<name>(player_number, ...)` to `Server.gd`, call it via `Global.send_command_me("<name>", [...])`.
- Full command surface (see `Server.gd`): `toggle_tile`, `place_blueprint`, `toggle_production`, `set_garage_ratio`, `set_beacon_ratio`, `set_nest_ratio`, `set_enemy_targets`, `set_building_targets`, `set_patrol_stance`, `empower`, `clear_empower`; plus `camera_mode` (clients report their camera state — drives the per-player avatar VIRUS-detect radius) and `debug_damage_unit`/`debug_damage_building` (server-authoritative debug keys). Callers: `TileElement` mouse handlers, the building HUDs, `VideoManager` (`camera_mode`), `AIController`, HUD debug keys.

### Server-only guard pattern

All server-side simulation (`_process`/`_physics_process` in `EnergyManager`, `CombatManager`, `StatisticsManager`, `Building`, `Unit`, `GameManager`) guards the top:

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
- Avatars: each client sends `receive_avatar_snapshot` at 20Hz **only while `Global.VM.camera_status == FPS`**; the server interpolates per-pnum avatar snapshots for the other peers. Clients skip their own avatar in `_apply_interpolated`/`_apply_snapshot_entities` to avoid control cycles.
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
| `GameManager` | `scripts/core/game/GameManager.gd` | Snapshots/interpolation, 1s job tick (`Global.JM.assign_jobs()` + each building `check_work()`), avatar relay |
| `EnergyManager` | `scripts/core/game/EnergyManager.gd` | Server-only energy sim (see Economy) |
| `CombatManager` | `scripts/core/game/CombatManager.gd` | Server-only target scan + firing, VIRUS uncloak (aerial/avatar detection), shared `choose_building_target` (see Combat) |
| `StatisticsManager` | `scripts/core/game/StatisticsManager.gd` | Server-only 1s stats sampler; per-player history (`aoe_size`, energy, unit counts, damage done/received); `rpc_receive_stats` pushes each finalized record to the owning client (see Statistics) |
| `AIController` | `scripts/core/ai/AIController.gd` | Random `toggle_tile` on a timer via `send_command(player_number, ...)` |
| `BuildingManager` | `scripts/world/buildings/BuildingManager.gd` | `Type` enum (MCP_1..4, GEN, VAT, GARAGE, BEACON, NEST), blueprints, building dict, `place_blueprint`/`place_building`/`rpc_remove_building`, empower tracking, `recompute_aoe` hookups |
| `Building` | `scripts/world/buildings/Building.gd` | Base: states BLUEPRINT→UNDER_CONSTRUCTION→CONSTRUCTED, `player_owner`, `get_aoe_radius()`, `check_work()` (adds REPAIR_BUILDING jobs while production is enabled), construction/production via energy, `apply_damage`, repair, terminal positioning, per-building HUD SubViewport |
| `MCP` | `scripts/world/buildings/MCP.gd` | Main Control Point: produces AVATAR first then ZOOMBA up to `zoomba_cap`; counts as generator+vat |
| `Generator` | `scripts/world/buildings/Generator.gd` | Energy output = Σ `1/gen_count` over its AoE tiles (each tile's output split N ways); hover shows catchment |
| `Vat` | `scripts/world/buildings/Vat.gd` | Capacity = 1000 + 100/adjacent same-owner Vat, ×1.2 if empowered; liquid-level visual |
| `Garage` | `scripts/world/buildings/Garage.gd` | Creates CONSUME_ZOOMBA jobs (zoomba → TANK conversion), `zoomba_tank_ratio`, patrol orders |
| `Beacon` | `scripts/world/buildings/Beacon.gd` | Produces AERIAL, patrol/strike orders, `patrol_strike_ratio`, patrol stance |
| `Nest` | `scripts/world/buildings/Nest.gd` | Produces VIRUS, attack orders, `_virus_tank_building_ratio` |
| `Zapper` | `scripts/world/buildings/Zapper.gd` | Laser beam visual (ImmediateMesh + RayCast3D) |
| `Blueprints` | `scripts/world/buildings/Blueprints.gd` | Ghost preview, material assignment, collision enable |
| `UnitManager` | `scripts/world/units/UnitManager.gd` | `Type` enum (NONE, AVATAR, ZOOMBA, TANK, AERIAL, VIRUS), `spawn_unit` (via `rpc_spawn_unit`), `rpc_remove_unit`, `displace_units_on_tile`, `unit_count` |
| `Unit` | `scripts/world/units/Unit.gd` | Base unit: IDLE/PATHING/WORKING, job lifecycle, health, self-heal, scram, combat aim/fire-event visuals, `apply_damage` |
| `Zoomba` | `scripts/world/units/Zoomba.gd` | Basic unit, player-colour material |
| `Tank` | `scripts/world/units/Tank.gd` | Anti-air unit (only damages AERIAL) |
| `Aerial` | `scripts/world/units/Aerial.gd` | Flying, patrol/strike modes, projectile delay, 120s lifetime (auto-removed); STRIKE self-generates personal COMBAT_PERSUE jobs |
| `Virus` | `scripts/world/units/Virus.gd` | Cloaked limpet unit: personal `ATTACK` jobs from Nest orders, spawns uncloaked → re-cloaks after 5s, drains TANKs (dies with the tank) or channels a building infection (self-sacrifice, effect stubbed) |
| `Avatar` | `scripts/world/units/Avatar.gd` | FPS character: `FPSBody` (CharacterBody3D + FPSCamera), ignores job system, screen-cursor terminal clicks |
| `JobManager` | `scripts/world/units/JobManager.gd` | Job pool + worker-centric assignment, abandon timers, `personal` jobs, job-event notifications |
| `VideoManager` | `scripts/world/camera/VideoManager.gd` | CameraStatus (OVERHEAD/TO_FPS/FPS/TO_OVERHEAD), 2s transition tween, mouse capture, trauma shake. **Converted — no dead Godot 3 code.** |
| `CameraRTS` | `scripts/world/camera/CameraRTS.gd` | Overhead camera controls |
| `HUD` | `scripts/ui/HUD.gd` | Tile/build mode buttons, drag select, energy bar, FPS toggle, debug keys |
| `StatisticsWindow` | `scripts/ui/StatisticsWindow.gd` | Modal stats overlay (M-key in RTS): 3 stacked line graphs (AoE+Energy dual-axis, Units, Damage), trailing-window selector (30s/10m/30m), reads `Global.SM.get_stats(my_player_number)` |
| `LineGraph` | `scripts/ui/LineGraph.gd` | Custom `Control` line graph: optional left/right autoscaled axes, grid, legend, polyline+fill via `_draw()` |
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

`JobManager.Type` = CONSTRUCT_BUILDING, REPAIR_BUILDING, TOGGLE_TILE, CONSUME_ZOOMBA, COMBAT_PERSUE, ATTACK. `start_work()` routes:
- `TOGGLE_TILE` → `tile.do_toggle_countdown(self)` (tile owns the callback chain)
- `CONSTRUCT_BUILDING` → `building.start_construction(self)`
- `REPAIR_BUILDING` → `building.start_repair(self)`
- `CONSUME_ZOOMBA` → `_consume_for_tank()` (spawns a TANK at the garage, then removes this zoomba)
- `COMBAT_PERSUE` → never WORKING — `pathing_callback()` diverts to `combat_pathing_callback()` (chase/orbit, see below)
- `ATTACK` → `start_attack()` (no-op in base `Unit`; VIRUS overrides it for the limpet). Personal VIRUS jobs, generated by `Virus.try_generate_offense_job()`, go through the normal pathing flow and DO enter WORKING. STRIKE aerials similarly self-derive a **personal `COMBAT_PERSUE`** job (`Aerial.try_generate_offense_job` → `choose_building_target`) after 1s idle.

### Unit.gd functions

**`idle_callback()`** — Idle loop entry. If `job` non-empty: asserts PATHING, clears path, calls `pathing_callback()`. If empty: picks a random accessible tile (own-AoE preferred for HOME_TERRITORY_UNITS; PATROL+HOLD units restricted to their building's `_aoe_tiles`), avoids backtracking, calls `move(idle_callback)`. Scrammed units (`scram_count > 0`) head toward their MCP instead.

**`pathing_callback()`** — Each pathfinding step: checks scram first (→ IDLE + `idle_callback`), `JobManager.check_job_still_valid` (→ `job_finished()`), reached `path_dest` (→ `start_work()`), `check_pathing_valid()` (→ `abandon_job()`), then moves to next node.

**`check_pathing_valid()`** — Validates remaining path nodes are still LOWERED (else invalidates). If path empty, re-paths from current location to all access tiles of the target, picking the shortest; sets `job["path_dest"]`. Returns false (→ abandon) if unreachable. Handles tiles lowered/raised mid-path, displaced edges, and access tiles changing.

**`start_work()`** — PATHING → WORKING, quick-rotate, zapper on, dispatch by job type (above).

**`job_finished()`** — Job completed/removed: hides zapper, state=IDLE, `JobManager.remove_job(job["id"])` (which calls our `remove_job()`).

**`remove_job()`** — Called by `JobManager.remove_job()`. If WORKING → `_cleanup_working_state()`. Sets IDLE, kills `move_tween` (prevents stale callbacks), clears `job`, calls `idle_callback()` unconditionally.

**`_cleanup_working_state()`** — Shared by `remove_job`/`abandon_job` when WORKING: hides zapper, kills `_rotate_tween`, cancels tile countdown (`cancel_toggle_countdown`), building construction, or a VIRUS limpet (`cancel_attack()`).

**`abandon_job()`** — Cleans working state if WORKING, sets IDLE, kills tween, `JobManager.abandon_job(id)` (job stays in pool), `idle_callback()`.

**`move(callback)`** — Kills previous tween, slerps rotation + moves to `location.pathing_centre`, calls callback. IDLE moves at 2x speed; scram at 0.5x. `move_tween` is a plain var (Tween is RefCounted).

**`scram()`** — `ui_scram` key (C) or auto-triggered when a ZOOMBA takes damage: `scram_count = SCRAM`; if busy, `abandon_job()`. Scrambled units aren't assigned jobs and aren't eligible during `assign_jobs`.

### JobManager.gd

- **`add_job(pnum, type, target, request_assign=null, personal=false, eligible_types=[], patrol_only=false, territory_only=false)`** — `target` is a TileElement/Unit/Building (resolve via `target_tile()`); dedupes identical pnum/type/target jobs (personal jobs exempt). Passing a `request_assign` Unit immediately tries to assign the job to it. `eligible_types`/`patrol_only`/`territory_only` gate which units `assign_jobs` may hand it to. `personal` jobs can't be reassigned — they're erased on abandon.
- **`cancel_job`** — deselect → `remove_job`. **`remove_job(id)`** — permanent deletion; if assigned, calls `unit.remove_job()`. **`abandon_job(id)`** — stays in pool, `abandoned_n`++, timer `min(60, abandoned_n × 11)`, clears `assigned`; personal jobs are erased instead.
- **`assign_jobs()`** (every 1s from GameManager) — two passes: decrement abandon timers, then for each idle unit (skipping AVATAR and `scram_count > 0`) → `assign_nearest_job(unit)` (shortest path length among eligible unassigned jobs for that player).
- **`check_job_still_valid(job)`** — per-type: CONSTRUCT_BUILDING (blueprint present), TOGGLE_TILE (state RAISED/LOWERED + still `selected_by`), REPAIR_BUILDING (damaged), CONSUME_ZOOMBA (constructed GARAGE), COMBAT_PERSUE (target alive; a re-cloaked VIRUS is invalid — same as destroyed), ATTACK (target alive). New job types extend this `match`.
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

`id`, `pnum`, `type`, `target` (TileElement/Unit/Building — not `location`), `assigned` (Unit/null), `personal` (bool), `eligible_types`, `patrol_only`, `territory_only`, `abandoned_by`, `abandoned_n`, `abandoned_timer`. Plus transient `path_dest` set during pathing.

## Economy & production

- **EnergyManager** (server-only): 0.05s tick sums `get_energy()` over CONSTRUCTED `generator`-group buildings (MCP=27 fixed, Generator=Σ `1/gen_count` over its AoE tiles), fills `energy[p]` up to `capacity[p]`; 1s rolling histories give per-second produced/consumed/requested rates and a supply ratio (`_produced/_requested`) used to ration consumers when the store runs dry (there is no `rate_of_change` var — see `get_player_energy()`). `request_energy(pnum, amount)` deducts (returns allocated). `recalculate_capacity()` sums CONSTRUCTED `vat`-group `get_capacity()`. Broadcasts `apply_energy` (unreliable) per player. **Dicts are 1-based** — iterate `range(1, Global.MAX_PLAYERS + 1)`, never `for p in Global.MAX_PLAYERS`.
- **Construction**: BLUEPRINT building's `_process` consumes energy at `CONSTRUCTION_COST / CONSTRUCTION_TIME`; at full → `set_constructed()` (`rpc_constructed` removes the blueprint and reveals the building).
- **Production**: CONSTRUCTED building accumulates `_production_energy` via `request_energy`; at `UNIT_COST` → spawn via `um.rpc("rpc_spawn_unit", uid, type, building_id)`; cooldown from `Config.PRODUCTION_COOLDOWNS`. MCP overrides: AVATAR first, then ZOOMBA up to `zoomba_cap = floor(sqrt(player_aoe_totals[pnum]))`. Garage overrides: issues CONSUME_ZOOMBA jobs instead of spawning directly. Beacon → AERIAL, Nest → VIRUS.
- **Empower**: `BuildingManager.set_empowered_for_player` (one building per player, swap clears the previous), `rpc_set_empowered`, subclasses react in `_empower_changed` (Vat ×1.2 capacity).
- Building HUDs: each building gets its own `SubViewport` + HUD scene (`_setup_hud`), rendered into the `Terminal/Screen` material; terminal positioned at the access tile nearest the MCP (`position_terminal`). Building settings are mirrored to all peers through the snapshot system, so enemy terminals are spyable (`GameManager.refresh_foreign_building_terminals`, 4Hz).

## Combat

- **CombatManager** (server-only): every 0.5s re-scans TANK/AERIAL/AVATAR units; score = `dmg × 10 - health`, must pass range (40) and line-of-sight (raycast that ignores LOWERED/FALLING tiles and self/target; per-pair results are cached and invalidated on any tile/building change). Enemy targeting is **explicit-list only**: a unit attacks players in `orders["enemy"]` — an empty list means it attacks nothing (no "everyone" fallback), and its own team is never included. Aerial roles: "patrol" = PATROL mode (home patrol, 3-tile VIRUS detect), "strike" = STRIKE mode (enemy overfly, 1-tile detect). Detection uncloaks a cloaked VIRUS (`c.uncloak()`); a cloaked VIRUS is never a fire target (`_update_firing` skips it). Kill-VIRUS jobs (`COMBAT_PERSUE`, `patrol_only` + `territory_only`) are executed only by PATROL aerials.
- **Avatar uncloak**: `_scan_avatar` uncloaks cloaked enemy VIRUS within Avatar LoS — 40u in FPS, 10u in RTS (`AVATAR_VIRUS_DETECT_RADIUS_FPS/RTS`), per DESIGN. Radius follows the owner's camera mode: local avatar reads `Global.VM.camera_status`, remote avatars use the mode their client reported via the `camera_mode` command.
- Firing: when weapon aligned (`Unit.is_weapon_aligned()`, slerped in `update_weapon_aim`), bursts of `WEAPON_BURST_DURATION`(0.4) with damage ticks every 0.1s. TANK fires an instant burst; AERIAL applies a projectile delay (`update_projectile_delay`). `combat_fire_event` is bumped server-side and drives client visuals (`_update_combat_visuals`).
- **Damage** via `Config.get_damage(attacker_type, target, mode)`: TANK damages only AERIAL (×6 patrol / ×5 strike). AERIAL damages VIRUS ×5 (patrol) / BUILDING ×2 (strike), plus mode-vs-mode multipliers. `apply_damage(amount, delay, attacker)` on server → health; ≤0 removes unit/building. `SELF_HEALING_UNITS` (ZOOMBA, TANK, AVATAR) heal server-side at `Config.SELF_HEAL_RATE` (10/25/10 HP/s) after 10s out of combat. A damaged ZOOMBA scram(). A CONSTRUCTED building calls for defense: `_call_for_defense(attacker)` queues a `COMBAT_PERSUE` job on the attacker — VIRUS attacker → PATROL aerials (`patrol_only` + `territory_only`), any other (AERIAL) → TANKs (`territory_only`).
- **VIRUS combat**: VIRUS doesn't fire — it generates a **personal `ATTACK` job** (`Virus.try_generate_offense_job`, like Aerial-strike) from its copied Nest orders (`enemy` / `target` / `tank_ratio`). Target = random enemy tank on the `tank_ratio` roll, else `CombatManager.choose_building_target()` (shared with Aerial-strike). An aerial spotting an enemy tank also queues a **pooled** `ATTACK` job (`eligible_types=[VIRUS]`) so a freshly spawned virus can be assigned it before it self-derives (the 1s `_idle_time` guard). On arrival `start_work()` → `start_attack()`: uncloak, attach (`_limpet_target`), `VIRUS_ATTACH_DELAY`(1s) pause, then tank drain at `VIRUS_TANK_DRAIN_DPS`(40) — the limpet **tracks the tank's position** each tick (snaps `location`/`global_position`) — or a building infection channel (`VIRUS_INFECTION_BASE_DURATION` 15s × health-at-attach/150; `_apply_building_effect()` is a stub). Ambient 1.25/s decay pauses while WORKING. Re-cloaks after `VIRUS_RECLOAK_COOLDOWN`(5s) when uncloaked & not attached (spawns uncloaked). Dies when its limpet TANK dies (any cause) or when a building infection completes (self-sacrifice); survives if the building is destroyed mid-channel → re-targets. Multiple VIRUS may limpet one target (personal jobs skip dedup).
- Health bars: `HealthBar3D` for units and buildings. Debug keys in HUD: `ui_damage_building` (P), `ui_damage_unit` (L) deal 40% max health.
- RTS cursor light (`OmniLight3D_RTS`): `ui_debug_light` (F3) toggles a wireframe gizmo (magenta sphere = `omni_range`, white axis = down direction, cyan cross = light origin) built by `OmniLight._build_debug_mesh()`. The light is omnidirectional — OmniLight3D has no cone/`omni_angle` property in this engine.

## Statistics

- **StatisticsManager** (`Global.SM`, server-only): samples every 1s (`TICK_INTERVAL`), appends one record per player to a full history — `stats[pnum]` is an `Array` (newest last) on the server.
- Record fields: `time` (monotonic seconds since engine start — x-axis of the graphs), `aoe_size` (split AoE score from `TileManager.player_aoe_totals`), `energy` {`stored`, `capacity`, `generated`, `used`} (trailing-1s rates from `EnergyManager.get_player_energy()`), `units` {`zoomba`, `tank`, `aerial_strike`, `aerial_patrol`, `virus`}, `damage` {`done`, `received`}.
- Damage hooks: `record_damage_done` (CombatManager at fire time) / `record_damage_received` (Unit/Building/Vat `_apply_damage` at impact time). Debug-key damage (P/L, attacker-less) counts as received only.
- **Sync**: each finalized record is pushed to the owning remote client via `rpc_id(peer, "rpc_receive_stats", p, record)` (`@rpc("authority","call_remote","reliable")`). `Server.player_to_peer` only contains remote clients (peers > 1), so the host's local slot and AI slots are skipped — the server keeps full history for everyone, while a client only gets its own player-number key populated.
- Query: `Global.SM.get_stats(pnum)` → the player's full history `Array`.
- **Statistics window** (`scenes/ui/StatisticsWindow.tscn`, `Global.VM`-gated): toggled by the `ui_stats`/M key in HUD `_input`, only while `Global.game_started` and camera is `OVERHEAD`; ESC and the X button also close it. Full-screen modal (STOP mouse filter + backdrop; HUD swallows game input while open). Reads `Global.SM.get_stats(Global.my_player_number)` (a client only ever has its own key populated) and renders three `LineGraph`s refreshed at 0.5s: AoE+Energy (dual-axis — energy on the left axis, AoE tiles on the right), Units, Damage. Trailing-window buttons select the most recent 30s/10m/30m. `LineGraph` autoscales each axis to a "nice" ceiling (1/2/5 × 10ⁿ) and draws the legend inside the graph.

## Avatar / FPS camera

- `Global.VM.CameraStatus` = OVERHEAD → TO_FPS → FPS → TO_OVERHEAD. Toggle via HUD button or `ui_capture_toggle`; 2s transition tween, mouse captured in FPS. Trauma/shake via `add_trauma`.
- `Avatar` (`scenes/world/units/Avatar.tscn`) = Unit with `FPSBody` (CharacterBody3D + `Rotation_Helper`/`FPSCamera`). WASD + `ui_movement_jump` movement, mouse look, ray for tile selection (jagged beam), `ScreenRay` for interacting with terminal HUDs (`ScreenBody` collision → drives the 2D `TerminalCursor` in the building's SubViewport HUD, propagating hover + click) — only within `TERMINAL_INTERACT_RANGE` (2 × `Cairo.UNIT`) of the building.
- Avatars skip the job system entirely (`idle_callback` no-op; `assign_jobs` skips AVATAR; not in `HOME_TERRITORY_UNITS`). Avatar snapshots are relayed separately (see Snapshot section).
- **The `Avatar` root (a `Unit`) never moves from its spawn tile — only its `FPSBody` (CharacterBody3D) travels the world.** Any system needing the avatar's real position must read the `FPSBody`'s transform (e.g. `avatar.get_node("FPSBody").global_position`), never the root's `global_position`/`location`. This drives combat aim (`CombatManager` aims at the body), snapshot/interpolation (avatar snapshots pack the `FPSBody` transform), and camera transitions.

## Godot 4 conversion patterns

- **Member variables and constants are declared at the top of each script**, grouped under `# --- ... ---` headers (Signals, Types, Constants, State, Nodes/`@onready` refs) — never inline mid-file near their only usage.
- **Tween** is RefCounted, not a Node: `create_tween()`, chained `tween_property/tween_method/tween_callback`, auto-starts. Store in a local/plain var, kill with `tween.kill()` + guard `tween and tween.is_valid()`, never `@onready`.
- **`setget` → set/get blocks** with underscore-backed var (`var _contains_val` backed by `contains`).
- **`@rpc` annotations**: `@rpc("authority", "call_local")` (server call runs everywhere), `@rpc("any_peer", "call_remote")` (client→server, derive caller via `get_remote_sender_id()`), plus `"reliable"`/`"unreliable"`.
- **ImmediateMesh**: `clear_surfaces()` / `surface_begin()` / `surface_add_vertex()` instead of ImmediateGeometry.
- **Materials**: player colour at `res://materials/player/player<N>_material.tres` (1..4, matches `PLAYER_COLORS`). Floor: `res://materials/floor/grid_faces.tres` (lit) + `grid_edges.tres` (unshaded cyan, `use_instance_color`).
- The whole codebase is converted — no Godot 3 syntax remains (this file's old "Remaining patterns" list is resolved).
- `Config.UI_*` accent constants are mirrored by hand in `themes/neon_ui.tres` (Godot themes can't read GDScript constants) — keep the two in sync when changing the palette.

## Gotchas

- `Server.next_player_num` is set by `NetworkManager.start_server()` after LOCAL/AI slots claim numbers — do not hard-code it.
- `rpc_id(1, ...)` targets the server (peer 1 is always the server in ENet).
- `TileManager.apply_toggle` validates `tile.state == RAISED` and LOWERED-with-no-building before toggling. Never call it directly — use `Global.send_command*`.
- `Global.my_player_number` = -1 for a host with no LOCAL slot (spectator); `send_command_me` no-ops and HUD energy reads 0.
- `%` unique-node lookup requires caller `owner`. Dynamically created TileElements miss this → use a stored `pathing_manager` ref (set by `TileManager.set_neighbours`) instead of `%PathingManager`.
- `TileElement` has no `.player` — check `.selected_by` / `.aoe` / `player_owner` on buildings/units.
- Server-only functions called from `_process`/`_physics_process` (which run on all peers) must self-guard.
- `create_tween()` returns RefCounted — local var, `.kill()` + `.is_valid()` guard, no `@onready`.
- Unit/buildings are spawned/removed only via `@rpc("authority","call_local")` RPCs; never add children directly on a client. Sole exception: level-setup MCP placement (`TileManager.apply_loaded_level` → `BuildingManager.place_building`) is deterministic and runs locally on every peer — no RPC involved.
- **Avatar root stays put** — the `Avatar` (Unit) node remains at its spawn tile; only its `FPSBody` child moves. Always read `avatar.get_node("FPSBody").global_position` for where the avatar actually is.
- `EnergyManager`/job/player dicts are 1-based (1..`MAX_PLAYERS`). Loops: `range(1, Global.MAX_PLAYERS + 1)`.

## Lobby flow

- When any REMOTE slot exists, "Start Lobby" loads `scenes/menu/Lobby.tscn`; otherwise straight to `World.tscn`. Remote clients always land on `Lobby.tscn` and wait.
- `Server.accepting_clients` stays false until the host enters the Lobby — clients connecting earlier are disconnected so they see a connection failure instead of silently joining.
- Host starts when `peer_to_player.size()` >= REMOTE slot count **and** every connected peer has confirmed it is inside the Lobby scene (`rpc_client_lobby_ready`; a 10s soft-lock fallback force-starts). Then host `rpc("rpc_start_game")` + everyone loads World.
- AI controllers skip actions while `not Global.game_started` or `Global.TM` is null (lobby).
- Back button: `Global.network_manager.stop()` + `queue_free()` + null it, then MainMenu.
- `NetworkManager.stop()` closes the client ENet peer too (`multiplayer.multiplayer_peer.close()`), not just the server peer.

## Floor (decorative only, no multiplayer sync)

- `scenes/world/floor/Floor.tscn` — 50×50 visual floor with animated mountains (vertex displacement via per-instance custom data), monuments with pulsing beacon, no collision, no RPCs. Timer morphs mountains via `create_tween()` → `tween_method()` → `update_mountain(idx, color)`.

## UI rules

- One LOCAL slot max — selecting LOCAL on a second slot snaps the first back to Remote (`MainMenu._on_slot_selected`). Zero LOCAL slots = Spectator mode.
- HUD modes: RAISE/LOWER (tile toggle, drag-select via `begin_drag`/`should_toggle`) and building placement (GEN/VAT/GARAGE/BEACON/NEST) → `TileElement` click sends `place_blueprint`. Building HUDs (SubViewports) send all building commands via `send_command_me` — commands carry `building_id`, never a node reference.

## Running

- Godot 4.7 binary: `C:\Users\timbo\Documents\Godot_v4.7-stable_win64.exe` (also `Godot_v3.6.2-stable_win64.exe` beside it for older projects). Use it for headless checks, e.g. `& "C:\Users\timbo\Documents\Godot_v4.7-stable_win64.exe" --headless --path <project> --quit-after 90` to catch parse/script errors.
- The user can run interactive tests inside the engine themselves (launch the game, join/multiplayer, place buildings, etc.) — when verifying a fix, prefer asking the user to test interactively rather than relying on headless reproduction.
- Pass `--client` as CLI arg to launch a second instance on the Connect tab (`MainMenu` checks `OS.get_cmdline_args()`).
- Default config for instances: "Run Instances" in the Godot editor with `--client` on the second.
