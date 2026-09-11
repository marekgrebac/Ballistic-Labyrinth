extends Node

var chat_history: Array[Dictionary] = []
var MAX_HISTORY: int = 100

signal remove_previous_message
@rpc("authority", "reliable", "call_local")
func remove_previous_local_message() -> void:
	if NetworkManager.is_dedicated_server: return
	chat_history.pop_back()
	remove_previous_message.emit()

func send_local_message(text: String, channel: String) -> void:
	process_message(text, channel, 0)

func send_message(text: String, channel: String, target_pid: int) -> void:
	if not NetworkManager.is_online: process_message(text, channel, target_pid)
	else: process_message.rpc_id(1, text, channel, target_pid)

@rpc("authority", "reliable", "call_local")
func update_chat_history(new_message: Dictionary) -> void:
	chat_history.append(new_message)
	while chat_history.size() > MAX_HISTORY:
		chat_history.pop_front()
	var new_array: Array[Dictionary] = [new_message]
	if NetworkManager.is_dedicated_server: ConsoleManager.dedicated_server_print(new_message)
	else: update_local_chat_ui.emit(new_array)

## CHANNELS
## --- shell_input: input command(only for configured chat menu UI, sent only locally)
## --- shell_output: regular shell output(sent only for executing peer)
## --- shell_error: error messages for commands(sent only for executing peer)
## --- target: command outputs that target a specific peer id different than executing peer(eg: admin grant/revoke)
## --- admin: staff only output messages
## --- peer: regular messages sent by peers
## --- global: system messages sent to everyone, excepting provided pid if pid > 0
signal update_local_chat_ui(messages: Array[Dictionary])
@rpc("any_peer", "reliable", "call_local")
func process_message(text: String, channel: String, target_pid: int) -> void:
	if target_pid < 0: return
	var sender_id: int
	if not multiplayer: sender_id = 0
	else: sender_id = multiplayer.get_remote_sender_id()
	if SessionManager.is_muted(sender_id): return
	var final_text: String = text.strip_edges()
	var message: Dictionary = {}
	var new_array: Array[Dictionary] = []
	if sender_id == 0 or target_pid == 1:
		message = {
			"sender_sid": sender_id,
			"sender_name": SessionManager.profile_data.get("name"),
			"text": final_text,
			"timestamp": Time.get_time_string_from_unix_time(int(Time.get_unix_time_from_system())),
			"channel": channel
		}
		chat_history.append(message)
		while chat_history.size() > MAX_HISTORY:
			chat_history.pop_front()
		new_array.append(message)
		if NetworkManager.is_dedicated_server: ConsoleManager.dedicated_server_print(message)
		else: update_local_chat_ui.emit(new_array)
		return
	if not multiplayer.is_server(): return
	var sender_name: String = ""
	if SessionManager.data.has(sender_id): sender_name = SessionManager.data.get(sender_id).get("name")
	message = {
		"sender_sid": sender_id,
		"sender_name": sender_name,
		"text": final_text,
		"timestamp": Time.get_time_string_from_unix_time(int(Time.get_unix_time_from_system())),
		"channel": channel
	}
	if channel in PID_EXCLUSIVE_CHANNELS:
		if target_pid == 0: return
		update_chat_history.rpc_id(target_pid, message)
		return
	if channel == "admin":
		for admin_id: int in SessionManager.data.keys():
			if admin_id <= 0: continue
			if not SessionManager.is_admin(admin_id): continue
			update_chat_history.rpc_id(admin_id, message)
		return
	if channel == "peer" or channel == "global":
		if target_pid == 0: update_chat_history.rpc(message)
		else: update_chat_history.rpc_id(target_pid, message)
		return

const PID_EXCLUSIVE_CHANNELS: PackedStringArray = ["shell_output", "shell_error", "target"]
const GROUP_CHANNELS: PackedStringArray = ["admin", "global"]

## clears chat history and the visible chat window on every client
@rpc("authority", "reliable", "call_local")
func purge_chat() -> void:
	if multiplayer.is_server(): return
	chat_history.clear()
	remove_previous_message.emit()
