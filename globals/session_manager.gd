extends Node

var data: Dictionary = {}
var profile_data: Dictionary = {}

var op_password: String = ""

func is_bot(session_id: int) -> bool:
	return session_id < 0

func turn_local_to_online_profile() -> void:
	if not multiplayer.is_server(): return
	if NetworkManager.is_dedicated_server: return
	data.clear()
	profile_data["admin"] = true
	profile_data["op"] = true
	data[multiplayer.get_unique_id()] = profile_data
	#UIManager.update_lobby_register() # happens right after exiting this scope

func master_enter_tree() -> void:
	create_local_profile()
	randomize_password()

func create_local_profile() -> void:
	if NetworkManager.is_dedicated_server: return
	if data.has(0): return
	profile_data = {
		"name": "unnamed",
		"admin": false,
		"op": false,
		"muted": false,
		"color": Color(1.0, 1.0, 1.0, 1.0),
		"kills": 0,
		"score": 0,
		"deaths": 0,
		"ping": 0
	}
	data[0] = profile_data

func randomize_password() -> void:
	if not NetworkManager.is_dedicated_server: return
	var encoded: String = encode_session_id(abs(randi())+2)
	var result: String = encoded
	encoded = encode_session_id(abs(randi())+2)
	result += encoded
	op_password = result
	var message: Dictionary = {
		"sender_sid": 1,
		"sender_name": "server",
		"text": "OP_PASSWORD: " + op_password,
		"timestamp": Time.get_time_string_from_unix_time(int(Time.get_unix_time_from_system())),
		"channel": "global"
	}
	ConsoleManager.dedicated_server_print(message)

func clear_registry() -> void:
	data.clear()
	data[0] = profile_data

func is_admin(pid: int) -> bool:
	if pid == 1: return true
	if not NetworkManager.is_online: return false
	if pid <= 0: return false
	if not pid in data.keys(): return false
	if data.get(pid).get("op") == true: return true
	if data.get(pid).get("admin") != true: return false
	return true

func is_op(pid: int) -> bool:
	if pid == 1: return true
	if not NetworkManager.is_online: return false
	if pid <= 0: return false
	if not pid in data.keys(): return false
	if data.get(pid).get("op") != true: return false
	return true

func is_muted(pid: int) -> bool:
	if pid <= 1: return false
	if not pid in data.keys(): return false
	if data.get(pid).get("muted") != true: return false
	return true

@rpc("authority", "reliable")
func add_session(session_id: int, profile: Dictionary) -> void:
	if session_id == 0: return
	data[session_id] = profile
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	add_session.rpc(session_id, profile)

var max_bot_count: int = 5
@rpc("authority", "reliable", "call_local")
func add_bot(count: int = 1) -> void:
	if count <= 0: return
	var current_bot_count: int = 0
	for sid: int in data.keys():
		if sid >= 0: continue
		current_bot_count += 1
	if current_bot_count + count > max_bot_count: return
	var new_sid: int = -1
	while count > 0:
		while data.has(new_sid): new_sid -= 1
		add_session(new_sid, {
			"name": "bot " + str(abs(new_sid)),
			"admin": false,
			"op": false,
			"muted": false,
			"color": Color(1.0, 1.0, 1.0, 1.0),
			"kills": 0,
			"score": 0,
			"deaths": 0,
			"ping": 0,
			"personality": {}
		})
		count -= 1
	UIManager.update_lobby_register()

@rpc("authority", "reliable", "call_local")
func remove_bot_sid(sid: int) -> void:
	if sid >= 0: return
	if not data.has(sid): return
	data.erase(sid)
	UIManager.update_lobby_register()

@rpc("authority", "reliable", "call_local")
func remove_bot_count(count: int = 1) -> void:
	if count <= 0: return
	for sid: int in data.keys():
		if count <= 0: break
		if sid >= 0: continue
		data.erase(sid)
		count -= 1
	UIManager.update_lobby_register()

func mute_peer(is_muting: bool, pid: int) -> void:
	if pid <= 0: return
	if data[pid].get("staff_access") == ConsoleManager.StaffAccess.OP: return
	data[pid]["muted"] = is_muting

func set_profile_name(name_string: String) -> void:
	profile_data["name"] = name_string
	wrap_request_profile_update()

func set_profile_color(color: Color) -> void:
	profile_data["color"] = color
	wrap_request_profile_update()

func set_local_admin(pid: int, is_this_admin: bool) -> void:
	data[pid]["admin"] = is_this_admin
	if pid != multiplayer.get_unique_id(): return
	UIManager.toggle_admin_options(is_this_admin)

func set_local_op(pid: int, is_this_op: bool) -> void:
	data[pid]["op"] = is_this_op
	set_local_admin(pid, true)

func increment_kill(sid: int) -> void:
	if sid == 0: return
	assign_from_str(sid, "kills", str(data[sid].get("kills") + 1))

