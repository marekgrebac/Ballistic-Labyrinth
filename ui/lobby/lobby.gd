extends CanvasLayer

const LOBBY_WIDGET_FILE: String = "res://ui/lobby/lobby_widget.tscn"

const EXIT_SERVER_LABEL: String = "Leave Room"
const CLOSE_ROOM_CONFIRM: String = "Close this room and disconnect all players?"
const EXIT_GAME_LABEL: String = "Exit Game"
const CLOSE_SERVER_LABEL: String = "Close Server"
const EXIT_SERVER_CONFIRM: String = "Are you sure you want to leave the server?"
const EXIT_GAME_CONFIRM: String = "Are you sure you want to exit the game?"
const CLOSE_SERVER_CONFIRM: String = "Are you sure you want to close this server?"

func toggle_spectate_window(value: bool) -> void:
	if value == false:
		$SpectateWindow.visible = false
		return
	$SpectateWindow/Animation.play(&"spectate_window")

func update_lobby_register() -> void:
	refresh_join_controls()
	if not NetworkManager.is_online:
		for lobby_widget: Node in %SessionsList.get_children():
			lobby_widget.queue_free()
		return
	var sid_ui: int
	var temp_registry: Dictionary = SessionManager.data.duplicate(true)
	for lobby_widget: Node in %SessionsList.get_children():
		sid_ui = lobby_widget.get_session_id()
		if sid_ui == 0:
			lobby_widget.queue_free()
			continue
		if temp_registry.has(sid_ui):
			lobby_widget.update(sid_ui)
			temp_registry.erase(sid_ui)
		else: lobby_widget.queue_free()
	for profile_key: int in temp_registry.keys():
		create_lobby_widget(profile_key)

func create_lobby_widget(profile_key: int) -> void:
	if profile_key == 0 and NetworkManager.is_online: return
	var lobby_widget: Control = load(LOBBY_WIDGET_FILE).instantiate()
	lobby_widget.update(profile_key)
	%SessionsList.add_child(lobby_widget)

func update_online_status() -> void:
	is_connecting = false
	if UIManager.chat_menu_node != null:
		UIManager.chat_menu_node.visible = NetworkManager.is_online
	if not NetworkManager.is_online:
		%LeaveGameButton.text = EXIT_GAME_LABEL
		%ConfirmLeaveGameTitle.text = EXIT_GAME_CONFIRM
		update_lobby_register()
	elif not NetworkManager.is_server:
		%LeaveGameButton.text = EXIT_SERVER_LABEL
		%ConfirmLeaveGameTitle.text = EXIT_SERVER_CONFIRM
	else:
		%LeaveGameButton.text = CLOSE_SERVER_LABEL
		%ConfirmLeaveGameTitle.text = CLOSE_SERVER_CONFIRM
		oneshot_update_lobby_register()
	refresh_join_controls()

func oneshot_update_lobby_register() -> void:
	if NetworkManager.is_online and multiplayer.is_server():
		if %SessionsList.get_child_count() == 0:
			create_lobby_widget(1)
			return
		%SessionsList.get_child(0).update(1)
		return

func write_version_text() -> void:
	$Frame/Version.text = "Version " + ProjectSettings.get_setting("application/config/version")

func activate(value: bool) -> void:
	unfocus()
	visible = value
	$SpectateWindow.visible = false
	if IngameManager.current_state != IngameManager.State.STOPPED: return
	if value and MasterManager.is_soundtrack_enabled: $Soundtrack.play()
	else: $Soundtrack.stop()

func unfocus() -> void:
	$Background.focus_mode = Control.FOCUS_ALL
	$Background.grab_focus()
	$Background.focus_mode = Control.FOCUS_NONE

var is_closing_room: bool = false

func _on_confirm_button_pressed() -> void:
	unfocus()
	$ExitConfirmDialog.visible = false
	if is_closing_room:
		is_closing_room = false
		NetworkManager.request_close_room.rpc_id(1)
		await get_tree().create_timer(1.0).timeout
		if NetworkManager.is_online:
			NetworkManager.disconnect_from_server()
		return
	if not NetworkManager.is_online:
		get_tree().quit()
	elif not multiplayer.is_server():
		NetworkManager.disconnect_from_server()
	else:
		NetworkManager.close_server()

func _on_discard_button_pressed() -> void:
	unfocus()
	$ExitConfirmDialog.visible = false

func _on_exit_game_button_pressed() -> void:
	unfocus()
	is_closing_room = false
	%ConfirmLeaveGameTitle.text = EXIT_SERVER_CONFIRM
	$ExitConfirmDialog.visible = true

func _on_close_room_button_pressed() -> void:
	unfocus()
	is_closing_room = true
	%ConfirmLeaveGameTitle.text = CLOSE_ROOM_CONFIRM
	$ExitConfirmDialog.visible = true

