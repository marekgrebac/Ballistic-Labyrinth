extends Node

var registry: Array[Dictionary] = []

const ATTRIBUTE_ALIASES: Dictionary = {
	"name": ["name", "username", "user", "n", "u"],
	"admin": ["admin", "is_admin", "a"],
	"color": ["color", "colour", "rgb", "c"],
	"kills": ["kills", "kill", "k"],
	"score": ["score", "win", "wins", "s", "w"]
}

enum StaffAccess {
	ANY = 0,
	ADMIN = 1,
	OP = 2
}

## confirm("yes") command isn't registered and stores a command in a temporary buffer
func _enter_tree() -> void:
	register_command(
		["help"],
		"shows available commands",
		StaffAccess.ANY,
		true
	)
	register_command(
		["help_chat", "chat", "chat_help"],
		"shows shortcuts for adjusting chat window",
		StaffAccess.ANY,
		true
	)
	register_command(
		["help_controls"],
		"shows keybindings for moving the tank in the game",
		StaffAccess.ANY,
		true
	)
	register_command(
		["disconnect", "leave"],
		"leaves from the currently connected server",
		StaffAccess.ANY,
		true
	)
	register_command(
		["get"],
		"get attributes from yourself or a certain player",
		StaffAccess.ANY,
		true
	)
	register_command(
		["set"],
		"set one of your attributes to a specific value",
		StaffAccess.ANY,
		false
	)
	register_command(
		["assign"],
		"modify any attribute from any session except admin role",
		StaffAccess.OP,
		false
	)
	register_command(
		["bot", "ai"],
		"create or delete bots",
		StaffAccess.OP,
		false
	)
	register_command( # temporary quick configuration
		["chat_resize"],
		"resize chat text to a specific size",
		StaffAccess.ANY,
		true
	)
	register_command(
		["start_game", "play", "start"],
		"starts the game",
		StaffAccess.OP,
		false
	)
	register_command(
		["crate", "powerup", "weapon"],
		"general command for manipulating crates ingame",
		StaffAccess.OP,
		false
	)
	register_command(
		["maze", "maze_set", "maze_size", "maze_set_size", "set_maze_size"],
		"sets the maze's minimum and maximum random width and height: \"min_w, max_w, min_h, max_h\"",
		StaffAccess.OP,
		false
	)
	register_command(
		["close_ingame", "end_ingame", "close_game", "end_game"],
		"ends the currently playing game and gets everyone back to lobby",
		StaffAccess.OP,
		false
	)
	register_command(
		["restart_ingame", "restart_game", "restart"],
		"restarts the currently playing game",
		StaffAccess.OP,
		false
	)
	register_command(
		["get_sessions", "get_session", "get_sid", "get_s"],
		"get certain or all attributes from every session",
		StaffAccess.ANY,
		true
	)
	register_command(
		["pause", "p"],
		"pause/resume the ingame",
		StaffAccess.OP,
		false
	)
	register_command(
		["toggle_ingame_states", "toggle_ingame_state", "ingame_state"],
		"toggles displaying messages for dedicated server when ingame state changes",
		StaffAccess.OP,
		false
	)
	register_command(
		["op", "master"],
		"grants or revokes op for any peer, but it's passworded and successful assigns change the password",
		StaffAccess.ANY,
		false
	)
	register_command(
		["makehost", "host", "transfer_host"],
		"transfers room host to another player: makehost {username}",
		StaffAccess.OP,
		false
	)
	register_command(
		["purge", "clear_chat", "clearchat"],
		"clears the chat window and history for everyone in the room",
		StaffAccess.OP,
		false
	)
	register_command(
		["admin"],
		"grants or revokes admin for any peer",
		StaffAccess.OP,
		false
	)
	register_command(
		["bot_max", "max_bot"],
		"set max bot count",
		StaffAccess.OP,
		false
	)
	register_command(
		["crate_max", "max_crate"],
		"set max crate count",
		StaffAccess.OP,
		false
	)
	register_command(
		["maze_max", "max_maze"],
		"set max maze size",
		StaffAccess.OP,
		false
	)
	register_command(
		["mute"],
		"mute or unmute any peer except ops",
		StaffAccess.OP,
		false
	)

## first string in alias list corresponds with a callable's name(ex: "connect" corresponds with cmd_connect)
func register_command(
	aliases: PackedStringArray,
	description: String,
	staff_access: StaffAccess,
	is_local: bool) -> void:
	registry.append({
		"aliases": aliases,
		"description": description,
		"staff_access": staff_access,
		"is_local": is_local
	})

