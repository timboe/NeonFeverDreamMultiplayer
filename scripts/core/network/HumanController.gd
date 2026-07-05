extends Node
class_name HumanController

# Present on the host machine only (child of a LocalClient).
# Acts as the bridge between mouse clicks on GameGrid and the server.
# Reads player_number from its parent LocalClient and reaches the
# server via Global.network_manager.server — no RPCs involved.
# Remote clients have no HumanController; they use rpc_id(1, ...) instead.

func send_toggle_cell(x: int, z: int):
	var client = get_parent() as LocalClient
	if not client:
		return
	var srv = Global.network_manager.server
	if srv:
		srv._handle_toggle_cell(client.player_number, x, z)
