# NeonFeverDreamMP — AGENTS.md

## Stack

- **Godot 4.7**, Jolt Physics, D3D12 renderer, Forward Plus
- Entrypoint: `scenes/menu/MainMenu.tscn`
- `DESIGN.md` is the game design doc (unit/building tables, combat matrix, economy intent) — gameplay code comments cite it as "per DESIGN".
- Autoloads (only two, see `project.godot`): `autoload/Global.gd` (holds `network_manager`, `game_config`, `my_player_number`, the `LEVELS` registry + `level` var, helpers `set_level`/`level_name`/`stats_window_open`, and the central teardown `leave_game()`) and `autoload/Config.gd` (all balance dicts, combat/empower/virus/rally consts + `get_damage()`).
- `Global.level` is the chosen entry of `Global.LEVELS` (`levels/*.gd`: duel, basin, canyons, skirmish_01) — tile IDs, MCP positions, LOWERED/IMMUTABLE/INVISIBLE sets, seed. Default: `duel`.
- No tests, no lint, no typecheck config.

## World scene layout

`scenes/world/World.tscn` — managers are all siblings under the root, most marked `unique_name_in_owner`:

```
World
├── WorldEnvironment    rendering environment
├── Sun / SunScene      directional lights
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
├── Floor               decorative 50×50 grid + mountains (see Floor)
├── HUD                 CanvasLayer, group "hud"
├── StatisticsWindow    CanvasLayer (layer 50), group "statistics_window"; modal stats graphs (M-key in RTS)
├── VictoryBanner       CanvasLayer, group "victory_banner"; "<NAME> WINS!" (see Game over)
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
- `NetworkManager` is **not** in any scene — instantiated at runtime by `MainMenu` and added to root with an **explicit name `"NetworkManager"`** (`nm.name = "NetworkManager"`). This is required: the server routes RPCs (e.g. `rpc_set_my_player_number`) to `/root/NetworkManager` on every peer, and a `.new()` default name ("Node", possibly auto-renamed to a random `@Node@<id>`) silently drops them.
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
- `send_command_me` uses `Global.my_player_number` and **no-ops when it's -1** (spectator / host with no LOCAL slot). Safe for host (set by `NetworkManager.start_server()` at LOCAL-slot creation) and remote (set by `NetworkManager.rpc_set_my_player_number` RPC).
- `send_command(pnum, ...)` is for AI controllers that know their own player number (`AIController` uses it for `toggle_tile`).
- The remote client's `pnum` is never trusted — the server always derives it from `peer_to_player`.
- Command handlers on `Server` are named `_cmd_<command>` and auto-dispatched via `callv` + `has_method`; `handle_command` validates arg count against the method signature. The `_cmd_` prefix is the allowlist. Adding a command = add `_cmd_<name>(player_number, ...)` to `Server.gd`, call it via `Global.send_command_me("<name>", [...])`.
- Full command surface (see `Server.gd`): `toggle_tile`, `place_blueprint`, `remove_building`, `toggle_production`, `set_garage_ratio`, `set_beacon_ratio`, `set_nest_ratio`, `set_enemy_targets`, `set_building_targets`, `set_patrol_stance`, `empower`, `clear_empower`, `rally` (FPS-only, server-enforced 15s cooldown — see Rally); plus `camera_mode` (clients report their camera state — drives the per-player avatar VIRUS-detect radius and rally legality) and `debug_damage_unit`/`debug_damage_building` (server-authoritative debug keys). Callers: `TileElement` mouse handlers, the building HUDs, `VideoManager` (`camera_mode`), `AIController`, HUD debug keys.

### Server-only guard pattern

All server-side simulation (`_process`/`_physics_process` in `EnergyManager`, `CombatManager`, `StatisticsManager`, `Building`, `Unit`, `GameManager`) guards the top:

```gdscript
func _process(delta):
	if not multiplayer.is_server():
		return
	...
