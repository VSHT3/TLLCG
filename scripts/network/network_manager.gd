## NetworkManager
## Stub for future multiplayer implementation using Godot's ENet.
## Currently provides the interface — fill in when ready to add networking.
class_name NetworkManager
extends Node

# ── State ────────────────────────────────────────────────────────────────────

var is_host: bool = false
var is_online: bool = false
var peer_id: int = -1
var connected_peers: Array[int] = []

# ── Signals ──────────────────────────────────────────────────────────────────

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal game_action_received(action: Dictionary)

# ── Connection ───────────────────────────────────────────────────────────────

func host_game(port: int = 7777, max_players: int = 4) -> bool:
	"""Host a game. Returns true on success."""
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, max_players)
	if err != OK:
		GameLogger.error("Failed to create server: %s" % error_string(err), "Network")
		return false
	
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_online = true
	peer_id = 1
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	GameLogger.info("Hosting on port %d" % port, "Network")
	return true


func join_game(address: String = "localhost", port: int = 7777) -> bool:
	"""Join an existing game. Returns true on connection attempt start."""
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(address, port)
	if err != OK:
		GameLogger.error("Failed to connect: %s" % error_string(err), "Network")
		return false
	
	multiplayer.multiplayer_peer = peer
	is_host = false
	is_online = true
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	
	GameLogger.info("Connecting to %s:%d" % [address, port], "Network")
	return true


func disconnect_game() -> void:
	multiplayer.multiplayer_peer = null
	is_online = false
	connected_peers.clear()
	GameLogger.info("Disconnected", "Network")


# ── Game Actions ─────────────────────────────────────────────────────────────

## Send a game action to all peers (or to server if client).
func send_action(action: Dictionary) -> void:
	if not is_online:
		return
	_receive_action.rpc(action)


@rpc("any_peer", "reliable")
func _receive_action(action: Dictionary) -> void:
	"""Called on all peers when an action is received."""
	game_action_received.emit(action)


# ── Callbacks ────────────────────────────────────────────────────────────────

func _on_peer_connected(id: int) -> void:
	connected_peers.append(id)
	player_connected.emit(id)
	GameLogger.info("Peer connected: %d" % id, "Network")


func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	player_disconnected.emit(id)
	GameLogger.info("Peer disconnected: %d" % id, "Network")


func _on_connected_to_server() -> void:
	peer_id = multiplayer.get_unique_id()
	GameLogger.info("Connected to server as peer %d" % peer_id, "Network")
