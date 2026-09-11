extends Node

const SERVER_PORT: int = 7777

var peer: MultiplayerPeer

var ip_address: String = "localhost"
var port: int = 7777
var room_code: String = ""

var is_online: bool = false
var is_server: bool = false
var is_dedicated_server: bool = false

func set_local_online_status(value_online: bool, value_server: bool) -> void:
	is_online = value_online
	is_server = value_server
	if is_online and is_server: SessionManager.turn_local_to_online_profile()
	UIManager.toggle_admin_options(value_server)
	UIManager.update_online_status()

func print_local(text: String) -> void:
	#print(text)
	ChatManager.process_message(text, "global", 0)

func print_error(text: String) -> void:
	ChatManager.process_message(text, "shell_error", 0)
	push_error(text)
	printerr(text)
	print_debug()

func master_enter_tree() -> void:
	if OS.has_feature("server") or DisplayServer.get_name() == "headless":
		is_dedicated_server = true
	if is_dedicated_server: start_server()
	else: set_local_online_status(false, false)

func _enter_tree() -> void:
	multiplayer.peer_connected.connect(peer_connected)
	multiplayer.peer_disconnected.connect(peer_disconnected)
	multiplayer.connected_to_server.connect(connected_to_server)
	multiplayer.connection_failed.connect(connection_failed)
	multiplayer.server_disconnected.connect(server_disconnected)

## client-side ping: measure RTT to the server, report it back, server shares it
const PING_INTERVAL: float = 5.0
var ping_clock: float = 0.0

func _process(delta: float) -> void:
	if not is_online or is_dedicated_server or multiplayer.is_server(): return
	ping_clock -= delta
	if ping_clock > 0.0: return
	ping_clock = PING_INTERVAL
	ping_probe.rpc_id(1, Time.get_ticks_msec())

@rpc("any_peer", "unreliable", "call_local")
func ping_probe(sent_msec: int) -> void:
	if not multiplayer.is_server(): return
	pong_probe.rpc_id(multiplayer.get_remote_sender_id(), sent_msec)

@rpc("authority", "unreliable", "call_local")
func pong_probe(sent_msec: int) -> void:
	if multiplayer.is_server(): return
	var rtt: int = Time.get_ticks_msec() - sent_msec
	report_ping.rpc_id(1, rtt)

@rpc("any_peer", "unreliable")
func report_ping(rtt: int) -> void:
	if not multiplayer.is_server(): return
	var sid: int = multiplayer.get_remote_sender_id()
	if not SessionManager.data.has(sid): return
	SessionManager.data[sid]["ping"] = rtt
	SessionManager.update_registry.rpc(SessionManager.data)

func setup_websocket_no_delay() -> void:
	if not multiplayer.multiplayer_peer: return
	multiplayer.multiplayer_peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED

func get_server_port() -> int:
	var env_port: String = OS.get_environment("BL_PORT")
	if not env_port.is_empty(): return int(env_port)
	return SERVER_PORT

const WS_BUFFER_SIZE: int = 4 * 1024 * 1024

func start_server() -> void:
	if is_online: return
	var ws_peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	ws_peer.inbound_buffer_size = WS_BUFFER_SIZE
	ws_peer.outbound_buffer_size = WS_BUFFER_SIZE
	var error: Error = ws_peer.create_server(get_server_port())
	if error != OK:
		print_error("NETWORK ERROR: cannot host: " + str(error))
		return
	peer = ws_peer
	IngameManager.current_is_animated_generation = true
	multiplayer.set_multiplayer_peer(peer)
	setup_websocket_no_delay()
	print_local("Server is up! Waiting for players...")
	set_local_online_status(true, true)

func get_connect_url() -> String:
	if OS.has_feature("web"):
		var location: Variant = JavaScriptBridge.get_interface("location")
		if location == null: return ""
		if room_code.is_empty(): return ""
		var proto: String = "wss"
		if String(location.protocol) == "http:": proto = "ws"
		return proto + "://" + String(location.host) + "/ws/" + room_code
	return "ws://" + ip_address + ":" + str(port)

func start_client() -> void:
	if is_online: return
	print_local("Connecting to server...")
	var target_url: String = get_connect_url()
	print_local("URL: " + target_url)
	if target_url.is_empty():
		print_error("NETWORK ERROR: no room selected")
		return
	var ws_peer: WebSocketMultiplayerPeer = WebSocketMultiplayerPeer.new()
	ws_peer.inbound_buffer_size = WS_BUFFER_SIZE
	ws_peer.outbound_buffer_size = WS_BUFFER_SIZE
	var error: Error = ws_peer.create_client(target_url)
	if error != OK:
		print_error("NETWORK ERROR: connection failed: " + str(error))
		return
	peer = ws_peer
	IngameManager.current_is_animated_generation = false
	multiplayer.set_multiplayer_peer(peer)
	setup_websocket_no_delay()
	set_local_online_status(true, false)

func peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server(): return
	print("BLTRACE peer_connected pid=", peer_id)
	var encoded_pid: String = SessionManager.encode_session_id(peer_id)
	ConsoleManager.print_output("Player connected with peer id = " + encoded_pid, "global", peer_id)
	MasterManager.play_server_sound(MasterManager.sounds.get_node(^"PlayerJoin"))
	if IngameManager.current_state == IngameManager.State.STOPPED:
		IngameManager.set_maze_animation_to_true.rpc_id(peer_id)
	else: UIManager.confirm_spectating.rpc_id(peer_id)

func peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server(): return
	print("BLTRACE peer_disconnected pid=", peer_id)
	var encoded_pid: String = SessionManager.encode_session_id(peer_id)
	ConsoleManager.print_output("Player disconnected with peer id = " + encoded_pid, "global", peer_id)
	MasterManager.play_server_sound(MasterManager.sounds.get_node(^"PlayerLeave"))
	IngameManager.delete_player(peer_id)
	SessionManager.data.erase(peer_id)
	migrate_host_if_needed()
	UIManager.update_lobby_register()
	SessionManager.update_registry.rpc(SessionManager.data)

## when the room host (op) leaves, the earliest-joined remaining player takes over
func migrate_host_if_needed() -> void:
	if not is_dedicated_server: return
	var best_sid: int = 0
	for sid: int in SessionManager.data.keys():
		if sid <= 1: continue
		if SessionManager.data[sid].get("op") == true:
			return
		if best_sid == 0 or sid < best_sid: best_sid = sid
	if best_sid == 0: return
	SessionManager.set_local_op(best_sid, true)
	ConsoleManager.print_output("You are now the room host: the previous host left", "target", best_sid)
	ChatManager.process_message("Room host left: new host is " + SessionManager.data[best_sid].get("name", "unnamed"), "global", 0)

## called on clients
func connected_to_server() -> void:
	var encoded_pid: String = SessionManager.encode_session_id(multiplayer.get_unique_id())
	print_local("Successfully joined with peer id = " + encoded_pid)
	SessionManager.request_profile_update.rpc_id(1, SessionManager.profile_data)

## called on clients
func connection_failed() -> void:
	set_local_online_status(false, false)
	print_error("Connection failed")

## called on clients when the server drops the connection
func server_disconnected() -> void:
	if not is_online: return
	IngameManager.set_current_state(IngameManager.State.STOPPED)
	SessionManager.clear_registry()
	set_local_online_status(false, false)
	if UIManager.is_ui_configured:
		UIManager.lobby_node.activate(true)
	print_local("Disconnected from the room")

@rpc("authority", "reliable")
func notify_room_closed(reason: String) -> void:
	if multiplayer.is_server(): return
	print_local(reason)

@rpc("any_peer", "reliable")
func request_close_room() -> void:
	if not multiplayer.is_server(): return
	if not is_dedicated_server: return
	var pid: int = multiplayer.get_remote_sender_id()
	if not SessionManager.is_op(pid):
		print_error("NETWORK ERROR: close_room denied, not the room host")
		return
	print_local("Closing this room...")
	notify_room_closed.rpc("Room was closed by the room admin")
	await get_tree().create_timer(0.4).timeout
	get_tree().quit()

func disconnect_client(peer_id: int) -> void:
	if not multiplayer.is_server(): return
	var encoded_pid: String = SessionManager.encode_session_id(peer_id)
	if peer_id <= 1:
		print_error("NETWORK ERROR: can't disconnect client with id " + encoded_pid + ": should be > 1")
		return
	var target_peer: WebSocketMultiplayerPeer = multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if not target_peer:
		print_error("NETWORK ERROR: can't disconnect client with id " + encoded_pid + ": null peer object")
		return
	if target_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		print_error("NETWORK ERROR: can't disconnect client with id " + encoded_pid + ": already disconnected")
		return
	set_local_online_status.rpc_id(peer_id, false, false)
	target_peer.disconnect_peer(peer_id)
	print_local("Kicked peer with id " + encoded_pid)

func disconnect_from_server() -> void:
	if multiplayer.is_server(): return
	SessionManager.clear_registry()
	await get_tree().process_frame
	multiplayer.multiplayer_peer.close()
	IngameManager.set_current_state(IngameManager.State.STOPPED)
	set_local_online_status(false, false)
	ChatManager.process_message("Successfully disconnected from server", "global", 0)

func close_server() -> void:
	if not is_online: return
	if not multiplayer.is_server(): return
	print_local("Shutting down server...")
	IngameManager.end_ingame(true)
	#await get_tree().create_timer(1.0).timeout
	if multiplayer.get_peers().size() > 0:
		notify_server_shutdown.rpc()
		await get_tree().create_timer(0.2).timeout
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	SessionManager.clear_registry()
	set_local_online_status(false, false)
	print_local("Server successfully closed: local machine is no longer a server")

@rpc("authority", "reliable")
func notify_server_shutdown() -> void:
	if multiplayer.is_server(): return
	SessionManager.clear_registry()
	set_local_online_status(false, false)
	print_local("Server is closing")
	