```

Spawn/remove never run directly on clients — they're `@rpc("authority", "call_local")` (e.g. `UnitManager.rpc_spawn_unit`, `rpc_remove_unit`, `BuildingManager.rpc_broadcast_place_blueprint`, `rpc_remove_building`, `Building.rpc_constructed`), called via `rpc(...)` so the server executes locally and mirrors to peers. `TileManager._physics_process` runs on all peers — anything server-only called from it must self-guard.

### Snapshot / interpolation (`GameManager`)

- Server packs all units+buildings into one `PackedFloat32Array` every 0.05s (`SNAPSHOT_INTERVAL`), split into MTU-safe chunks (256 floats = 1024 B, `SNAPSHOT_CHUNK_FLOATS`) and sent as `rpc("rpc_apply_snapshot_chunk", seq, chunk_idx, total, chunk)` unreliable; the client reassembles by seq in `_chunk_buffer` (`CHUNK_BUFFER_MAX` caps partials; a completed seq drops older stragglers) then parses via `_parse_snapshot`. A lost chunk costs only that snapshot — same as ENet fragmentation, minus the loss multiplier of one giant packet. Each entity = `SLOT_COUNT`(13) float32s (buildings use slot 10 for the VIRUS infection attacker bitmask, slot 11 for pooled channel progress and slot 12 for the longest remaining infection duration — driving the infection status bars; AERIAL units use slot 10 for lifetime-remaining so clients can draw the lifetime bar — the client's `_lifetime_timer` never advances).
- Unit slots: pos x/y/z, rot.y, state, health, type-specific extras (ZOOMBA: zapper visible + target y; TANK/AERIAL/VIRUS: slot 7 = rallied flag — drives the rally marker, see Rally; AERIAL: mode; VIRUS: cloaked), `combat_target` (0=none, +unit id, -building id), `combat_fire_event` (visual trigger). AVATAR packs its `FPSBody` transform, not the root.
- Clients buffer up to `MAX_SNAPSHOT_BUFFER`(4) and interpolate with `INTERPOLATION_DELAY`(0.075) render time.
- Avatars: each client sends `rpc_receive_avatar_snapshot` at 20Hz **only while `Global.VM.camera_status == FPS`**; the server interpolates per-pnum avatar snapshots for the other peers. Clients skip their own avatar in `_apply_interpolated`/`_apply_snapshot_entities` to avoid control cycles.
- `_apply_unit` asserts type match and is client-only — the server never mutates client state.

## Key classes

| Class | File | Role |
|---|---|---|
| `Global` | `autoload/Global.gd` | Singleton: `network_manager`, `my_player_number`, `LEVELS` registry + `level` var, command relay, `MAX_PLAYERS=4`, `set_level`/`level_name`/`stats_window_open`/`leave_game` |
| `Config` | `autoload/Config.gd` | Static balance dicts (`BUILDING_AOE`, `BUILDING_MAX_HP`, `BUILDING_ENERGY_CAPACITY`, `CONSTRUCTION_COST`, `UNIT_COST`, `PRODUCTION_COOLDOWNS`, `UNIT_SPEED`, `UNIT_MAX_HP`, `UNIT_LIFETIME`, `HOME_TERRITORY_UNITS`, `SELF_HEALING_UNITS`, `PLAYER_COLORS`/`PLAYER_NAMES`) + combat/empower/virus/rally consts (`AERIAL_*`, `EMPOWER_*`, `VIRUS_*`, `RALLY_*`, `CATCHUP_*`), `player_accent()`/`player_unit_material()`, `get_damage()` |
| `NetworkManager` | `scripts/core/network/NetworkManager.gd` | Creates `Server` + local AI controllers, or ENet client; player number = slot index + 1 (LOCAL → `my_player_number`, AI → `AIController`, REMOTE → reserved in `server.remote_slot_pnums`); `rpc_set_my_player_number` RPC |
| `Server` | `scripts/core/network/Server.gd` | ENet server, `peer_to_player`/`player_to_peer`, `remote_slot_pnums` pool (remotes draw from it in slot order; freed on disconnect), `_cmd_*` dispatch |
| `TileManager` | `scripts/world/tiles/TileManager.gd` | Cairo pentagon grid gen, `State` enum, `apply_toggle`, `recompute_aoe` (+`player_aoe_totals`/`player_aoe_rings`/`gen_count`), MCP-distance gradient (`ensure_mcp_distances`/`mcp_dist`), `remove_tile_from_pathing`, tile selection broadcast, monorail RPC forwarding |
| `TileElement` | `scripts/world/tiles/TileElement.gd` | One tile: state transitions, neighbours, `aoe`/`selected_by`, MultiMesh visuals, emission priority system, `_working_unit_dict` countdown chain, mouse input → `send_command_me` |
| `PathingManager` | `scripts/world/tiles/PathingManager.gd` | AStar3D, `connect_tiles`/`disconnect_tile`, `pathfind`/`distance`, generation-bumped path cache, debug renderer, monorail ref |
| `MonorailMultimesh` | `scripts/world/tiles/MonorailMultimesh.gd` | Monorail rail meshes + caps between tiles (tweened connect/disconnect), own `StaticBody3D` collision body; edges/caps mirrored to clients via `TileManager.rpc_monorail_*` |
| `GameConfig` | `scripts/core/game/GameConfig.gd` | Resource: `player_count`, `port`, `server_ip`, `slots` array (LOCAL/REMOTE/AI/CLOSED) |
| `GameManager` | `scripts/core/game/GameManager.gd` | Snapshots/interpolation, 1s job tick (`Global.JM.assign_jobs()` + each building `check_work()` + catch-up `_tick_desperation`), avatar relay, game over (`on_player_eliminated` → `rpc_game_over` → VictoryBanner → stats, see Game over) |
| `EnergyManager` | `scripts/core/game/EnergyManager.gd` | Server-only energy sim (see Economy) |
| `CombatManager` | `scripts/core/game/CombatManager.gd` | Server-only target scan + firing, VIRUS uncloak (aerial/avatar detection), shared `choose_building_target` (see Combat) |
| `StatisticsManager` | `scripts/core/game/StatisticsManager.gd` | Server-only 1s stats sampler; per-player history (`aoe_size`, energy, unit counts, damage done/received); `rpc_receive_stats` pushes each finalized record to the owning client (see Statistics) |
| `AIController` | `scripts/core/ai/AIController.gd` | Random `toggle_tile` on a timer via `send_command(player_number, ...)` |
| `BuildingManager` | `scripts/world/buildings/BuildingManager.gd` | `Type` enum (MCP_1..4, GEN, VAT, GARAGE, BEACON, NEST), blueprints, building dict, `place_blueprint`/`place_building`/`rpc_remove_building`, empower tracking, remove-mode hover ghost, `recompute_aoe` hookups |
| `Building` | `scripts/world/buildings/Building.gd` | Base: states BLUEPRINT→UNDER_CONSTRUCTION→CONSTRUCTED, `player_owner`, `get_aoe_radius()`, `check_work()` (adds REPAIR_BUILDING jobs while production is enabled), construction/production via energy, `apply_damage`, repair, terminal positioning, per-building HUD SubViewport, settings inheritance from highest-id sibling (`rpc_inherit_settings`), infection status bars (`_bar_channel`/`_bar_remaining`) + attacker-coloured torus ring |
| `MCP` | `scripts/world/buildings/MCP.gd` | Main Control Point: produces AVATAR first then ZOOMBA up to `zoomba_cap`; counts as generator+vat; empower buffs (spawn rate ×0.8 cooldown, damage reduction ×0.75, zoomba move/work ×1.2); infected MCP halts ZOOMBA production but still respawns the Avatar (the cure). Cooldown: MCP_1 is 2.0s (`# TESTING`), MCP_2..4 are 10s |
| `Generator` | `scripts/world/buildings/Generator.gd` | Energy output = Σ `1/gen_count` over its AoE tiles (each tile's output split N ways); hover shows catchment; empowered → +1 influence radius (`_aoe_tiles_extra` ring) |
| `Vat` | `scripts/world/buildings/Vat.gd` | Capacity = 1000 + 100/adjacent same-owner Vat, ×1.5 if empowered; empowered vat also discounts construction/production drains ×0.9 (type-wide via `Global.BM.empowered_type`, scales completion thresholds — same build time, 10% less energy); liquid-level visual; shared health pool + pool graph (`_join_pool`/`_merge_pools`/master re-election) |
| `Garage` | `scripts/world/buildings/Garage.gd` | Creates CONSUME_ZOOMBA jobs (zoomba → TANK conversion), `zoomba_tank_ratio`, `player_tank_target()` (pooled ratio across all of the player's garages × MCP cap, clamped cap − 1), patrol orders; empowered → all player TANKs fire interval ×0.8 vs AERIAL |
| `Beacon` | `scripts/world/buildings/Beacon.gd` | Produces AERIAL, patrol/strike orders, `patrol_strike_ratio`, patrol stance; empowered → all player AERIALs gain +30s lifetime (`Aerial._get_lifetime()`) |
| `Nest` | `scripts/world/buildings/Nest.gd` | Produces VIRUS, attack orders, `_virus_tank_building_ratio`; empowered → all player VIRUS +30% speed, limpeted TANKs immobilized |
| `Zapper` | `scripts/world/buildings/Zapper.gd` | Laser beam visual (ImmediateMesh + RayCast3D) |
| `DestructionFX` | `scripts/world/fx/DestructionFX.gd` | One-shot destruction debris (buildings + units): spawns the victim's own `MeshInstance3D`s as `RigidBody3D` chunks (blasted out from the centre, own collision layer vs tiles only; a dying building is dropped out of physics first so depenetration can't eject the chunks), white ember particle burst + `Global.VM.add_trauma` (buildings only); chunks freeze and sink 18u (6u for units) below their resting spot before `queue_free`. `spawn(building)` / `spawn_unit(unit)` (unit scale, no burst; Avatar FX centres on the FPSBody). Spawned locally by every peer in `rpc_remove_building` / `rpc_remove_unit` (call_local) — cosmetic, no sync. Cloaked VIRUS deaths skip FX. TODOs: MCP_2's CSGCombiner top sections and MultiMeshInstance3D parts (AERIAL blades, VIRUS rings) bake no chunks yet |
| `Blueprints` | `scripts/world/buildings/Blueprints.gd` | Ghost preview, material assignment, collision enable, material capture/restore (remove-mode ghost) |
| `UnitManager` | `scripts/world/units/UnitManager.gd` | `Type` enum (NONE, AVATAR, ZOOMBA, TANK, AERIAL, VIRUS), `_spawn_unit` (via `rpc_spawn_unit`), `rpc_remove_unit`, `displace_units_on_tile`, `unit_count` |
| `Unit` | `scripts/world/units/Unit.gd` | Base unit: IDLE/PATHING/WORKING, job lifecycle, health, self-heal, scram (MCP-gradient walk-home), combat aim/fire-event visuals, `apply_damage`; `work_speed_multiplier()` (empowered-MCP zoomba buff); `rallied` flag + marker disc (see Rally) |
| `Zoomba` | `scripts/world/units/Zoomba.gd` | Basic unit, player-colour material |
| `Tank` | `scripts/world/units/Tank.gd` | Anti-air unit (only damages AERIAL); `_attached_virus` tracking + `virus_immobilized()` (Nest empower buff) |
| `Aerial` | `scripts/world/units/Aerial.gd` | Flying, patrol/strike modes, projectile delay, 120s lifetime (auto-removed; +30s while a Beacon is empowered via `_get_lifetime()`); STRIKE self-generates personal COMBAT_PERSUE jobs |
| `Virus` | `scripts/world/units/Virus.gd` | Cloaked limpet unit: personal `ATTACK` jobs from Nest orders, spawns uncloaked → re-cloaks after 5s, drains TANKs (dies with the tank) or pools a building-infection channel (per-building `_channels`; completing virus self-sacrifices; effects per DESIGN, see VIRUS combat) |
| `Avatar` | `scripts/world/units/Avatar.gd` | FPS character: `FPSBody` (CharacterBody3D + FPSCamera), ignores job system, screen-cursor terminal clicks (`TerminalCursor`), rally anchor + empower beam |
| `JobManager` | `scripts/world/units/JobManager.gd` | Job pool + worker-centric assignment, abandon timers, `personal` jobs, job-event notifications, rally squad management (`start_rally`/`cancel_player_rally`/`rally_avatar_tile`) |
| `VideoManager` | `scripts/world/camera/VideoManager.gd` | CameraStatus (OVERHEAD/TO_FPS/FPS/TO_OVERHEAD), 2s transition tween, mouse capture, trauma shake (`add_trauma`, distance falloff), `fps_locked` (game over), `force_leave_fps`/`exit_fps_immediate`, `jump_to` (notification click-through) |
| `CameraRTS` | `scripts/world/camera/CameraRTS.gd` | Overhead camera controls: edge/right-drag pan, wheel zoom, Q/E rotate, pitch via vertical drag (T/G `ui_pitch_*` bindings are dead). MIT-licensed CameraController (Maujoe) |
| `HUD` | `scripts/ui/HUD.gd` | Tile/build/remove mode buttons, drag select, energy bar, FPS toggle, debug keys, `ui_rally` (R, FPS-only) + cooldown ring, RTS hover tooltip for own CONSTRUCTED buildings |
| `StatisticsWindow` | `scripts/ui/StatisticsWindow.gd` | Modal stats overlay (M-key in RTS): 3 stacked line graphs (AoE+Energy dual-axis, Units, Damage), trailing-window selector (30s/10m/30m), reads `Global.SM.get_stats(my_player_number)` |
| `LineGraph` | `scripts/ui/LineGraph.gd` | Custom `Control` line graph: optional left/right autoscaled axes, grid, legend, polyline+fill via `_draw()` |
| `NotificationManager` | `scripts/ui/NotificationManager.gd` | Job-event on-screen notifications (`rpc_add_job_notification`; combat jobs skipped, `MAX_VISIBLE` 7); clicking a chip → `Global.VM.jump_to` |
| `HealthBar3D` | `scripts/ui/HealthBar3D.gd` | Billboard health bars for units + buildings |
| `TerminalHUD` | `scripts/ui/TerminalHUD.gd` | Base class for all six building HUDs: CRT shader, cursor wiring (`drive_cursor_at_uv`/`uv_from_collision`), enemy-target theming, owner-colour tint, empower button + `_set_empower_indicator` states, spy/tooltip mode (see Economy → Building HUDs) |
| `VictoryBanner` | `scripts/ui/VictoryBanner.gd` | CanvasLayer, group "victory_banner"; "<NAME> WINS!" in the winner's player colour; shown by `GameManager.rpc_game_over` (see Game over) |

## Level system

- Levels are GDScripts in `levels/*.gd` registered in `Global.LEVELS` (menu key → preload). `Global.level` is a **var** — every peer must set it to the same level **before World loads** (the chosen map syncs via `GameConfig.level_name` → `Lobby.rpc_start_game(level_name)`; the no-remote host path sets it in `MainMenu._start_host`; unknown keys fall back to `Global.DEFAULT_LEVEL`). Desynced levels = desynced tile IDs.
- Each level defines `NAME` (menu label), `MAX_PLAYERS` (caps the main menu player-count selector; matches `MCP_ARRAY` size — duel/basin/canyons = 2, skirmish_01 = 3), `SEED`, `TRIPLETS_X`/`TRIPLETS_Z`/`BORDER_TRIPLETS` (arena size), `MCP_ARRAY` (tile ids; index+1 = player number), `LOWERED`, `IMMUTABLE`, `INVISIBLE`, `MOUNTAINS` (mountain-column count for the floor shader), and `STARTING_BUILDINGS` (optional array of `{tile, pnum, type}` placed as constructed buildings during level setup — canyons gives each player a starting GEN). `Global.level_max_players(key)`/`Global.level_label(key)` surface these to the menu (dropdown text like "Duel (2 player)", "Skirmish (2-3 player)").
- **Non-square maps**: `TRIPLETS_X` drives the world x extent (the x cluster loop) and `TRIPLETS_Z` the world z extent (the z loop) — the cluster pattern is rotated ~15° against the world axes, so each loop also leaks a small offset on the other axis. The playable area is the world rectangle `[0, TRIPLETS_X*3*UNIT*2] × [0, TRIPLETS_Z*3*UNIT*2]` with a ragged border (see `_check_disabled`). Equal values reproduce the old square arena.
- `TileManager._populate()` marks tiles IMMUTABLE/INVISIBLE as `DISABLED_RAISED` (`disabled`/`invisible` groups) vs `interactive`. `_set_neighbours()` gives every pathing-capable tile (interactive + obsidian floors) its `pathing_centre` and AStar point — obsidian floors MUST get theirs here, before `MonorailMultimesh.setup`/`cap_setup` bake rail/cap transforms (they used to get it later, so rails over floors rendered at the world origin). `_apply_loaded_level()` places each MCP via `BuildingManager.place_building(...)`, lowers the LOWERED tiles (connecting obsidian floors to their lowered neighbours), places `STARTING_BUILDINGS`, then `recompute_aoe()`.
- **Obsidian floors**: a tile in both IMMUTABLE and LOWERED is a permanent walkable corridor — state `DISABLED_LOWERED`. `walkable()` (LOWERED or DISABLED_LOWERED) gates navigation; interactivity gates (`apply_toggle`, `_can_place_here`, `can_toggle_tile`, `add_to_aoe`) check `state` alone, so floors are automatically non-toggleable, non-buildable and AoE-excluded. The floor visual updates its disabled-MultiMesh instance (`disabled_mm`/`disabled_mm_id`).
- Tile IDs are the deterministic generation order — editing the level means editing these ID arrays.
- **Authoring tools**: headless dump (`godot --headless --path . -- --dump-tiles --level=<key>`) writes every tile's id, anchor position, pathing centre, state, flags and neighbour ids to stdout + `user://level_dump.txt`, then quits. In-game, `ui_debug_tile` (F4) prints the tile under the cursor and copies its id to the clipboard. Beware: the dump's x/z are tile **anchors**; the border check (`_check_disabled`) tests a rotated corner of each tile, so anchors can extend ~33 units past the world rectangle and edge tiles can generate `DISABLED_RAISED` even when their anchor is inside — don't list such tiles in LOWERED or they become obsidian floors. Level preview capture: `godot --path . -- --capture-preview --level=<key>` (**not headless** — the headless display server renders nothing) loads World with the level, frames the arena with a square 1024×1024 top-down ortho camera, writes `res://previews/<key>.png` and quits; the main-menu preview box (`PreviewPanel`, `scripts/ui/MainMenu.gd`) loads these per selected map — regenerating a preview after a level edit is just re-running the flag. Both authoring runs bind a random free high port (20000–60000) instead of the default; `PreviewCapture` waits on the `TileManager.level_loaded` signal (90-frame watchdog) and hides HUD/loading/stats groups while capturing.

## Tile system

- `TileManager.State` = RAISED, FALLING, LOWERED, RISING, DISABLED_RAISED, DISABLED_LOWERED. Tiles are `StaticBody3D` + one MultiMesh instance (`enabled_tiles_to_multimesh`), 5 pentagon neighbours, `pathing_centre` for pathfinding, `location` for units/buildings. Navigation checks use `tile.walkable()` (LOWERED or DISABLED_LOWERED), not raw state comparisons.
- `apply_toggle(pnum, tile_id)` (server only, **never called directly** — go through `send_command`) toggles a player's `selected_by` claim. RAISED/LOWERED only; LOWERED+has building is rejected; returns false on deselect → `JobManager.cancel_job`. Selection broadcast via `rpc_broadcast_tile_selection`. Tile commit fires dust/plume particle bursts + `Global.VM.add_trauma`; clients sync the resulting state and terminal positions via `_sync_state_after_toggle`/`_reposition_terminals_after_toggle`.
- Access tiles: `get_access_tiles(require_aoe=0)` — LOWERED neighbours with no building, optionally filtered to own AoE. Used everywhere (wandering, pathing targets, terminal placement, displacement). Allocation-free check: `has_access(require_aoe=0)`.
- AoE: `recompute_aoe()` BFS from each building's `get_aoe_radius()`, deterministic on all peers. Fills `tile.aoe`, `tile.gen_count` (for GEN), `player_aoe_totals` (split shares), `player_aoe_rings`, then pokes generators/vats + `EnergyManager.recalculate_capacity()` and un-selects tiles no longer under AoE. Re-run after building place/remove.
- **MCP-distance gradient**: `TileManager.ensure_mcp_distances()` fills each tile's `mcp_dist` (tile-graph distance from the owning player's MCP), invalidated on pathing changes (`invalidate_mcp_dist`, bumped by the PathingManager path cache). Drives scram + home recovery and home-territory wandering (see Job system).