func increment_score(sid: int) -> void:
	if sid == 0: return
	assign_from_str(sid, "score", str(data[sid].get("score") + 1))

func increment_death(sid: int) -> void:
	if sid == 0: return
	if not data.has(sid): return
	assign_from_str(sid, "deaths", str(data[sid].get("deaths", 0) + 1))

## alpha channel isn't used, so every color is opaque by default
func color_to_string(color: Color) -> String:
	var result: String = "\"" + str(color.r) + " " + str(color.g) + " " + str(color.b) + "\""
	return result

func string_to_color(string: String) -> Color:
	string = string.replace("\"", "")
	var split: PackedStringArray = string.split(" ", false)
	if split.size() <= 2: return Color.WHITE
	var floats: PackedFloat32Array = []
	for i: int in range(0, 3):
		floats.append(float(split[i]))
		if floats[i] < 0: floats[i] = 0.0
		if floats[i] > 1.0: floats[i] = 1.0
	var color: Color = Color(floats[0], floats[1], floats[2])
	return color

func vector4i_to_string(vector: Vector4i) -> String:
	var result: String = "\"" + str(vector[0]) + " " + str(vector[1])
	result += " " + str(vector[2]) + " " + str(vector[3]) + "\""
	return result

func string_to_vector4i(string: String) -> Vector4i:
	string = string.replace("\"", "")
	var split: PackedStringArray = string.split(" ", false)
	if split.size() <= 3: return Vector4i.ZERO
	return Vector4i(int(split[0]), int(split[1]), int(split[2]), int(split[3]))

@rpc("authority", "reliable")
func assign_from_str(sid: int, attribute: String, value: String) -> void:
	if sid == 0 and NetworkManager.is_online: sid = multiplayer.get_unique_id()
	if not data.has(sid): return
	if not data[sid].has(attribute): return
	if attribute == "color":
		data[sid][attribute] = string_to_color(value)
	else:
		if typeof(data[sid][attribute]) == TYPE_BOOL:
			if attribute == "admin": # stricter console set for admin permission
				if value == "true": set_local_admin(sid, true)
				else: set_local_admin(sid, false)
			elif attribute == "admin": # stricter console set for op permission
				if value == "true": set_local_op(sid, true)
				else: set_local_op(sid, false)
			else:
				if value == "false" or value == "0": data[sid][attribute] = false
				else: data[sid][attribute] = true
		if typeof(data[sid][attribute]) == TYPE_INT: data[sid][attribute] = int(value)
		if typeof(data[sid][attribute]) == TYPE_FLOAT: data[sid][attribute] = float(value)
		if typeof(data[sid][attribute]) == TYPE_STRING: data[sid][attribute] = value
		if sid == multiplayer.get_unique_id(): profile_data[attribute] = data[sid][attribute]
	UIManager.update_lobby_register()
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	assign_from_str.rpc(sid, attribute, value)

@rpc("authority", "reliable")
func set_bot_trait_from_str(sid: int, attribute: String, value: String) -> void:
	if sid >= 0: return
	if not data.has(sid): return
	if not data[sid]["personality"].has(attribute): return
	if typeof(data[sid]["personality"][attribute]) == TYPE_BOOL:
		if value == "false" or value == "0": data[sid]["personality"][attribute] = false
		else: data[sid]["personality"][attribute] = true
	if typeof(data[sid]["personality"][attribute]) == TYPE_INT:
		data[sid]["personality"][attribute] = int(value)
	if typeof(data[sid]["personality"][attribute]) == TYPE_FLOAT:
		data[sid]["personality"][attribute] = float(value)
	if typeof(data[sid]["personality"][attribute]) == TYPE_STRING:
		data[sid]["personality"][attribute] = value
	UIManager.update_lobby_register()
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	set_bot_trait_from_str.rpc(sid, attribute, value)

