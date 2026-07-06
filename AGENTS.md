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

### Toggle flow (3 paths, all converge on `GameGrid.apply_toggle`)

1. **Host human click**: `GameGrid._input` → `_on_cell_clicked` → `human_controllers[0].send_toggle_cell` → `HumanController.send_toggle_cell` → `Server._handle_toggle_cell` → `GameGrid.apply_toggle`
2. **AI**: `AIController._on_timer` → `Server._handle_toggle_cell` → `GameGrid.apply_toggle`
3. **Remote client click**: `GameGrid._input` → `_on_cell_clicked` (no human_controllers) → `rpc_id(1, "toggle_cell")` → server's `GameGrid.toggle_cell` → `Global.network_manager.server._on_remote_toggle_cell` → `Server._handle_toggle_cell` → `GameGrid.apply_toggle`

After `apply_toggle`, `apply_cell_update` broadcasts `rpc("set_cell", x, z, owners)` to all remote peers.

## Grid state

- 32×32 `grid_data[x][z]` arrays of player numbers (empty = unowned).
- Visual: per-cell `GridCell` instances with `Label3D` showing current owners.
- `set_owners(owners: Array)` drives the visual — no TileMap involved.
- Initial sync: `Server._on_peer_connected` calls `_sync_client_grid` which sends `rpc_id(peer_id, "set_cell", ...)` for every non-empty cell.

## Key classes

| Class | File | Role |
|---|---|---|
| `Global` | `autoload/Global.gd` | Singleton, holds `network_manager` ref |
| `NetworkManager` | `scripts/core/network/NetworkManager.gd` | Creates Server/LocalClients or ENet client |
| `Server` | `scripts/core/network/Server.gd` | ENet server, peer→player mapping |
| `GameGrid` | `scripts/world/GameGrid.gd` | Grid state + cell visuals |
| `GridCell` | `scripts/world/GridCell.gd` | Single cell (MeshInstance3D + Label3D) |
| `HumanController` | `scripts/core/network/HumanController.gd` | Host-side click bridge |
| `AIController` | `scripts/core/ai/AIController.gd` | Random timer-driven toggle |
| `GameConfig` | `scripts/core/game/GameConfig.gd` | Slot config: LOCAL, REMOTE, AI, CLOSED |
| `CameraController` | `scripts/world/CameraController.gd` | Middle-click drag, scroll zoom |

## Running

- Pass `--client` as CLI arg to launch second instance on the Connect tab (skips Host tab).
- Default config for instances: `"Run Instances"` in Godot editor with `--client` on the second.

## Gotchas

- `Server.next_player_num` is set by `NetworkManager.start_server()` before creating local clients — do not hard-code it.
- `GameGrid.toggle_cell()` looks up Server via `Global.network_manager.server` (not a node path) — the node path lookup fails because NetworkManager is dynamically added to root.
- `rpc_id(1, ...)` targets the server (peer 1 is always the server in ENet).
- Host's GameGrid has `human_controllers` group (direct path), remote clients have none (RPC path).
- `_sync_client_grid` only sends cells with non-empty owner arrays.

## Lobby flow

- When any REMOTE slot exists, "Start Lobby" loads `scenes/menu/Lobby.tscn` instead of going straight to World.
- Lobby shows slot config, waits for all REMOTE peers to connect, then auto-starts World when `Server.peer_to_player.size()` equals the REMOTE slot count.
- Host broadcasts `rpc("remote_start_game")` to all clients before transitioning; clients receive it via `Lobby.remote_start_game()` and load World.
- Remote clients also load `Lobby.tscn` (not World.tscn) on connect, and wait for the host's RPC.
- AI controllers check for `/root/World/GameGrid` existence and skip actions during lobby (the node doesn't exist yet).
- Back button calls `Global.network_manager.stop()` + `queue_free()` and returns to MainMenu.
- `NetworkManager.stop()` also closes the client ENet peer (`multiplayer.multiplayer_peer.close()`) in client mode — not just the server peer.

## UI rules

- Only one slot can be "Host (Local)" — selecting LOCAL on a second slot snaps the first LOCAL back to Remote.
- Zero LOCAL slots is allowed (Spectator mode): the host can watch but has no HumanController, so host clicks route through RPC (Path C) but get dropped by Server (no `peer_to_player` entry for the host).