### Per-instance visual data (MultiMesh)

Three independent channels on each tile instance:

| Channel | Written by | Read by | Purpose |
|---|---|---|---|
| `INSTANCE_CUSTOM.rgba` | `set_tile_mm_selecting_mask` | `aluminium.tres` vertex→`selecting_mask` | Band stripes — player AoE claims (r=g=p1 etc.) |
| `COLOR.rgb` | `set_tile_mm_color` | `grid_edges.tres` fragment → `ALBEDO` | Edge color — hover indicator |
| `COLOR.a` | `set_tile_mm_emission` | `aluminium.tres` fragment → `EMISSION`+`EMISSION_ENERGY` | White glow intensity |

`set_tile_mm_color` preserves `a`, `set_tile_mm_emission` preserves `rgb`. On top sits an **emission priority system**: `TileElement.EmissionEffect` (GENERATOR_CATCHMENT > TILE_SELECTED > TILE_HOVER > PULSE_ANIMATION) with `request_emission`/`release_emission` writing the active effect into COLOR.a; `_apply_emission` skips while the toggle tween/countdown tweens run. `PulseEffect` (node under `TileManager.tscn`) is the PULSE_ANIMATION source — a per-player timer flashing the player's AoE rings in their colour.

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
  ┌─────────┐   assign_job()   ┌─────────┐   _start_work()   ┌─────────┐
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