var input_thread: Thread
var input_thread_should_run: bool = true
func initialize_dedicated_server_console() -> void:
	input_thread = Thread.new()
	input_thread.start(listen_for_console_input)

## only works for Linux instances
func listen_for_console_input() -> void:
	while input_thread_should_run:
		var line := OS.read_string_from_stdin()
		if line.length() > 0:
			call_deferred("execute_raw_string", line)

func _exit_tree() -> void:
	input_thread_should_run = false
	if input_thread and input_thread.is_started():
		input_thread.wait_to_finish()

const NO_TIMESTAMP_CHANNELS: PackedStringArray = ["shell_input", "shell_error", "shell_output"]
func dedicated_server_print(message: Dictionary) -> void:
	if message.get("channel", "null") == "null": return
	if message.get("channel", "null") == "shell_input": return
	if message.get("channel", "null") == "peer": return
	var result_buffer: String = ""
	if not message.get("channel") in NO_TIMESTAMP_CHANNELS:
		result_buffer += str(message.get("timestamp")) + " "
	elif message.get("channel") == "shell_output":
		result_buffer += "/: "
	elif message.get("channel") == "shell_error":
		result_buffer += "E: "
	elif message.get("channel") == "admin":
		result_buffer += "ADMIN: "
	elif message.get("channel") == "target":
		result_buffer += "!!!: "
	elif message.get("channel") == "global":
		result_buffer += "***: "
	result_buffer += message.get("text")
	print(result_buffer)

func print_output(text: String, channel: String, pid: int) -> void:
	if pid < 0: return
	if channel == "peer": return
	if channel == "shell_input": pid = 0
	if pid == 0 and not channel in ChatManager.GROUP_CHANNELS:
		ChatManager.send_local_message(text, channel)
		return
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	if channel in ChatManager.PID_EXCLUSIVE_CHANNELS:
		if pid == 0: return
		ChatManager.send_message(text, channel, pid)
		return
	if channel == "global" and pid > 0:
		ChatManager.send_message(text, "global", 1)
		for peer: int in multiplayer.get_peers():
			if peer == pid: continue
			ChatManager.send_message(text, "global", peer)
		return
	ChatManager.send_message(text, channel, 0)

func split_respecting_quotes(text: String) -> Array[String]:
	var regex := RegEx.new()
	regex.compile('"[^"]*"|\'[^\']*\'|\\S+')
	var result: Array[String] = []
	for item in regex.search_all(text):
		result.append(item.get_string())
	return result

## if returning true, execute_raw_string stops, else it keeps going
const CONFIRM_COMMAND_STRING: String = "yes"
func invoked_needs_confirmation(invoked: String) -> bool:
	if not is_confirming_command: return false
	if invoked == CONFIRM_COMMAND_STRING:
		execute_cmd(confirmed_cmd, confirmed_args, confirmed_flags)
	else: print_output("command aborted", "shell_output", 0)
	is_confirming_command = false
	return true

func get_invoked_as_dictionary(invoked: String) -> Dictionary:
	var active_cmd: Dictionary = {}
	for cmd: Dictionary in registry:
		if invoked in cmd["aliases"]:
			active_cmd = cmd
			break
	if active_cmd.is_empty():
		print_output("command not found: " + invoked, "shell_error", 0)
		return {}
	return active_cmd

func is_admin_local_verify(invoked: String, active_cmd: Dictionary) -> bool:
	if active_cmd["staff_access"] == StaffAccess.ADMIN and not SessionManager.is_admin(multiplayer.get_unique_id()):
		print_output("command not found: " + invoked, "shell_error", 0)
		return false
	return true

func is_admin_server_verify(cmd: Dictionary, pid: int) -> bool:
	if not cmd in registry: return false
	if cmd["is_local"]: return false
	if cmd["staff_access"] == StaffAccess.ADMIN and not SessionManager.is_admin(pid): return false
	return true

func is_op_local_verify(invoked: String, active_cmd: Dictionary) -> bool:
	if active_cmd["staff_access"] == StaffAccess.OP and not SessionManager.is_op(multiplayer.get_unique_id()):
		print_output("command not found: " + invoked, "shell_error", 0)
		return false
	return true

func is_op_server_verify(cmd: Dictionary, pid: int) -> bool:
	if not cmd in registry: return false
	if cmd["is_local"]: return false
	if cmd["staff_access"] == StaffAccess.OP and not SessionManager.is_op(pid): return false
	return true