const MIN_RANDOM_COLOR: float = 0.05
const MAX_RANDOM_COLOR: float = 0.97
@rpc("authority", "reliable", "call_local")
func random_bot_color(set_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = set_seed
	var result: String
	for bot_id: int in SessionManager.data.keys():
		if bot_id >= 0: continue
		result = "\"" + str(rng.randf_range(MIN_RANDOM_COLOR, MAX_RANDOM_COLOR))
		result += " " + str(rng.randf_range(MIN_RANDOM_COLOR, MAX_RANDOM_COLOR))
		result += " " + str(rng.randf_range(MIN_RANDOM_COLOR, MAX_RANDOM_COLOR)) + "\""
		assign_from_str(bot_id, "color", result)

var max_crate_count: int = 15
func add_crate(count: int, type: String) -> void:
	if not multiplayer.is_server(): return
	if type == "bulk" and count <= 0: return
	if IngameManager.ingame_container.get_child_count() == 0: return
	if IngameManager.current_state != IngameManager.State.FINISHED: return
	var crates_node: Node = IngameManager.ingame_container.get_child(0).get_node_or_null(^"Crates")
	if crates_node == null: return
	var current_crate_count: int = crates_node.get_child_count()
	if type != "bulk": count = 1
	if current_crate_count + count > max_crate_count: return
	if type == "bulk":
		for i: int in range(0, count): IngameManager.ingame_container.get_child(0)._on_crate_spawn_delay_timeout("bulk")
		return
	IngameManager.ingame_container.get_child(0)._on_crate_spawn_delay_timeout(type)

func remove_crate(count: int) -> void:
	if not multiplayer.is_server(): return
	if count <= 0: return
	if IngameManager.ingame_container.get_child_count() == 0: return
	if IngameManager.current_state != IngameManager.State.FINISHED: return
	var crates_node: Node = IngameManager.ingame_container.get_child(0).get_node_or_null(^"Crates")
	if crates_node == null: return
	var current_count: int = crates_node.get_child_count()
	if current_count < count: count = current_count
	while count > 0:
		crates_node.get_child(0).free()
		count -= 1

func wrap_request_profile_update() -> void:
	if not NetworkManager.is_online:
		UIManager.update_lobby_register()
		return
	if multiplayer.is_server():
		request_profile_update(profile_data)
	else: request_profile_update.rpc_id(1, profile_data)

#func get_profile_name() -> String:
	#return profile_data.get("name")
#
#func get_profile_color() -> Color:
	#return profile_data.get("color")
#
#func get_profile_kills() -> int:
	#return profile_data.get("kills")
#
#func get_profile_score() -> int:
	#return profile_data.get("score")
#
#func get_profile_admin() -> bool:
	#return profile_data.get("admin")
#func get_profile_op() -> bool:
	#return profile_data.get("op")

@rpc("authority", "reliable")
func update_registry(server_data: Dictionary) -> void:
	data.clear()
	data.assign(server_data)
	UIManager.update_lobby_register()

@rpc("any_peer", "reliable")
func request_profile_update(profile: Dictionary) -> void:
	if not multiplayer.is_server(): return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 1: return
	var clean_name: String = profile.get("name", "unnamed").strip_edges()
	if clean_name.is_empty(): clean_name = "Player " + encode_session_id(sender_id)
	var has_power_holder: bool = false
	for sid: int in data.keys():
		if sid > 1 and data[sid].get("op") == true:
			has_power_holder = true
			break
	var grant_power: bool = NetworkManager.is_dedicated_server and not has_power_holder
	var previous: Dictionary = data.get(sender_id, {})
	var new_session: Dictionary = {
		"name": clean_name,
		"admin": grant_power or is_admin(sender_id),
		"op": grant_power or is_op(sender_id),
		"muted": is_muted(sender_id),
		"color": profile.get("color", Color(1.0, 1.0, 1.0, 1.0)),
		"kills": previous.get("kills", 0),
		"score": previous.get("score", 0),
		"deaths": previous.get("deaths", 0),
		"ping": previous.get("ping", 0)
	}
	data[sender_id] = new_session
	if grant_power:
		ConsoleManager.print_output("You are the room admin. Use Start Game; chat console: /start /bot /maze /restart /end_game /makehost /help", "target", sender_id)
	UIManager.update_lobby_register()
	update_registry.rpc(data)

const ENCODE_ALPHABET: String = "0123456789ABCDEFGHJKLMNPRTUVWXYZabcdefhikmnorstuvwxz^&*~!?/\\<>"
const ENCODE_BOT_PREFIX: String = "ai#"
const ENCODE_HOST: String = "#HOST"

func encode_session_id(session_id: int) -> String:
	if session_id == 0: return "0"
	if session_id == 1: return ENCODE_HOST
	var is_negative: bool = session_id < 0
	var num: int = abs(session_id)
	var result: String = ""
	var ENCODE_BASE: int = ENCODE_ALPHABET.length()
	while num > 0:
		var remainder: int = num % ENCODE_BASE
		result = ENCODE_ALPHABET[remainder] + result
		num /= ENCODE_BASE
	return ENCODE_BOT_PREFIX + result if is_negative else result

func decode_session_id(encoded_id: String) -> int:
	if encoded_id.is_empty(): return 0
	if encoded_id == ENCODE_HOST: return 1
	var is_negative: bool = encoded_id.begins_with(ENCODE_BOT_PREFIX)
	if is_negative: encoded_id = encoded_id.substr(ENCODE_BOT_PREFIX.length())
	var result: int = 0
	var ENCODE_BASE: int = ENCODE_ALPHABET.length()
	for i: int in range(encoded_id.length()):
		var character: String = encoded_id[i]
		var value: int = ENCODE_ALPHABET.find(character)
		if value == -1:
			push_error("CUSTOM ERROR in chat_manager.gd: Invalid character in encode string base")
			return 0
		result = result * ENCODE_BASE + value
	return -result if is_negative else result