`JobManager.Type` = CONSTRUCT_BUILDING, REPAIR_BUILDING, TOGGLE_TILE, CONSUME_ZOOMBA, COMBAT_PERSUE, ATTACK. `_start_work()` routes:
- `TOGGLE_TILE` → `tile.do_toggle_countdown(self)` (tile owns the callback chain)
- `CONSTRUCT_BUILDING` → `building.start_construction(self)`
- `REPAIR_BUILDING` → `building.start_repair(self)`
- `CONSUME_ZOOMBA` → `_consume_for_tank()` (spawns a TANK at the garage, then removes this zoomba)
- `COMBAT_PERSUE` → never WORKING — `_pathing_callback()` diverts to `_combat_pathing_callback()` (chase/orbit, see below). Rallied squad members follow their avatar through the same personal-COMBAT_PERSUE flow (see Rally).
- `ATTACK` → `start_attack()` (no-op in base `Unit`; VIRUS overrides it for the limpet). Personal VIRUS jobs, generated by `Virus.try_generate_offense_job()`, go through the normal pathing flow and DO enter WORKING. STRIKE aerials similarly self-derive a **personal `COMBAT_PERSUE`** job (`Aerial.try_generate_offense_job` → `choose_building_target`) after 1s idle.

### Unit.gd functions