func get_flags_and_args_and_execute_cmd(tokens: PackedStringArray, active_cmd: Dictionary) -> void:
	var flags: Array[PackedStringArray] = []
	var args: PackedStringArray = []
	var is_previous_token_argument_flag: bool = false
	for token: String in tokens:
		if token.begins_with("\"") and token.ends_with("\""):
			token = token.trim_prefix("\"").trim_suffix("\"")
		if token.begins_with("-"):
			if is_previous_token_argument_flag:
				print_output("invalid flag syntax: expected argument after = flag", "shell_error", 0)
				return
			flags.append([token])
		elif token.begins_with("="):
			if is_previous_token_argument_flag:
				print_output("invalid flag syntax: expected argument after = flag", "shell_error", 0)
				return
			flags.append([token])
			is_previous_token_argument_flag = true
		elif is_previous_token_argument_flag: flags[-1].append(token)
		else: args.append(token)
	execute_cmd(active_cmd, args, flags)

func execute_raw_string(raw_text: String) -> void:
	var text: String = raw_text.strip_edges()
	if text.is_empty(): return
	if text.begins_with("/") and text.substr(1).is_empty(): return
	if UIManager.is_ui_configured: ChatManager.send_local_message(text, "shell_input")
	if text.begins_with("/"): text = text.substr(1)
	var tokens: PackedStringArray = split_respecting_quotes(text)
	var invoked: String = ""
	invoked = tokens[0]
	if invoked_needs_confirmation(invoked): return
	tokens.remove_at(0)
	var active_cmd: Dictionary = get_invoked_as_dictionary(invoked)
	if active_cmd.is_empty(): return
	if not is_admin_local_verify(invoked, active_cmd): return
	if not is_op_local_verify(invoked, active_cmd): return
	get_flags_and_args_and_execute_cmd(tokens, active_cmd)

func execute_cmd(cmd: Dictionary, args: PackedStringArray, flags: Array[PackedStringArray]) -> void:
	if cmd["is_local"]:
		Callable(self, "cmd_" + cmd["aliases"][0]).call(args, flags, 0)
		return
	if not NetworkManager.is_online: return
	request_network_cmd.rpc_id(1, cmd, args, flags)

@rpc("any_peer", "reliable", "call_local")
func request_network_cmd(cmd: Dictionary, args: PackedStringArray, flags: Array[PackedStringArray]) -> void:
	var pid: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server(): return
	if not is_admin_server_verify(cmd, pid): return
	if not is_op_server_verify(cmd, pid): return
	Callable(self, "cmd_" + cmd["aliases"][0]).call(args, flags, pid)

var is_confirming_command: bool = false
var confirmed_cmd: Dictionary = {}
var confirmed_args: PackedStringArray = []
var confirmed_flags: Array[PackedStringArray] = []
func confirm_cmd(cmd: Dictionary, args: PackedStringArray, flags: Array[PackedStringArray], pid: int = 0) -> void:
	is_confirming_command = true
	print_output(
		"are you sure you want to execute this command? " + cmd["aliases"][0] + "\n" +
		"use the \"yes\" command to confirm or cancel by typing a dummy command(one / suffices)\n",
		"target", pid
	)
	confirmed_cmd = cmd
	confirmed_args = args
	confirmed_flags = flags

## wrapper function for commands that require confirmation
## to make a command cmd_foo confirm-only, this line is appended right before the actual
## command execution in the function body:
## if not is_cmd_confirmed(cmd_foo, args, flags): return
func is_cmd_confirmed(callback: Callable, args: PackedStringArray, flags: Array[PackedStringArray], pid: int = 0) -> bool:
	if is_confirming_command:
		is_confirming_command = false
		return true
	for cmd: Dictionary in registry:
		if "cmd_" + cmd["aliases"][0] != callback.get_method(): continue
		confirm_cmd(cmd, args, flags, pid)
		return false
	return false

