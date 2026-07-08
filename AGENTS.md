# NeonFeverDreamMP — AGENTS.md

## Stack

- **Godot 4.7**, Jolt Physics, D3D12 renderer, Forward Plus
- Entrypoint: `scenes/menu/MainMenu.tscn`
- Single autoload: `autoload/Global.gd` (holds `network_manager`, `game_config`)
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

## Key classes

| Class | File | Role |
|---|---|---|
| `Global` | `autoload/Global.gd` | Singleton, holds `network_manager` ref |
| `NetworkManager` | `scripts/core/network/NetworkManager.gd` | Creates Server/LocalClients or ENet client |
| `Server` | `scripts/core/network/Server.gd` | ENet server, peer→player mapping, command dispatch |
| `TileManager` | `scripts/world/tiles/TileManager.gd` | Cairo pentagon tile grid generation + multiplayer selection sync |
| `TileElement` | `scripts/world/tiles/TileElement.gd` | Single tile (StaticBody3D + MultiMesh instance) with hover/selection visual |
| `AIController` | `scripts/core/ai/AIController.gd` | Random timer-driven tile toggle |
| `GameConfig` | `scripts/core/game/GameConfig.gd` | Slot config: LOCAL, REMOTE, AI, CLOSED |
| `CameraController` | `scripts/world/CameraController.gd` | Middle-click drag, scroll zoom |

## Running

- Pass `--client` as CLI arg to launch second instance on the Connect tab (skips Host tab).
- Default config for instances: `"Run Instances"` in Godot editor with `--client` on the second.

## Gotchas

- `Server.next_player_num` is set by `NetworkManager.start_server()` before creating local clients — do not hard-code it.
- `rpc_id(1, ...)` targets the server (peer 1 is always the server in ENet).
- `TileManager.apply_toggle` validates `tile.state == RAISED` before toggling — tiles in FALLING/LOWERED/DISABLED are skipped.
- `Global.my_player_number` is set at slot-creation time for the host human, or by `NetworkManager.set_my_player_number` RPC for remotes. If `my_player_number == -1`, the multi-selector fallback uses `selecting.min()`.

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

## Tile scripts (imported from Godot 3, converted)

- `TileElement.gd`: `tween.remove`→`active_tween.kill`, `interpolate_method`→`tween_method`, `interpolate_property`→`tween_property`, `interpolate_callback`→`tween_callback`, signals use `.connect()` not `connect()`, `BUTTON_LEFT`→`MOUSE_BUTTON_LEFT`, `GlobalVars`→`Global`, commented code updated too. `transform.origin.y = val`→copy-modify-set pattern.
- `TileManager.gd`: `BaseMaterial3D`→`StandardMaterial3D`, `set_surface_material`→`set_surface_override_material`, `set_multimesh()`→`.multimesh =`, `translation`→`position`, `use_in_baked_light` removed.
- `TileManager.tscn`: both `[node name="Tween"]` children removed.
- `PathingManager.gd`: `PackedInt32Array`→`PackedInt64Array`.
- `Cairo.gd`: `GENERATE = false` with "do not regenerate" note.
- `MonorailMultimesh.gd`: not yet reviewed.

## UI rules

- Only one slot can be "Host (Local)" — selecting LOCAL on a second slot snaps the first LOCAL back to Remote.
- Zero LOCAL slots is allowed (Spectator mode): the host can watch but has no AIController, so host clicks route through `send_command_me` but get dropped by Server (no `peer_to_player` entry for the host).