**`idle_callback()`** — Idle loop entry. If `job` non-empty: asserts PATHING, clears path, calls `_pathing_callback()`. If empty: picks a random accessible tile (own-AoE preferred for HOME_TERRITORY_UNITS; PATROL+HOLD units restricted to their building's `_aoe_tiles`), avoids backtracking, calls `_move(idle_callback)`. Scrammed units (`scram_count > 0`) and home-territory units left idle outside their AoE (e.g. a disbanded rally) walk the MCP-distance gradient back toward their MCP instead (`_gradient_home_destinations`).

**`_pathing_callback()`** — Each pathfinding step: checks scram first (→ IDLE + `idle_callback`), `JobManager.check_job_still_valid` (→ `job_finished()`), reached `path_dest` (→ `_start_work()`), `_check_pathing_valid()` (→ `abandon_job()`), then moves to next node.

**`_check_pathing_valid()`** — Validates remaining path nodes are still LOWERED (else invalidates). If path empty, re-paths from current location to all access tiles of the target, picking the shortest; sets `job["path_dest"]`. Returns false (→ abandon) if unreachable. Handles tiles lowered/raised mid-path, displaced edges, and access tiles changing. A moving unit target (VIRUS ATTACK → TANK) also re-paths whenever its planned `path_dest` is no longer adjacent to the target's current tile — the virus chases the tank instead of walking to where it was and teleport-latching on arrival (the arrival check in `_pathing_callback` enforces adjacency before `_start_work`).

**`_start_work()`** — PATHING → WORKING, quick-rotate, zapper on, dispatch by job type (above).

**`job_finished()`** — Job completed/removed: hides zapper, state=IDLE, `JobManager.remove_job(job["id"])` (which calls our `remove_job()`).

**`remove_job()`** — Called by `JobManager.remove_job()`. If WORKING → `_cleanup_working_state()`. Sets IDLE, kills `move_tween` (prevents stale callbacks), clears `job`, calls `idle_callback()` unconditionally.

**`_cleanup_working_state()`** — Shared by `remove_job`/`abandon_job` when WORKING: hides zapper, kills `_rotate_tween`, cancels tile countdown (`cancel_toggle_countdown`), building construction, or a VIRUS limpet (`cancel_attack()`).

**`abandon_job()`** — Cleans working state if WORKING, sets IDLE, kills tween, `JobManager.abandon_job(id)` (job stays in pool), `idle_callback()`.

**`_move(callback)`** — Kills previous tween, slerps rotation + moves to `location.pathing_centre`, calls callback. IDLE moves at half speed (time ×2 — slow wandering); scram at time ×0.75 (≈1.33x speed). `move_tween` is a plain var (Tween is RefCounted). VIRUS/AERIAL hops land at a random offset within `MOVE_OFFSET_RADIUS` of the pathing centre; zoomba IDLE moves rotate-then-walk; a virus-immobilized TANK holds position.

**`scram()`** — `ui_scram` key (C) or auto-triggered when a ZOOMBA takes damage: `scram_count = SCRAM`; if busy, `abandon_job()`. Scrambled units aren't assigned jobs and aren't eligible during `assign_jobs`.

### JobManager.gd

- **`add_job(pnum, type, target, request_assign=null, personal=false, eligible_types=[], patrol_only=false, territory_only=false)`** — `target` is a TileElement/Unit/Building (resolve via `target_tile()`); dedupes identical pnum/type/target jobs (personal jobs exempt). Passing a `request_assign` Unit immediately tries to assign the job to it. `eligible_types`/`patrol_only`/`territory_only` gate which units `assign_jobs` may hand it to. `personal` jobs can't be reassigned — they're erased on abandon.
- **`cancel_job`** — deselect → `remove_job`. **`remove_job(id)`** — permanent deletion; if assigned, calls `unit.remove_job()`. **`abandon_job(id)`** — stays in pool, `abandoned_n`++, timer `min(60, abandoned_n × 11)`, clears `assigned`; personal jobs are erased instead.
- **`assign_jobs()`** (every 1s from GameManager) — three passes: prune unassigned jobs whose targets died (`check_job_still_valid`), decrement abandon timers, then for each idle unit (skipping AVATAR and `scram_count > 0`) → `_assign_nearest_job(unit, job_list)` (shortest path length among eligible unassigned jobs for that player; the job list is snapshotted once per pass, and candidates are sorted by euclidean distance so A* queries stop once the straight-line lower bound (`PATH_EDGE_EUCLID_BOUND`) exceeds the best path found).
- **`check_job_still_valid(job)`** — per-type: CONSTRUCT_BUILDING (blueprint present), TOGGLE_TILE (state RAISED/LOWERED + still `selected_by`), REPAIR_BUILDING (damaged), CONSUME_ZOOMBA (constructed GARAGE), COMBAT_PERSUE (target alive; a re-cloaked VIRUS is invalid — same as destroyed), ATTACK (target alive). New job types extend this `match`.
- **`_notify_job_event`** — server-side job add/assign/abandon/finish → `NotificationManager.rpc_add_job_notification`. Combat jobs (`COMBAT_PERSUE`, `ATTACK`) are skipped — no notification spam.

### TileElement.gd (tile-side job support)

- **`do_toggle_countdown(z)`** — server-only. Adds entry to `_working_unit_dict[pnum]` with unit/job and a 2s countdown tween → `_begin_toggle`. RPC mode 0 = visual countdown.
- **`cancel_toggle_countdown(pnum)`** — server-only. Removes entry, kills its tween, RPC mode 1.
- **`_cancel_other_workers(except_pnum)`** — `_begin_toggle` kills all other workers' countdowns, calls `job_finished()` on their units, RPC mode 1 each.
- **`_begin_toggle()`** — server-only. First countdown fires: if tile state changed during countdown → `job_finished()` all workers (abort). Else cancel others, transition RAISED→FALLING / LOWERED→RISING, clear `selected_by`, broadcast, second tween (`fall_time + thunk_time`) → `_done_toggle`.
- **`_done_toggle()`** — server-only. Completes state change (set_lowered / RAISED + position reset). For each worker whose job is still assigned to its unit → `JobManager.remove_job`. Clears `_working_unit_dict`.

Two tweens per tile: `_countdown_tweens` (server-only per-player countdown → _begin_toggle) and `toggle_tween` (synced visual, created by `rpc_toggle_animation` modes 0/2; `_apply_emission` skips while it runs).

### Job finish vs abandon vs cancel

| Outcome | Who triggers | Job lifecycle | Unit lifecycle | Tile lifecycle |
|---|---|---|---|---|
| **Finish** | Tile animation → `_done_toggle` → `job_finished()` | Removed (`remove_job`) | → IDLE → `idle_callback` | State change completed, dict cleared |
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

- **EnergyManager** (server-only): 0.05s tick sums `get_energy()` over CONSTRUCTED `generator`-group buildings (MCP=27 fixed, Generator=Σ `1/gen_count` over its AoE tiles), fills `energy[p]` up to `capacity[p]`; 1s rolling histories give per-second produced/consumed/requested rates and a supply ratio (`_produced/_requested`) used to ration consumers when the store runs dry (there is no `rate_of_change` var — see `get_player_energy()`). `request_energy(pnum, amount)` deducts (returns allocated). `recalculate_capacity()` sums CONSTRUCTED `vat`-group `get_capacity()`. Broadcasts `rpc_apply_energy` (unreliable) once per tick — all players in one `PackedFloat64Array`. **Dicts are 1-based** — iterate `range(1, Global.MAX_PLAYERS + 1)`, never `for p in Global.MAX_PLAYERS`.
- **Catch-up mechanics (currently disabled)**: Underdog Grit (zoomba work speed, `GameManager.underdog_grit_work_mult`) and the Desperation Meter (MCP energy + STRIKE/VIRUS damage, `_tick_desperation`/`desperation_energy_rate`/`desperation_damage_mult`) are implemented but **switched off** in `Config` — `CATCHUP_GRIT_WORK_MULT_PER_STACK` = 1.0, `CATCHUP_DESP_ENERGY_PER_STACK`/`CATCHUP_DESP_DAMAGE_PER_STACK` = 0.0 (marked "off"; DESIGN values preserved in Config comments). All three are wired live every tick (`desperation_energy_rate` in `EnergyManager`, grit in `Unit.work_speed_multiplier` + `TileElement` countdowns, desperation damage in `CombatManager`/`Virus`) — flipping the Config multipliers back on re-enables them. DESIGN.md describes them as active.
- **Construction**: BLUEPRINT building's `_process` consumes energy at `CONSTRUCTION_COST / CONSTRUCTION_TIME`; at full → `set_constructed()` (`rpc_constructed` removes the blueprint and reveals the building).
- **Production**: CONSTRUCTED building accumulates `_production_energy` via `request_energy`; at `UNIT_COST` → spawn via `um.rpc("rpc_spawn_unit", uid, type, building_id)`; cooldown from `Config.PRODUCTION_COOLDOWNS`. MCP overrides: AVATAR first, then ZOOMBA up to `zoomba_cap = floor(sqrt(player_aoe_totals[pnum]))` (MCP cooldown is 2.0s for MCP_1 — `# TESTING` — and 10s for MCP_2..4). **Converted TANKs spend the zoomba cap too** — the cap is the MCP-derived army budget (`zoomba + tank < cap`), so converting never grows the army. Garage overrides: issues CONSUME_ZOOMBA jobs instead of spawning directly, with a pooled tank target `player_tank_target()` = Σ `roundi(cap × garage.ratio)` over the player's garages, clamped to `cap − 1` (never converts the last zoomba — sums ≥ 100% across garages still leave 1). Conversions are one-way: a destroyed TANK does not return its zoomba. Beacon → AERIAL, Nest → VIRUS.
- **Empower**: `BuildingManager.set_empowered_for_player` (one building per player, swap clears the previous), `rpc_set_empowered` (reliable, call_local → every peer applies `_empower_changed`), `empowered_type(pnum)` for type-wide army buffs. **Only CONSTRUCTED buildings can be empowered** (`Server._cmd_empower` rejects blueprints/under-construction — army-wide buffs must cost a finished building). Removing the empowered building (any cause) clears the player's empower via `rpc_remove_building` → `clear_empowered_for_player` *before* Vat pool detach, so the pool master/members are un-empowered while the pool graph is intact (fixes the stale permanently-empowered master). Buffs per DESIGN: **Generator** +1 influence radius (instance); **Vat** ×1.5 capacity + ×0.9 drain discount (instance capacity, type-wide discount via `Building._vat_spend_mult` — the discount scales the construction/production **completion thresholds**, so builds take the same time and pay less); **MCP** zoomba spawn rate ×0.8 cooldown, zoomba move/work speed ×1.2, damage reduction ×0.75 (instance); **Garage** all TANKs fire interval ×0.8 vs AERIAL (type-wide); **Beacon** all AERIALs +30s lifetime (type-wide, dynamic); **Nest** all VIRUS move time /1.3 + limpeted TANKs immobilized (type-wide). Terminal Empowered row shows per-type buff text + state (EMPOWERED / BUFF ACTIVE via another of the type / dim idle hint) via `TerminalHUD._set_empower_indicator`.

- **Settings inheritance**: newly constructed Garage/Beacon/Nest copy the player's latest settings (ratios, targets, stance) from the highest-id sibling of the same type (`Building._inherit_settings_from_sibling` → `_copy_settings_from` → `rpc_inherit_settings`); the server applies the copy through the command relay, clients mirror it locally for display.
- Building HUDs: all six HUD scenes extend the `TerminalHUD` base (`scripts/ui/TerminalHUD.gd`): CRT shader overlay, cursor wiring (`drive_cursor_at_uv`/`click_at_uv`/`release_cursor`/`uv_from_collision` via `TerminalCursor.gd`, which pushes synthetic input events into the SubViewport), enemy-target button theming, owner-colour tint, empower button (`_empower_building` → `send_command_me("empower")` + `Global.VM.force_leave_fps()`) and `_set_empower_indicator` (EMPOWERED / BUFF ACTIVE via another of the type / dim idle hint). Each building gets its own `SubViewport` + HUD scene (`_setup_hud`), rendered into the `Terminal/Screen` material; terminal positioned at the access tile nearest the MCP (`position_terminal`). Building settings are mirrored to all peers through the snapshot system, so enemy terminals are spyable (`GameManager._refresh_foreign_building_terminals`, 4Hz). **Terminal SubViewports render on demand**: `UPDATE_ONCE` with re-render at the 4 Hz HUD data cadence (`Building._process` + `refresh_terminal_ui` → `_request_hud_rerender`), switching to `UPDATE_WHEN_VISIBLE` while a cursor hovers the terminal (smooth glow tweens). Terminal content only changes at 4 Hz (or on interaction), so a per-frame render was pure waste. Per-HUD notes: Beacon ratio slider is inverted (shows STRIKE %, sends 100−value); Garage shows the summed ratio over all garages (red when >100%); Generator shows catchment buckets tinted by `Config.CATCHMENT_*`; MCP shows zoomba+tank vs cap; Nest's building-target section appears only when the slider isn't at 100% tanks; Vat shows energy/capacity + adjacency count. Production is a **toggle button** (PRODUCING/PAUSED) on Garage/Beacon/Nest only — not a radio (MCP always produces). RTS hover tooltip: hovering your own CONSTRUCTED building in RTS opens a read-only instance of its HUD scene (`HUD.gd`, `set_tooltip_mode(true)`).

## Combat

- **CombatManager** (server-only): every 0.5s re-scans TANK/AERIAL/AVATAR units; score = `dmg × 10 - health`, must pass range (40) and line-of-sight (raycast that ignores LOWERED/FALLING/DISABLED_LOWERED tiles and self/target, blocks on RAISED/DISABLED_RAISED; per-pair results are cached and invalidated on any tile/building change). Enemy targeting is **explicit-list only**: a unit attacks players in `orders["enemy"]` — an empty list means it attacks nothing (no "everyone" fallback), and its own team is never included. Aerial roles: "patrol" = PATROL mode (home patrol, 3-tile VIRUS detect), "strike" = STRIKE mode (enemy overfly, 1-tile detect). Detection uncloaks a cloaked VIRUS (`c.uncloak()`); a cloaked VIRUS is never a fire target (`_update_firing` skips it). Kill-VIRUS jobs (`COMBAT_PERSUE`, `patrol_only` + `territory_only`) are executed only by PATROL aerials.
- **Avatar uncloak**: `_scan_avatar` uncloaks cloaked enemy VIRUS within Avatar LoS — 40u in FPS, 10u in RTS (`AVATAR_VIRUS_DETECT_RADIUS_FPS/RTS`), per DESIGN. Radius follows the owner's camera mode: local avatar reads `Global.VM.camera_status`, remote avatars use the mode their client reported via the `camera_mode` command.
- Firing: when weapon aligned (`Unit.is_weapon_aligned()`, slerped in `_update_weapon_aim`), bursts of `WEAPON_BURST_DURATION`(0.4) with damage ticks every 0.1s — the burst block runs across frames in `_update_firing` (a 2025 perf edit had accidentally nested it inside the fire-timer block, collapsing every burst to one tick; fixed). Each tick applies the full `Config.get_damage()` value (retune later if needed). The burst pauses behind the LOS-grace waits. TANK fires an instant burst (fire interval ×0.8 vs AERIAL while a Garage is empowered — type-wide); AERIAL applies a projectile delay (`update_projectile_delay`). `combat_fire_event` is bumped server-side and drives client visuals (`_update_combat_visuals`). A TANK immobilized by a VIRUS limpet from an empowered Nest cannot fire at all (`virus_immobilized()`). Rallied units within `RALLY_TETHER_RADIUS` of their avatar deal ×1.1 damage (`_rally_tethered`, see Rally). **LOS cache invalidation**: `invalidate_los()` is called by `recompute_aoe`, by the actual tile state transitions in `TileElement._begin_toggle`/`_done_toggle` (not at selection time — `apply_toggle` no longer invalidates, since deselect/reject never move a wall), and by unit spawn/remove (`UnitManager`). Target scans build per-player unit/building groupings once per scan, so each attacker only iterates enemy players' entities.
- **Damage** via `Config.get_damage(attacker_type, target, mode)`: TANK damages only AERIAL (×6 patrol / ×5 strike). AERIAL damages VIRUS ×5 (patrol) / BUILDING ×2 (strike), plus mode-vs-mode multipliers. `apply_damage(amount, delay, attacker)` on server → health; ≤0 removes unit/building. `SELF_HEALING_UNITS` (ZOOMBA, TANK, AVATAR) heal server-side at `Config.SELF_HEAL_RATE` (10/25/10 HP/s) after 10s out of combat. A damaged ZOOMBA scram(). A CONSTRUCTED building calls for defense: `_call_for_defense(attacker)` queues a `COMBAT_PERSUE` job on the attacker — VIRUS attacker → PATROL aerials (`patrol_only` + `territory_only`), any other (AERIAL) → TANKs (`territory_only`).
- **VIRUS combat**: VIRUS doesn't fire — it generates a **personal `ATTACK` job** (`Virus.try_generate_offense_job`, like Aerial-strike) from its copied Nest orders (`enemy` / `target` / `tank_ratio`). Target = random enemy tank on the `tank_ratio` roll, else `CombatManager.choose_building_target(require_constructed=true)` (shared with Aerial-strike, which passes false; MCP types MCP_2..4 normalize to the MCP_1 toggle). An aerial spotting an enemy tank also queues a **pooled** `ATTACK` job (`eligible_types=[VIRUS]`) so a freshly spawned virus can be assigned it before it self-derives (the 1s `_idle_time` guard). On arrival `_start_work()` → `start_attack()`: uncloak, attach (`_limpet_target`, registered on the tank via `Tank.register_virus` so the Nest immobilize buff applies), and **jump straight onto the tank** (snaps `location`/`global_position` and rides it every tick, even through the delay — a moving tank can't drift away), then after `VIRUS_ATTACH_DELAY`(1s) the tank drain begins at `VIRUS_TANK_DRAIN_DPS`(40) — or a **building channel** (see Infection below). Ambient 1.25/s decay pauses while WORKING. Re-cloaks after `VIRUS_RECLOAK_COOLDOWN`(5s) when uncloaked & not attached (spawns uncloaked). Dies when its limpet TANK dies (any cause) or when it delivers a building infection (self-sacrifice); survives if the building is destroyed mid-channel → re-targets. Multiple VIRUS may limpet one target (personal jobs skip dedup).
- **Building infection** (no cap — see DESIGN): multiple VIRUS channeling the same building share a per-(building, attacker) pool (`Building._channels`); the pool is a fixed `VIRUS_INFECTION_BASE_DURATION`(15s) of channeling effort and each channeler pours in at `1/health-fraction` per second (`Virus.channel_rate()` — a 75 HP virus's seconds count double, matching its prorated channel), so every joiner strictly speeds completion. Completion → `BuildingManager.infect_building(attacker, building, strength)`: the empowered building is rejected (immune); otherwise the effect is created (`{strength, remaining: VIRUS_INFECTION_DURATION}`) or **refreshed** by the same attacker (`remaining += duration × strength`, strength replaced). Magnitude scales with strength. Per-type effects: Generator power theft (EnergyManager redirects `get_energy()` to attackers, split by strength share); Vat per-vat store drain (`VIRUS_VAT_DRAIN_DPS`, cascades to the whole shared-health pool via `BuildingManager.infect_building`); Beacon store drain + 25 DPS to the owner's AERIALs (`Beacon._tick_infection`); Garage halves TANK patrol speed (`Unit._move`) and ×5 AA fire interval (`CombatManager`); Nest uncloaks + DoTs the owner's VIRUS on owner territory (`Nest._tick_infection`); MCP halts ZOOMBA production (`MCP._can_produce` — the Avatar still respawns, as it is the cure) and takes extra AERIAL damage (`MCP._apply_damage`). Expiry (`remaining` ticked in `Building._tick_infection`, per-attacker `cure_infection`) or the Avatar curing by touch in FPS (`Avatar._scan_cure`, `VIRUS_CURE_RADIUS`; Vat cure cascades). Infection keys sync to clients via the building snapshot mask (slot 10) → `Building.apply_infection_mask` drives the attacker-coloured torus ring visual + defender notification, and slots 11/12 drive the pooled-channel and remaining-duration status bars (`_bar_channel`/`_bar_remaining`).
- Health bars: `HealthBar3D` for units and buildings. **Debug keys in HUD: `ui_scram` (C), `ui_damage_building` (P), `ui_damage_unit` (L), `ui_debug_tile` (F4 — prints the tile under the cursor + copies its id to the clipboard; level-authoring helper). The first three are DEBUG-ONLY, intentionally unrestricted: `ui_damage_*` go through the server command relay (`_cmd_debug_damage_*`) so ANY peer can damage every player's units/buildings, and `ui_scram` calls `zoomba.scram()` directly on every zoomba in the group (host-effective, no-op for remote clients). Do not wire gameplay features through them; strip them from a release build. Leave the direct scram call alone — routing it through a command would just widen the cheat surface.**
- RTS cursor light (`OmniLight3D_RTS`): `ui_debug_light` (F3) toggles a wireframe gizmo (magenta sphere = `omni_range`, white axis = down direction, cyan cross = light origin) built by `OmniLight._build_debug_mesh()`. The light is omnidirectional — OmniLight3D has no cone/`omni_angle` property in this engine.

## Statistics

- **StatisticsManager** (`Global.SM`, server-only): samples every 1s (`TICK_INTERVAL`), appends one record per player to a history capped at `MAX_STATS_RECORDS`(3600 = 1h) — `stats[pnum]` is an `Array` (newest last) on the server. Oldest-first pruning keeps memory bounded regardless of game length.
- Record fields: `time` (monotonic seconds since engine start — x-axis of the graphs), `aoe_size` (split AoE score from `TileManager.player_aoe_totals`), `energy` {`stored`, `capacity`, `generated`, `used`} (trailing-1s rates from `EnergyManager.get_player_energy()`), `units` {`zoomba`, `tank`, `aerial_strike`, `aerial_patrol`, `virus`}, `damage` {`done`, `received`}.
- Damage hooks: `record_damage_done` (CombatManager at fire time) / `record_damage_received` (Unit/Building/Vat `_apply_damage` at impact time). Debug-key damage (P/L, attacker-less) counts as received only.
- **Sync**: each finalized record is pushed to the owning remote client via `rpc_id(peer, "rpc_receive_stats", p, record)` (`@rpc("authority","call_remote","reliable")`). `Server.player_to_peer` only contains remote clients (peers > 1), so the host's local slot and AI slots are skipped — the server keeps full history for everyone, while a client only gets its own player-number key populated.
- Query: `Global.SM.get_stats(pnum)` → the player's full history `Array`.
- **Statistics window** (`scenes/ui/StatisticsWindow.tscn`, `Global.VM`-gated): toggled by the `ui_stats`/M key in HUD `_input`, only while `Global.game_started` and camera is `OVERHEAD`; ESC and the X button also close it. Full-screen modal (STOP mouse filter + backdrop; HUD swallows game input while open). Reads `Global.SM.get_stats(Global.my_player_number)` (a client only ever has its own key populated) and renders three `LineGraph`s refreshed at 0.5s: AoE+Energy (dual-axis — energy on the left axis, AoE tiles on the right), Units, Damage. Trailing-window buttons select the most recent 30s/10m/30m. `LineGraph` autoscales each axis to a "nice" ceiling (1/2/5 × 10ⁿ) and draws the legend inside the graph. After game over the window opens automatically in end-of-game mode (`StatisticsWindow.open_end_of_game()`); dismissing it returns to MainMenu via `Global.leave_game()` (see Game over).

## Avatar / FPS camera

- `Global.VM.CameraStatus` = OVERHEAD → TO_FPS → FPS → TO_OVERHEAD. Toggle via HUD button or `ui_capture_toggle`; 2s transition tween, mouse captured in FPS. Trauma/shake via `add_trauma` (distance falloff from the viewer, optional linger). `camera_mode` is reported at every transition start AND end — the server uses it for the per-player avatar VIRUS-detect radius and rally legality.
- `Avatar` (`scenes/world/units/Avatar.tscn`) = Unit with `FPSBody` (CharacterBody3D + `Rotation_Helper`/`FPSCamera`). WASD + `ui_movement_jump` movement, mouse look, `ScreenRay` for interacting with terminal HUDs (`ScreenBody` collision → drives the 2D `TerminalCursor` in the building's SubViewport HUD, propagating hover + click) — only within `TERMINAL_INTERACT_RANGE` (2 × `Cairo.UNIT`) of the building.
- **Empower beam**: the avatar carries a `Zapper` node under `FPSBody` (beam origin ≈ chest height). `Avatar._update_empower_beam()` (every peer, every frame) finds the player's empowered building (`is_empowered` + `player_owner` — synced via the reliable `rpc_set_empowered`), builds the zapper's basis so its local +Y points at that building's `Terminal/Screen` global position, sets `target_position.y = distance` (the jaggy endpoint is snapped to `(0, target_position.y, 0)`, so an exact distance parks the tip on the screen plane; any overreach punches through the terminal), and hides the beam when none / out of `EMPOWER_BEAM_MAX_RANGE` (1.5 × interact range — suppresses the beam after a distant MCP respawn). No snapshot changes: empowered building, terminal transform (deterministic `position_terminal`) and FPSBody transform (locally driven / relayed via avatar snapshots) are identical on every peer, so the beam matches on server + all clients. Cleared by `clear_empower` (re-enter FPS), building removal, redirects on re-empower, or the avatar's death (`UnitManager.rpc_remove_unit` server-side clear on the Avatar branch).
- Avatars skip the job system entirely (`idle_callback` no-op; `assign_jobs` skips AVATAR; not in `HOME_TERRITORY_UNITS`). Avatar snapshots are relayed separately (see Snapshot section).
- Camera helpers: `fps_locked` blocks FPS entry (set during the victory banner); `force_leave_fps()` (used by empower — buff cleared on FPS exit) and `exit_fps_immediate()` (avatar death / game over, parks the camera at the death site); `jump_to(pos)` tweens the RTS camera to a position (notification click-through).
- **The `Avatar` root (a `Unit`) never moves from its spawn tile — only its `FPSBody` (CharacterBody3D) travels the world.** Any system needing the avatar's real position must read the `FPSBody`'s transform (e.g. `avatar.get_node("FPSBody").global_position`), never the root's `global_position`/`location`. This drives combat aim (`CombatManager` aims at the body), snapshot/interpolation (avatar snapshots pack the `FPSBody` transform), and camera transitions.

## Rally (Avatar squad)

DESIGN's FPS rally ability, fully implemented:

- **Command**: `Server._cmd_rally` — FPS-only (rejects presses unless the caller's reported `camera_mode` is FPS), server-enforced per-player cooldown (`Config.RALLY_COOLDOWN` 15s, `_rally_cooldowns` dict), then `JobManager.start_rally(pnum)` + cosmetic shockwave `UnitManager.rpc_rally_fx` → `RallyRing` (expanding torus, player accent).
- **Gather** (`JobManager.start_rally`): friendly TANK/AERIAL/VIRUS (ZOOMBA excluded) — alive, not scramming, not already rallied, within `RALLY_RADIUS` (8 × `Cairo.UNIT`) of the avatar's FPSBody with LOS. Each joins via a **personal `COMBAT_PERSUE` job targeting the avatar** (`personal=true`, so multiple presses grow the squad). HOLD-stance TANKs/AERIAL-PATROLs switch to WIDE on rally; PATROL/STRIKE **mode is never switched** (fixed at spawn).
- **Follow**: squad members stay in the normal PATHING state — the avatar root never moves, so `JobManager.rally_avatar_tile()` resolves the follow target to the nearest walkable unoccupied tile under the FPSBody (0.5s-TTL memo cache); adjacent units orbit tile-to-tile, far units A* to its access tiles.
- **Marker + sync**: `Unit.set_rallied()` toggles a player-accented disc under the unit, on every peer; the flag syncs via **snapshot slot 7** (TANK/AERIAL/VIRUS only).
- **Tether bonus**: rallied units within `RALLY_TETHER_RADIUS` (4 tiles) of the avatar deal ×1.1 damage (`Config.RALLY_TETHER_DAMAGE_MULT`, applied in `CombatManager._rally_tethered`).
- **Rallied VIRUS**: a rallied VIRUS may drop out (abandons the squad, clearing `rallied`) to limpet an enemy TANK/building it comes within `RALLY_LIMPET_RANGE` (3 tiles) of (`Virus._try_rally_attack`, 1s throttle).
- **Disband** (squad returns to normal patrol): avatar death (`UnitManager.rpc_remove_unit` → `cancel_player_rally`) or leaving FPS (`Server._cmd_camera_mode` → `cancel_player_rally`). Home-territory units left outside their AoE then walk the MCP-distance gradient back inside it.
- **UI**: `ui_rally` (R) handled in `HUD._input` only while `Global.VM.camera_status == FPS`; `RallyCooldownRing` (circular `draw_arc` around the crosshair, client-side cooldown mirror — the server enforces the real one).

## Game over (victory)

- **Detection**: `BuildingManager.rpc_remove_building` → a destroyed CONSTRUCTED MCP triggers `GameManager.on_player_eliminated(owner)` (server-only): clears the player's empower, removes all their buildings and units; when exactly one CONSTRUCTED MCP remains → `rpc_game_over(winner)` (`@rpc("authority","call_local","reliable")`).
- **Banner**: `rpc_game_over` snaps FPS players back (`exit_fps_immediate`, `VideoManager.fps_locked = true` — FPS re-entry blocked during the banner) and shows `VictoryBanner` ("<NAME> WINS!" in `Config.PLAYER_NAMES`/`player_accent` colour, group `victory_banner`). The sim keeps running for `GAME_OVER_BANNER_DURATION` (5s) so a second MCP can fall mid-banner.
- **After banner**: `Global.game_started = false` (server sims stop), banner hidden, `StatisticsWindow.open_end_of_game()` — dismissing it calls `Global.leave_game()` back to MainMenu.
- No surrender mechanic (matches DESIGN); victory is **last single MCP owner** — no teams/alliances (DESIGN's alliance system is a FUTURE STRETCH GOAL).

## Godot 4 conversion patterns

- **Member variables and constants are declared at the top of each script**, grouped under `# --- ... ---` headers (Signals, Types, Constants, State, Nodes/`@onready` refs) — never inline mid-file near their only usage.
- **Tween** is RefCounted, not a Node: `create_tween()`, chained `tween_property/tween_method/tween_callback`, auto-starts. Store in a local/plain var, kill with `tween.kill()` + guard `tween and tween.is_valid()`, never `@onready`.
- **`setget` → set/get blocks** with underscore-backed var (`var _contains_val` backed by `contains`).
- **`@rpc` annotations**: `@rpc("authority", "call_local")` (server call runs everywhere), `@rpc("any_peer", "call_remote")` (client→server, derive caller via `get_remote_sender_id()`), plus `"reliable"`/`"unreliable"`. **Every RPC function is named `rpc_<name>`** (e.g. `rpc_spawn_unit`, `rpc_apply_snapshot_chunk`, `rpc_set_my_player_number`) and is called by that exact string — `rpc("rpc_<name>", ...)` / `rpc_id(peer, "rpc_<name>", ...)`.
- **ImmediateMesh**: `clear_surfaces()` / `surface_begin()` / `surface_add_vertex()` instead of ImmediateGeometry.
- **Materials**: player colour at `res://materials/player/player<N>_material.tres` (1..4, matches `PLAYER_COLORS`). Floor: `res://materials/floor/grid_faces.tres` (lit) + `grid_edges.tres` (unshaded cyan, `use_instance_color`).
- The whole codebase is converted — no Godot 3 syntax remains (this file's old "Remaining patterns" list is resolved).
- `Config.UI_*` accent constants are mirrored by hand in `themes/neon_ui.tres` and `themes/terminal_ui.tres` (Godot themes can't read GDScript constants) — keep all three in sync when changing the palette.

## Gotchas

- Player number = **slot index + 1** — the MainMenu slot the host assigns a role to IS the player number that slot plays as. Remotes draw from `Server.remote_slot_pnums` in slot order (first connector = lowest-numbered remote slot); a peer connecting with no free slot is rejected. Freed pnums go back into the pool on disconnect.
- `rpc_id(1, ...)` targets the server (peer 1 is always the server in ENet).
- `TileManager.apply_toggle` validates `tile.state == RAISED` and LOWERED-with-no-building before toggling (DISABLED_* states fail the check — obsidian is never toggleable). Never call it directly — use `Global.send_command*`.
- **`Global.level` is a runtime var** — every peer must set it to the identical level before World loads (MainMenu no-remote path, `Lobby._start_game` on the host, `Lobby.rpc_start_game` on clients). Setting it after World loads desyncs tile IDs.
- `OS.get_cmdline_user_args()` (not `get_cmdline_args()`) is what sees args after `--` — use it for CLI flags like `--dump-tiles`/`--level=`.
- `Global.my_player_number` = -1 for a host with no LOCAL slot (spectator); `send_command_me` no-ops and HUD energy reads 0.
- `%` unique-node lookup requires caller `owner`. Dynamically created TileElements miss this → use a stored `pathing_manager` ref (set by `TileManager._set_neighbours`) instead of `%PathingManager`.
- `TileElement` has no `.player` — check `.selected_by` / `.aoe` / `player_owner` on buildings/units.
- Server-only functions called from `_process`/`_physics_process` (which run on all peers) must self-guard.
- `create_tween()` returns RefCounted — local var, `.kill()` + `.is_valid()` guard, no `@onready`.
- Unit/buildings are spawned/removed only via `@rpc("authority","call_local")` RPCs; never add children directly on a client. Sole exception: level-setup MCP placement (`TileManager._apply_loaded_level` → `BuildingManager.place_building`) is deterministic and runs locally on every peer — no RPC involved.
- **Avatar root stays put** — the `Avatar` (Unit) node remains at its spawn tile; only its `FPSBody` child moves. Always read `avatar.get_node("FPSBody").global_position` for where the avatar actually is.
- `EnergyManager`/job/player dicts are 1-based (1..`MAX_PLAYERS`). Loops: `range(1, Global.MAX_PLAYERS + 1)`.
- **Game over**: `Global.game_started` flips false after the victory banner — server sims stop. `Global.leave_game()` is the single teardown path (lobby back, end-of-game dismissal).

## Lobby flow

- When any REMOTE slot exists, "Start Lobby" loads `scenes/menu/Lobby.tscn`; otherwise straight to `World.tscn`. Remote clients always land on `Lobby.tscn` and wait.
- `NetworkManager.start_server()` returns `false` if the ENet bind fails (e.g. a stale game instance already holds the port) — `MainMenu` aborts with an error dialog instead of entering the lobby with a dead server (which previously made new clients connect to the stale instance and land in spectator).
- `Server.accepting_clients` stays false until the host enters the Lobby — clients connecting earlier are disconnected so they see a connection failure instead of silently joining.
- **TODO (mid-game reconnect)**: a peer that disconnects mid-game has its slot pnum freed back into `remote_slot_pnums` and its `_ready_peers`/player entry removed, but `accepting_clients` is set false when the lobby exits, so reconnecting peers are rejected — and nothing tears down the disconnected player's sim (MCP keeps producing, army keeps fighting). Re-enabling reconnect needs a full game-state sync (tiles, buildings, units, energy, jobs, empower, infections) for the joining peer, plus sim teardown/transfer for the freed pnum. Flagged to revisit.
- Host starts when `peer_to_player.size()` >= REMOTE slot count **and** every connected peer has confirmed it is inside the Lobby scene (`rpc_client_lobby_ready`; a 10s soft-lock fallback force-starts). Then host `rpc("rpc_start_game", level_name)` + everyone loads World — `rpc_start_game` sets `Global.level` on each client before the scene change, and the lobby state broadcast carries `level_name` so clients display the chosen map.
- AI controllers skip actions while `not Global.game_started` or `Global.TM` is null (lobby).
- Back button (and end-of-game dismissal): `Global.leave_game()` — nulls `network_manager` first, closes `Server.accepting_clients`, calls `NetworkManager.stop()` (closes both peer types), resets `my_player_number`, restores the mouse, then reloads MainMenu.
- `NetworkManager.stop()` closes the client ENet peer too (`multiplayer.multiplayer_peer.close()`), not just the server peer.

## Floor (decorative only, no multiplayer sync)

- `scenes/world/floor/Floor.tscn` — 50×50 visual floor (`GridMultiMesh` with per-instance mountain displacement via `meshes/grid.tres` shader params `SCROLL`/`SPEED`/`MOUNTAIN_MAX_HEIGHT`), monuments (`Monument.tscn` root is a StaticBody3D with no collision — the `create_convex_collision()` branch is `GENERATE = false`), no RPCs. Timer morphs mountains via `create_tween()` → `tween_method()` → `_update_mountain(idx, color)` (1s `MORPH_TIME` per column). `Grid.gd` is dead code (`GENERATE = false`); the floor uses `meshes/grid.tres` instead.

## UI rules

- One LOCAL slot max — selecting LOCAL on a second slot snaps the first back to Remote (`MainMenu._on_slot_selected`). Zero LOCAL slots = Spectator mode. Slot dropdown options are Host (Local)/Remote/AI — no CLOSED entry (unused `GameConfig.SlotType.CLOSED`); defaults: slot 0 Local, slot 1 Remote, slots ≥2 AI.
- HUD modes: RAISE/LOWER (tile toggle, drag-select via `begin_drag`/`should_toggle`), building placement (GEN/VAT/GARAGE/BEACON/NEST) → `TileElement` click sends `place_blueprint`, and REMOVE (demolish mode — click an owned building; the MCP can't be removed, removing an empowered building clears its empower). Building HUDs (SubViewports) send all building commands via `send_command_me` — commands carry `building_id`, never a node reference.

## Running

- Godot 4.7 binary: `C:\Users\timbo\Documents\Godot_v4.7-stable_win64.exe` (also `Godot_v3.6.2-stable_win64.exe` beside it for older projects). Use it for headless checks, e.g. `& "C:\Users\timbo\Documents\Godot_v4.7-stable_win64.exe" --headless --path <project> --quit-after 90` to catch parse/script errors.
- Level tile dump: `& "C:\Users\timbo\Documents\Godot_v4.7-stable_win64.exe" --headless --path <project> -- --dump-tiles --level=<key>` prints every tile (id, anchor x/z, state, flags, neighbours) and writes `user://level_dump.txt`, then quits.
- The user can run interactive tests inside the engine themselves (launch the game, join/multiplayer, place buildings, etc.) — when verifying a fix, prefer asking the user to test interactively rather than relying on headless reproduction.
- Pass `--client` as CLI arg to launch a second instance on the Connect tab (`MainMenu` checks `OS.get_cmdline_args()`).
- Default config for instances: "Run Instances" in the Godot editor with `--client` on the second.