## if y entry is < 0, then x entry refers to a number of SIDs(no specific SIDs)
## if y entry is = 0, then x entry refers to a target SID
## if y entry is = 1, then it's a silent exception
## if y entry is > 2, then it prints the exception
func get_session_reference_from_flags(flags: Array[PackedStringArray], pid: int = 0) -> Vector2i:
	var result: int = multiplayer.get_unique_id()
	const COUNT_FLAGS = ["=c", "==count", "==num", "==number"]
	const SID_FLAGS = ["=s", "==sid"]
	const NAME_FLAGS = ["=u", "==username", "=n", "==name"]
	for flag: PackedStringArray in flags:
		if not flag[0] in COUNT_FLAGS and not flag[0] in SID_FLAGS and not flag[0] in NAME_FLAGS: continue
		if flag[0] in COUNT_FLAGS:
			if flag.size() <= 1:
				print_output("provide a count integer to ==count", "shell_error", pid)
				return Vector2i(2, 2)
			result = abs(int(flag[1]))
			result = min(result, SessionManager.data.size())
			return Vector2i(result, -1)
		if flag[0] in SID_FLAGS:
			if flag.size() <= 1:
				print_output("provide an sid to ==sid to filter session ids", "shell_error", pid)
				return Vector2i(2, 2)
			result = SessionManager.decode_session_id(flag[1])
			if not result in SessionManager.data.keys():
				print_output("session with ID = " + flag[1] + " doesn't exist", "shell_error", pid)
				return Vector2i(2, 2)
			return Vector2i(result, 0)
		# flag[0] in NAME_FLAGS:
		if flag.size() <= 1:
			print_output("provide a name to ==name to filter session ids", "shell_error", pid)
			return Vector2i(2, 2)
		var match_count: int = 0
		for key: int in SessionManager.data.keys():
			if match_count == 1 and key == 0: continue
			if SessionManager.data[key].get("name") != flag[1]: continue
			result = key
			match_count += 1
			if match_count >= 2: break
		if match_count == 0:
			print_output("session with name = " + flag[1] + " doesn't exist", "shell_error", pid)
			return Vector2i(2, 2)
		if match_count > 1:
			print_output("multiple sessions have the same name, consider filtering by sid", "shell_error", pid)
			return Vector2i(2, 2)
		return Vector2i(result, 0)
	return Vector2i(1, 1)

func get_printed_session(sid: int) -> String:
	if sid == 0: return ""
	if not sid in SessionManager.data.keys(): return ""
	var result: String = " " + str(SessionManager.encode_session_id(sid))
	result += ":\n"
	result += str(SessionManager.data[sid])
	return result