func _on_username_edit_text_submitted(new_text: String) -> void:
	var username: String = new_text.strip_edges()
	%UsernameEdit.text = username
	SessionManager.set_profile_name(username)

func _on_username_edit_text_changed(new_text: String) -> void:
	SessionManager.set_profile_name(new_text.strip_edges())

func _on_player_color_picker_color_changed(color: Color) -> void:
	%PlayerColorTest.modulate = color
	SessionManager.set_profile_color(color)

var is_connecting: bool = false

func refresh_join_controls() -> void:
	var online: bool = NetworkManager.is_online
	var my_id: int = multiplayer.get_unique_id()
	var me_registered: bool = online and SessionManager.data.has(my_id)
	%JoinButton.visible = not online
	%JoinButton.disabled = is_connecting
	%CreateRoomButton.visible = not online
	%CreateRoomButton.disabled = is_connecting
	%RoomIdInput.editable = not online
	%StartGameButton.visible = me_registered and SessionManager.is_op(my_id)
	%LeaveGameButton.visible = online
	%CloseRoomButton.visible = me_registered and SessionManager.is_op(my_id)
	%HelpPanel.visible = not online
	$Frame/TextureRect.self_modulate.a = 0.54901963 if online else 0.0

func _on_join_button_pressed() -> void:
	var code: String = %RoomIdInput.text.strip_edges().to_upper()
	if code.is_empty():
		ChatManager.process_message("Enter a ROOM ID, or press Create Room", "global", 0)
		return
	if is_connecting: return
	if not OS.has_feature("web"):
		NetworkManager.room_code = code
		NetworkManager.start_client()
		return
	pending_join_code = code
	is_connecting = true
	refresh_join_controls()
	room_http.request(api_url("/api/rooms/" + code))

func _on_create_room_button_pressed() -> void:
	if is_connecting or NetworkManager.is_online: return
	if not OS.has_feature("web"):
		ChatManager.process_message("Create Room works only in the web app", "global", 0)
		return
	is_connecting = true
	refresh_join_controls()
	ChatManager.process_message("Creating room...", "global", 0)
	var target: String = api_url("/api/rooms")
	var req_error: Error = room_http.request(target, PackedStringArray(), HTTPClient.METHOD_POST, "")
	if req_error != OK: fail_connect("Cannot create room (request failed: " + str(req_error) + ")")

func _on_start_game_button_pressed() -> void:
	IngameManager.start_game.rpc_id(1)

var room_http: HTTPRequest = null
var pending_join_code: String = ""

func api_url(path: String) -> String:
	var location: Variant = JavaScriptBridge.get_interface("location")
	if location == null: return path
	return String(location.protocol) + "//" + String(location.host) + path

func _ready() -> void:
	room_http = HTTPRequest.new()
	room_http.timeout = 10.0
	add_child(room_http)
	room_http.request_completed.connect(_on_room_http_completed)
	refresh_join_controls()
	if OS.has_feature("web"):
		var location: Variant = JavaScriptBridge.get_interface("location")
		if location != null:
			var search: String = String(location.search)
			var room_match: RegEx = RegEx.new()
			room_match.compile("[?&]room=([A-Za-z0-9]{4,12})")
			var found: RegExMatch = room_match.search(search)
			if found != null:
				var code: String = found.get_string(1).to_upper()
				%RoomIdInput.text = code
				NetworkManager.room_code = code
				_on_join_button_pressed.call_deferred()

func fail_connect(message: String) -> void:
	is_connecting = false
	pending_join_code = ""
	refresh_join_controls()
	%RoomIdInput.placeholder_text = message
	ChatManager.process_message(message, "global", 0)

func _on_room_http_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not pending_join_code.is_empty():
		var code: String = pending_join_code
		pending_join_code = ""
		if response_code == 200:
			NetworkManager.room_code = code
			NetworkManager.start_client()
		else: fail_connect("Room not found: " + code)
		return
	if response_code != 201:
		fail_connect("Cannot create room (server error " + str(response_code) + ")")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("code"):
		fail_connect("Cannot create room (bad response)")
		return
	var code: String = String(parsed["code"])
	%RoomIdInput.text = code
	NetworkManager.room_code = code
	NetworkManager.start_client()

func _on_toggle_soundtrack_toggled(toggled_on: bool) -> void:
	MasterManager.toggle_soundtrack(not toggled_on)
	if MasterManager.is_soundtrack_enabled: $Soundtrack.play()

func _on_room_id_input_text_changed(new_text: String) -> void:
	NetworkManager.room_code = new_text.strip_edges().to_upper()

func _on_room_id_input_text_submitted(_new_text: String) -> void:
	_on_join_button_pressed()
