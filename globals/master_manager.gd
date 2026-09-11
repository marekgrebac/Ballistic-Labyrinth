extends Node

const AWAIT_INTERRUPT_CHECK_INTERVAL: float = 0.05
var is_await_interrupted: bool = false
## if returning false, it should stop the function it's called in using return keyword
## if returning true, parent function proceeds normally after timer
## one-liner use: "if not await await_interrupt(seconds): return"
func await_interrupt(duration_seconds: float) -> bool:
	var elapsed: float = 0.0
	while elapsed < duration_seconds:
		if is_await_interrupted:
			is_await_interrupted = false
			return false
		await get_tree().create_timer(AWAIT_INTERRUPT_CHECK_INTERVAL).timeout
	return true

func _enter_tree() -> void:
	instantiate_audio_container()
	NetworkManager.master_enter_tree()
	SessionManager.master_enter_tree()
	UIManager.master_enter_tree()

var sounds: Node = null
const AUDIO_CONTAINER_PATH: String = "res://globals/audio_container.tscn"
func instantiate_audio_container() -> void:
	sounds = load(AUDIO_CONTAINER_PATH).instantiate()
	add_child(sounds)

var is_soundtrack_enabled: bool = true
func toggle_soundtrack(is_enabled: bool) -> void:
	if not UIManager.is_ui_configured: return
	is_soundtrack_enabled = is_enabled
	if not is_enabled: UIManager.lobby_node.get_node(^"Soundtrack").stop()

func play_server_sound(player: Node, pid: int = 0) -> void:
	## NodePath args couple RPC encoding with the scene cache; send plain strings
	if not multiplayer.is_server():
		receive_server_sound(String(player.get_path()))
		return
	if pid < 0: return
	if pid == 0: receive_server_sound.rpc(String(player.get_path()))
	else: receive_server_sound.rpc_id(pid, String(player.get_path()))

@rpc("authority", "unreliable", "call_local")
func receive_server_sound(player_path: String) -> void:
	var player = get_node_or_null(NodePath(player_path))
	if not player:
		push_error("CUSTOM ERROR: can't play server sound: null audio player path")
		return
	if player.has_method("play"): player.play()

@rpc("any_peer", "reliable", "call_local")
func set_pause(is_paused: bool) -> void:
	var pid: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server():
		if pid != 1: return
		get_tree().paused = is_paused
		if not UIManager.is_ui_configured: return
		UIManager.lobby_node.unfocus()
		var is_admin: bool = SessionManager.is_op(multiplayer.get_unique_id())
		UIManager.pause_menu_node.toggle_admin_options(is_admin)
		UIManager.pause_menu_node.visible = is_paused
		return
	if not SessionManager.is_op(pid): return
	if IngameManager.current_state == IngameManager.State.STOPPED: return
	get_tree().paused = is_paused
	if UIManager.is_ui_configured:
		UIManager.lobby_node.unfocus()
		UIManager.pause_menu_node.visible = is_paused
	for send: int in multiplayer.get_peers():
		if send <= 1: return
		set_pause.rpc_id(send, is_paused)