func cmd_help(args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	var command_list: String = ""
	var is_pid_admin: bool = SessionManager.is_admin(multiplayer.get_unique_id())
	var is_pid_op: bool = SessionManager.is_op(multiplayer.get_unique_id())
	if args.is_empty():
		for command: Dictionary in registry:
			if not NetworkManager.is_online and command["aliases"][0] != "connect": continue
			if command["aliases"][0] == "op": continue
			if command["staff_access"] == StaffAccess.ADMIN and not is_pid_admin: continue
			if command["staff_access"] == StaffAccess.OP and not is_pid_op: continue
			var length: int = command["aliases"].size()
			var index: int = 0
			for alias: String in command["aliases"]:
				if index == length - 1: command_list += alias
				else: command_list += alias + "/"
				index += 1
			command_list += ": " + command["description"] + "\n"
		print_output(command_list, "shell_output", 0)
		return
	for command: Dictionary in registry:
		if not args[0] in command["aliases"]: continue
		var length: int = command["aliases"].size()
		var index: int = 0
		for alias: String in command["aliases"]:
			if index == length - 1: command_list += alias
			else: command_list += alias + "/"
			index += 1
		command_list += ": " + command["description"] + "\n"
		print_output(command_list, "shell_output", 0)
		return
	print_output("command not found: " + args[0], "shell_error", 0)

func cmd_disconnect(args: PackedStringArray, flags: Array[PackedStringArray], _pid: int) -> void:
	if not NetworkManager.is_online:
		print_output("already offline/disconnected", "shell_error", 0)
		return
	if multiplayer.is_server():
		print_output("can't disconnect with this command: only the room's server process may stop it", "shell_error", 0)
		return
	if not is_cmd_confirmed(cmd_disconnect, args, flags): return
	NetworkManager.disconnect_from_server()

func cmd_get(args: PackedStringArray, flags: Array[PackedStringArray], _pid: int) -> void:
	if args.is_empty():
		print_output("usage: get PROPERTY [SID/=s SID/=u NAME]", "shell_output", 0)
		return
	var target_sid: int = 0
	if NetworkManager.is_online: target_sid = multiplayer.get_unique_id()
	if flags.is_empty():
		if args.size() > 1: target_sid = SessionManager.decode_session_id(args[1])
	else:
		var filter: Vector2i = get_session_reference_from_flags(flags)
		if filter[1] >= 2: return
		if filter[1] == 1: target_sid = multiplayer.get_unique_id()
		if filter[1] == 0: target_sid = filter[0]
		if filter[1] < 0:
			print_output("can't get attributes from a bulk number", "shell_error", 0)
			return
	for key: PackedStringArray in ATTRIBUTE_ALIASES.values():
		if not args[0] in key: continue
		var session_entry: Dictionary = SessionManager.data[target_sid]
		var result: String
		if key[0] == "color":
			result = SessionManager.color_to_string(session_entry.get(key[0]))
		else: result = str(session_entry.get(key[0]))
		print_output(key[0] + ": " + result, "shell_output", 0)
		return
	if not args[0] in CMD_GET_SESSION: return
	print_output(get_printed_session(target_sid), "shell_output", 0)

const CMD_GET_SESSION := ["session", "register"]

func cmd_set(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if not multiplayer.is_server(): return
	if NetworkManager.is_dedicated_server:
		print_output("dedicated server doesn't have a session", "shell_error", pid)
		return
	if args.is_empty():
		print_output("usage: set PROPERTY VALUE", "shell_output", pid)
		return
	if args.size() < 2:
		print_output("provide a value to set your attribute to", "shell_output", pid)
		return
	var property: String = ""
	for value: PackedStringArray in ATTRIBUTE_ALIASES.values():
		if not args[0] in value: continue
		property = value[0]
		break
	if property.is_empty():
		print_output("nonexistent attribute " + args[0], "shell_error", pid)
		return
	const PROHIBITED = ["admin", "kills", "score"]
	if property in PROHIBITED:
		print_output("nonexistent attribute " + args[0], "shell_error", pid)
		return
	SessionManager.assign_from_str(pid, args[0], args[1])

func cmd_assign(args: PackedStringArray, flags: Array[PackedStringArray], pid: int) -> void:
	if not multiplayer.is_server(): return
	if args.size() < 2:
		print_output("usage: assign PROPERTY VALUE [=s/==sid SID / =n/==name NAME]", "shell_output", pid)
		return
	var property: String = ""
	for key: PackedStringArray in ATTRIBUTE_ALIASES.values():
		if not args[0] in key: continue
		property = key[0]
		break
	if property.is_empty():
		print_output("nonexistent attribute " + args[0], "shell_error", pid)
		return
	if property == "admin":
		print_output("can't modify admin permissions with assign", "shell_error", pid)
		return
	var target_sid: int = 0
	var filter: Vector2i = get_session_reference_from_flags(flags, pid)
	if filter[1] >= 2: return
	if filter[1] == 1: target_sid = pid
	if filter[1] == 0: target_sid = filter[0]
	if filter[1] < 0:
		print_output("can't get attributes from a bulk number", "shell_error", pid)
		return
	if filter[1] == 1: target_sid = multiplayer.get_unique_id()
	if target_sid == 1 and NetworkManager.is_dedicated_server:
		print_output("dedicated server doesn't have a session", "shell_error", pid)
		return
	if target_sid <= 0 and property == "personality":
		print_output("can't change bot personality using the assign command", "shell_error", pid)
		return
	SessionManager.assign_from_str(target_sid, args[0], args[1])

func cmd_bot(args: PackedStringArray, flags: Array[PackedStringArray], pid: int) -> void:
	if not multiplayer.is_server(): return
	if args.is_empty():
		print_output(
			"usage: bot {add [COUNT]}/{delete =s/=c/=n SID/COUNT/NAME}/{set =s/=n SID/NAME \"trait\" VALUE}/{enable}/{disable}/{random}",
			"shell_output", pid)
		return
	const ALIASES_1 := ["add", "create"]
	const ALIASES_2 := ["remove", "delete", "erase"]
	const ALIASES_3 := ["set", "assign", "set_personality", "assign_personality", "set_trait", "assign_trait", "trait"]
	const ALIASES_4 := ["enable", "on", "activate", "turn_on"]
	const ALIASES_5 := ["disable", "off", "deactivate", "turn_off"]
	const ALIASES_6 := ["random", "randomise", "randomize", "rand", "rng", "generate"]
	if args[0] in ALIASES_1: # BOT add ...
		var count1: int = 1
		if args.size() >= 2: count1 = abs(int(args[1])) # BOT add 1 [2] [3] [4] ...
		SessionManager.add_bot.rpc(count1)
		return
	elif args[0] in ALIASES_2: # BOT remove ...
		var filter: Vector2i = get_session_reference_from_flags(flags, pid)
		if filter[1] >= 2: return
		if filter[1] == 1:
			print_output("usage: bot delete =s/=c/=n SID/COUNT/NAME", "shell_output", pid)
			return
		if filter[1] == 0:
			var sid: int = filter[0]
			sid = -abs(sid)
			SessionManager.remove_bot_sid.rpc(sid)
			return
		if filter[1] == -1:
			SessionManager.remove_bot_count.rpc(filter[0])
			return
	elif args[0] in ALIASES_3: # BOT set ...
		if args.size() < 3: # BOT set ?"trait"? ?VALUE?
			print_output("provide a bot trait and modify it to a value", "shell_output", pid)
			return
		var filter: Vector2i = get_session_reference_from_flags(flags, pid)
		var sid: int
		if filter[1] >= 2: return
		if filter[1] == 1:
			print_output("usage: bot set =s/=n SID/NAME \"trait\" VALUE", "shell_output", pid)
			return
		if filter[1] == 0:
			sid = filter[0]
			sid = -abs(sid)
		if filter[1] <= -1:
			print_output("can't refer to bots using a count integer when modifying traits", "shell_error", pid)
			return
		var ATTRIBUTE: String = args[1]
		var VALUE: String = args[2]
		if not SessionManager.data[sid]["personality"].has(ATTRIBUTE):
			var ERROR: String = "nonexistent trait \"" + ATTRIBUTE + "\"\n"
			var HELP: String = "available bot traits:\n"
			var traits: String = ""
			for trait_attribute: String in SessionManager.data[sid]["personality"].keys():
				traits += trait_attribute + "\n"
			print_output(ERROR + HELP + traits, "shell_error", pid)
			return
		SessionManager.set_bot_trait_from_str(sid, ATTRIBUTE, VALUE)
		return
	elif args[0] in ALIASES_4: # BOT enable ...
		if IngameManager.current_state != IngameManager.State.FINISHED:
			print_output("can't change bot process mode when ingame is not loaded", "shell_error", pid)
			return
		for bot_controller: Node in IngameManager.get_children():
			if bot_controller.get_meta("type", "null") != "bot": continue
			bot_controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	elif args[0] in ALIASES_5: # BOT disable ...
		if IngameManager.current_state != IngameManager.State.FINISHED:
			print_output("can't change bot process mode when ingame is not loaded", "shell_error", pid)
			return
		for bot_controller: Node in IngameManager.get_children():
			if bot_controller.get_meta("type", "null") != "bot": continue
			bot_controller.process_mode = Node.PROCESS_MODE_DISABLED
			bot_controller.linear_input = 0
			bot_controller.angular_input = 0
	elif args[0] in ALIASES_6: # BOT random ...
		var set_seed: int = randi()
		if args.size() >= 2: set_seed = int(args[1])
		SessionManager.random_bot_color.rpc(set_seed)
		return
	else: # BOT ...
		print_output("invalid first argument. Should be add, delete, set, enable, disable or random", "shell_error", pid)
		return

# temporary quick configuration
func cmd_chat_resize(args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	if not UIManager.is_ui_configured:
		print_output("no chat menu connected", "shell_error", 0)
		return
	if args.is_empty():
		print_output("provide a font size", "shell_output", 0)
		return
	UIManager.chat_menu_node.set_font_size(int(args[0]))

func cmd_start_game(_args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	if not multiplayer.is_server(): return
	IngameManager.start_game()

func cmd_crate(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if not multiplayer.is_server(): return
	if args.is_empty():
		print_output(
			"usage: crate (add [COUNT/TYPE [COUNT]])/(delete [COUNT])",
			"shell_output", pid)
		return
	const ALIASES_1 := ["add", "create"]
	const ALIASES_2 := ["remove", "delete", "erase"]
	if args[0] in ALIASES_1: # CRATE add ...
		var count: int = 1
		var specific_type: String = "bulk"
		if args.size() >= 2:
			if not args[1].is_valid_int():
				specific_type = args[1]
			else: count = abs(int(args[1])) # CRATE add 1 [2] [3] [4] ...
		if args.size() == 2: SessionManager.add_crate(count, specific_type)
		if args.size() >= 3:
			count = int(args[2])
			for i: int in range(0, count):
				SessionManager.add_crate(1, specific_type)
		return
	elif args[0] in ALIASES_2: # CRATE remove ...
		var count: int = 1
		if args.size() >= 2: count = abs(int(args[1])) # BOT remove 1 [2] [3] [4] ...
		SessionManager.remove_crate(count)
		return
	else: # CRATE ...
		print_output("invalid first argument. Should be add or delete", "shell_error", pid)
		return

func cmd_maze(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if not multiplayer.is_server(): return
	if args.is_empty():
		print_output(
			"usage: maze \"min_width, max_width, min_height, max_height\"",
			"shell_output", pid)
		return
	var compact: String = " ".join(args).replace(",", " ").strip_edges()
	var parsed: Vector4i = SessionManager.string_to_vector4i(compact)
	if parsed[0] <= 0 or parsed[1] <= 0 or parsed[2] <= 0 or parsed[3] <= 0:
		print_output("usage: maze \"min_width, max_width, min_height, max_height\"", "shell_output", pid)
		return
	IngameManager.set_maze_size.rpc(compact)
	print_output("maze size set to " + compact + " (applies from the next round)", "target", pid)

func cmd_close_ingame(_args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	if not NetworkManager.is_online:
		print_output("can't close ingame when offline/disconnected", "shell_error", 0)
		return
	IngameManager.end_ingame(true)

func cmd_restart_ingame(_args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	if not NetworkManager.is_online:
		print_output("can't restart ingame when offline/disconnected", "shell_error", 0)
		return
	IngameManager.restart_ingame()

func cmd_get_sessions(args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	if args.is_empty():
		var result: String = ""
		for sid: int in SessionManager.data.keys():
			result += "\n--- "
			result += get_printed_session(sid)
		if result.is_empty(): print_output("there are no current sessions", "shell_output", 0)
		else: print_output(result, "shell_output", 0)
		return
	for key: PackedStringArray in ATTRIBUTE_ALIASES.values():
		if not args[0] in key: continue
		for session: Dictionary in SessionManager.data.values():
			var result: String
			if key[0] == "color":
				result = SessionManager.color_to_string(session.get(key[0]))
			else: result = str(session.get(key[0]))
			print_output(key[0] + ": " + result, "shell_output", 0)
		return

const AFFIRM_ALIASES := ["true", "t", "yes", "y"]
func cmd_pause(args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	if args.is_empty(): MasterManager.set_pause(not get_tree().is_paused())
	elif args[0] in AFFIRM_ALIASES: MasterManager.set_pause(true)
	else: MasterManager.set_pause(false)

func cmd_toggle_ingame_states(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if not NetworkManager.is_dedicated_server:
		print_output("can't toggle ingame state display if it's not a dedicated server", "shell_error", pid)
		return
	if args.is_empty(): IngameManager.is_showing_states = not IngameManager.is_showing_states
	elif args[0] in AFFIRM_ALIASES: IngameManager.is_showing_states = true
	else: IngameManager.is_showing_states = false
	var message: Dictionary = {
		"sender_sid": 1,
		"sender_name": "server",
		"text": "ingame state display set to " + str(IngameManager.is_showing_states),
		"timestamp": Time.get_time_string_from_unix_time(int(Time.get_unix_time_from_system())),
		"channel": "global"
	}
	ConsoleManager.dedicated_server_print(message)

func cmd_op(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	ChatManager.remove_previous_local_message.rpc_id(pid)
	if args.size() < 3:
		print_output("usage: op {true/false} {pid} {password}", "shell_output", pid)
		return
	var entered_pass: String = args[2]
	if entered_pass != SessionManager.op_password:
		print_output("incorrect op password", "shell_error", pid)
		return
	SessionManager.randomize_password()
	var target_pid: int = SessionManager.decode_session_id(args[1])
	if target_pid <= 0:
		print_output("invalid peer id", "shell_error", pid)
		return
	if not target_pid in multiplayer.get_peers():
		print_output("peer id " + args[1] + " doesn't exist", "shell_error", pid)
		return
	var old_op_value: bool = SessionManager.data[target_pid]["op"]
	SessionManager.assign_from_str(target_pid, "op", args[0])
	var current_op_value: bool = args[0] == "true"
	var has_op_changed: bool = current_op_value != old_op_value
	if not has_op_changed:
		if current_op_value == true: print_output("this player is already an op", "shell_error", pid)
		else: print_output("this player is already not an op", "shell_error", pid)
		return
	if SessionManager.data[target_pid]["op"] == true:
		print_output("you have been granted op permissions", "target", target_pid)
		return
	print_output("you are no longer an op", "target", target_pid)

func cmd_admin(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if args.size() < 2:
		print_output("usage: admin {true/false} {pid}", "shell_output", pid)
		return
	var target_pid: int = SessionManager.decode_session_id(args[1])
	if target_pid <= 0:
		print_output("invalid peer id", "shell_error", pid)
		return
	if not target_pid in multiplayer.get_peers():
		print_output("peer id " + args[1] + " doesn't exist", "shell_error", pid)
		return
	if SessionManager.data[target_pid].get("op") == true:
		print_output("can't change admin role for op session", "shell_error", pid)
		return
	var old_admin_value: bool = SessionManager.data[target_pid]["admin"]
	SessionManager.assign_from_str(target_pid, "admin", args[0])
	var current_admin_value: bool = args[0] == "true"
	var has_admin_changed: bool = current_admin_value != old_admin_value
	if not has_admin_changed:
		if current_admin_value == true: print_output("this player is already an admin", "shell_error", pid)
		else: print_output("this player is already not an admin", "shell_error", pid)
		return
	if SessionManager.data[target_pid]["admin"] == true:
		print_output("you have been granted admin permissions", "target", target_pid)
		return
	print_output("you are no longer an admin", "target", target_pid)

func cmd_makehost(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if args.is_empty():
		print_output("usage: makehost {username}", "shell_output", pid)
		return
	var target_name: String = " ".join(args).strip_edges().to_lower()
	var target_sid: int = 0
	for sid: int in SessionManager.data.keys():
		if sid <= 1: continue
		if str(SessionManager.data[sid].get("name", "")).strip_edges().to_lower() == target_name:
			target_sid = sid
			break
	if target_sid == 0:
		print_output("player not found: " + " ".join(args), "shell_error", pid)
		return
	if target_sid == pid:
		print_output("you are already the room host", "shell_error", pid)
		return
	SessionManager.set_local_op(target_sid, true)
	SessionManager.set_local_op(pid, false)
	SessionManager.set_local_admin(pid, false)
	print_output("you are now the room host", "target", target_sid)
	ChatManager.process_message(str(SessionManager.data[target_sid].get("name", "unnamed")) + " is now the room host", "global", 0)
	UIManager.update_lobby_register()
	SessionManager.update_registry.rpc(SessionManager.data)

func cmd_purge(_args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if not multiplayer.is_server(): return
	ChatManager.purge_chat.rpc()
	print_output("chat purged", "target", pid)

func cmd_bot_max(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if args.size() < 1:
		print_output("usage: bot_max {count}", "shell_output", pid)
		return
	var count: int = int(args[0])
	if count < 0: count = 0
	SessionManager.max_bot_count = count

func cmd_crate_max(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if args.size() < 1:
		print_output("usage: crate_max {count}", "shell_output", pid)
		return
	var count: int = int(args[0])
	if count < 0: count = 0
	SessionManager.max_crate_count = count

func cmd_maze_max(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if args.size() < 1:
		print_output("usage: maze_max {cell width/height}", "shell_output", pid)
		return
	var size: int = int(args[0])
	if size < 1: size = 1
	IngameManager.max_maze_size = size

func cmd_mute(args: PackedStringArray, _flags: Array[PackedStringArray], pid: int) -> void:
	if args.size() < 2:
		print_output("usage: mute {true/false} {pid}", "shell_output", pid)
		return
	var is_muting: bool = args[0] == "true"
	var target_pid: int = SessionManager.decode_session_id(args[1])
	if target_pid <= 0:
		print_output("invalid peer id", "shell_error", pid)
		return
	if not target_pid in multiplayer.get_peers():
		print_output("peer id " + args[1] + " doesn't exist", "shell_error", pid)
		return
	if SessionManager.data[target_pid].get("op") == true:
		print_output("can't mute an op session", "shell_error", pid)
		return
	SessionManager.mute_peer(is_muting, target_pid)

func cmd_help_chat(_args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	var message: String = "\n"
	message += "Shift+M: toggle move window\n"
	message += "Shift+R: toggle chat resizing\n"
	message += "Shift+H: toggle chat visibility\n"
	message += "chat_resize: command for resizing chat text\n"
	print_output(message, "shell_output", 0)

func cmd_help_controls(_args: PackedStringArray, _flags: Array[PackedStringArray], _pid: int) -> void:
	var message: String = "\n"
	message += "W/up arrow to move forward\n"
	message += "S/down arrow to move backward\n"
	message += "A/left arrow to rotate counterclockwise\n"
	message += "D/right arrow to rotate clockwise\n"
	message += "Hold shift to drift\n"
	message += "Press space to shoot\n"
	print_output(message, "shell_output", 0)
