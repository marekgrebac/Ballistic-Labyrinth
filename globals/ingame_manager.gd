extends Node

enum State {
	STOPPED				= 0,
	ANIMATING			= 1,
	WAITING_BEFORE_SYNC = 2,
	FINISHED			= 3
}

var current_state: State = State.STOPPED

var is_showing_states: bool = false
func set_current_state(state: State) -> void:
	current_state = state
	if not NetworkManager.is_dedicated_server: return
	if not is_showing_states: return
	var state_name: String = ""
	if state == State.STOPPED: state_name = " (STOPPED)"
	if state == State.ANIMATING: state_name = " (ANIMATING)"
	if state == State.WAITING_BEFORE_SYNC: state_name = " (WAITING BEFORE SYNC)"
	if state == State.FINISHED: state_name = " (FINISHED)"
	var message: Dictionary = {
		"sender_sid": 1,
		"sender_name": "server",
		"text": "ingame state set to " + str(state) + state_name,
		"timestamp": Time.get_time_string_from_unix_time(int(Time.get_unix_time_from_system())),
		"channel": "global"
	}
	ConsoleManager.dedicated_server_print(message)

## this node will have every controller node as a child node so they're easier to access

## updated once by origin node, remains constant
var scene_root: Node = null

var current_seed: int = 0
var current_maze_dimensions: Vector2i = Vector2i(20, 12) ## first entry is width, second is height
var set_maze_dimensions: Vector4i = Vector4i(20, 20, 12, 12)
var current_is_animated_generation: bool = false

const INGAME_FILE: String = "res://ingame/ingame.tscn"
var ingame_container: MultiplayerSpawner = null
var controller_container: MultiplayerSpawner = null

#var is_ingame_configured: bool = false
#var is_ingame_finished: bool = false

#var finished_clients: Array = []

var alive_tanks_count: int = 0

func _enter_tree() -> void:
	setup_ingame_container()
	setup_controller_container()

func setup_ingame_container() -> void:
	ingame_container = MultiplayerSpawner.new()
	ingame_container.spawn_function = spawn_ingame
	add_child(ingame_container, true)
	ingame_container.name = "IngameContainer"
	ingame_container.spawn_path = ingame_container.get_path()

func setup_controller_container() -> void:
	controller_container = MultiplayerSpawner.new()
	controller_container.spawn_function = _custom_spawn
	add_child(controller_container, true)
	controller_container.name = "ControllerContainer"
	controller_container.spawn_path = controller_container.get_path()

var max_maze_size: int = 25
@rpc("authority", "reliable", "call_local")
func set_maze_size(string: String) -> void:
	var result: Vector4i = SessionManager.string_to_vector4i(string)
	if result[0] <= 0 or result[1] <= 0 or result[2] <= 0 or result[3] <= 0: return
	if result[0] > result[1] or result[2] > result[3]: return
	for i: int in range(4): if result[i] > max_maze_size: return
	set_maze_dimensions = result

@rpc("authority", "reliable", "call_local")
func set_maze_animation_to_true() -> void:
	current_is_animated_generation = true

func create_controller(sid: int) -> void:
	print("BLTRACE create_controller sid=", sid)
	if sid == 0: return
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	controller_container.spawn(sid)

const NEW_PLAYER_CONTROLLER_FILE: String = "res://ingame/controllers/player_controller/player_controller.tscn"
const NEW_BOT_CONTROLLER_FILE: String = "res://ingame/controllers/bot_controller/bot_controller.tscn"
func _custom_spawn(sid: Variant) -> Node:
	sid = int(sid)
	if sid == 0: return null
	var controller: Node
	if sid >= 1: controller = load(NEW_PLAYER_CONTROLLER_FILE).instantiate()
	if sid <= -1: controller = load(NEW_BOT_CONTROLLER_FILE).instantiate()
	controller.set_sid(sid)
	return controller

func create_controllers() -> void:
	print("BLTRACE create_controllers data=", SessionManager.data.keys())
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	var already_has_controller: bool
	for sid: int in SessionManager.data:
		already_has_controller = false
		for controller: Node in controller_container.get_children():
			if controller.sid != sid: continue
			already_has_controller = true
			break
		if already_has_controller: continue
		create_controller(sid)

@rpc("authority", "reliable", "call_local")
func disable_client_controller(path: NodePath) -> void:
	get_node(path).set_multiplayer_authority(1)
	get_node(path).set_visibility_public(false)

func delete_controllers() -> void:
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	for controller: Node in controller_container.get_children():
		if controller is MultiplayerSynchronizer:
			disable_client_controller.rpc_id(controller.sid, controller.get_path())
		await get_tree().process_frame
		controller.queue_free()

func delete_player(pid: int) -> void:
	print("BLTRACE delete_player pid=", pid, " state=", current_state)
	if pid <= 1: return
	if current_state != State.FINISHED:
		for orphan: Node in controller_container.get_children():
			if orphan.sid == pid and orphan.pawn == null:
				orphan.queue_free()
		return
	var target_controller: MultiplayerSynchronizer = null
	for cont: Node in controller_container.get_children():
		if cont.sid <= 1: continue
		if cont.sid != pid: continue
		target_controller = cont
		break
	if target_controller == null: return
	if target_controller.pawn == null:
		target_controller.queue_free()
		return
	for bullet: Node in IngameManager.ingame_node.get_node(^"Bullets").get_children():
		if bullet.owner_node != target_controller.pawn: continue
		bullet.queue_free()
	target_controller.pawn.queue_free()
	target_controller.queue_free()
	## a disconnected player's pawn no longer blocks the round end
	alive_tanks_count = max(0, alive_tanks_count - 1)
	if alive_tanks_count <= 1 and ingame_node != null:
		ingame_node.get_node(^"Timers/DeathDelay").start()

## counts played rounds, broadcast alongside maze properties for the HUD label
var round_number: int = 0

@rpc("any_peer", "reliable", "call_local")
func start_game() -> void:
	var pid: int = multiplayer.get_remote_sender_id()
	print("BLTRACE start_game pid=", pid)
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	if pid != 0 and not SessionManager.is_op(pid): return
	MasterManager.is_await_interrupted = true
	current_seed = randi()
	current_maze_dimensions.x = randi_range(set_maze_dimensions[0], set_maze_dimensions[1])
	current_maze_dimensions.y = randi_range(set_maze_dimensions[2], set_maze_dimensions[3])
	if current_maze_dimensions.y > current_maze_dimensions.x:
		var auxiliary: int = current_maze_dimensions.x
		current_maze_dimensions.x = current_maze_dimensions.y
		current_maze_dimensions.y = auxiliary
	round_number += 1
	start_ingame(current_seed, current_maze_dimensions)

@rpc("any_peer", "reliable")
func end_game() -> void:
	var pid: int = multiplayer.get_remote_sender_id()
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	if not SessionManager.is_op(pid): return
	end_ingame(true)

const LATE_INGAME_SYNC_DELAY: float = 2.0
@rpc("authority", "reliable")
func late_sync_ingame(maze_seed: int, maze_dimensions: Vector2i) -> void:
	await get_tree().create_timer(LATE_INGAME_SYNC_DELAY).timeout
	start_ingame(maze_seed, maze_dimensions)

func start_ingame(maze_seed: int, maze_dimensions: Vector2i) -> void:
	print("BLTRACE start_ingame seed=", maze_seed, " dims=", maze_dimensions)
	if not multiplayer.is_server(): return
	set_maze_properties.rpc(maze_seed, maze_dimensions, round_number)
	create_controllers()
	create_ingame()

@rpc("authority", "reliable", "call_local")
func set_maze_properties(maze_seed: int, maze_dimensions: Vector2i, p_round_number: int) -> void:
	if UIManager.is_ui_configured: UIManager.lobby_node.activate(false)
	current_seed = maze_seed
	current_maze_dimensions = maze_dimensions
	round_number = p_round_number
	if UIManager.is_ui_configured: UIManager.set_round_label(round_number)

func create_ingame() -> void:
	print("BLTRACE create_ingame")
	if ingame_container.get_child_count() > 0: return
	var data: Dictionary = {
		"seed": current_seed,
		"dimensions": current_maze_dimensions
	}
	ingame_container.spawn(data)

var ingame_node: Node = null
func spawn_ingame(data: Variant) -> Node:
	print("BLTRACE spawn_ingame")
	if UIManager.is_ui_configured: UIManager.lobby_node.activate(false)
	var ingame: Node = load(INGAME_FILE).instantiate()
	ingame_node = ingame
	current_seed = data["seed"]
	current_maze_dimensions = data["dimensions"]
	return ingame

const RESTART_DELAY: float = 0.6
func restart_ingame() -> void:
	print("BLTRACE restart_ingame")
	end_ingame(false) #delete_ingame(false)
	## let queued frees and replication despawns land before the new round spawns
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(RESTART_DELAY).timeout
	set_current_state(State.STOPPED)
	start_game()

func _on_ingame_next_round() -> void:
	restart_ingame()

func delete_ingame(is_deleting_controllers: bool) -> void:
	print("BLTRACE delete_ingame controllers=", is_deleting_controllers)
	if not multiplayer.is_server(): return
	if ingame_container.get_child_count() == 0: return
	if OS.get_environment("BL_DEBUG_NO_INSTANCE_LOOP") != "1":
		for spawner: Node in ingame_container.get_child(0).get_children():
			if not spawner is MultiplayerSpawner: continue
			for instance: Node in spawner.get_children():
				## deferred free: mid-frame free() of replicated nodes raced
				## replication despawns and segfaulted room servers during
				## death-cascade round restarts
				instance.queue_free()
	if is_deleting_controllers: delete_controllers()
	ingame_container.get_child(0).queue_free()

@rpc("authority", "reliable")
func end_ingame(is_deleting_controllers: bool) -> void:
	print("BLTRACE end_ingame controllers=", is_deleting_controllers)
	MasterManager.set_pause(false)
	set_current_state(State.STOPPED)
	if UIManager.is_ui_configured: UIManager.set_round_label(0)
	delete_ingame(is_deleting_controllers)
	if is_deleting_controllers and UIManager.is_ui_configured:
		UIManager.lobby_node.activate(true)
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	end_ingame.rpc(is_deleting_controllers)

@rpc("any_peer", "reliable", "call_local")
func request_end_ingame() -> void:
	var pid: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server(): return
	if pid == 0: return
	if not SessionManager.is_op(pid): return
	MasterManager.set_pause(false)
	end_ingame(true)

func finish_network_maze_generation() -> void:
	print("BLTRACE finish_network_maze_generation alive=", alive_tanks_count)
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	#for pid: int in multiplayer.get_peers():
		#if pid in finished_clients: continue
		#restart_ingame.rpc_id(pid, current_seed, current_maze_dimensions, false)
	if current_state <= State.ANIMATING: return
	place_pawns()
	ingame_node.toggle_pawns.rpc(true)
	if OS.get_environment("BL_DEBUG_NO_CRATES") != "1":
		ingame_node.activate_crate_spawn_timer()
	set_current_state(State.FINISHED)

#@rpc("any_peer", "reliable")
#func add_finished_generation() -> void:
	#var pid: int = multiplayer.get_remote_sender_id()
	#if pid <= 1: return
	#finished_clients.append(pid)

const FINISH_GENERATION_DELAY: float = 1.0
func broadcast_generation_finish() -> void:
	print("BLTRACE broadcast_generation_finish")
	if not multiplayer.is_server(): return
	set_current_state(State.WAITING_BEFORE_SYNC)
	await get_tree().create_timer(FINISH_GENERATION_DELAY).timeout
	if current_state != State.WAITING_BEFORE_SYNC: return
	finish_network_maze_generation()
	#return
	#add_finished_generation.rpc_id(1)

const PAWN_LINEAR_STUCK_FACTOR: float = 200 / 3.2
const NEW_TANK_PAWN_PATH: String = "res://ingame/entities/tank_pawn/tank_pawn.tscn"
func place_pawns() -> void:
	print("BLTRACE place_pawns start sids=", SessionManager.data.keys())
	if not NetworkManager.is_online: return
	if not multiplayer.is_server(): return
	alive_tanks_count = 0
	## stagger pawn instantiation across frames: dense spawn bursts right
	## after mass queue_frees crash the engine during round restarts
	await place_pawns_staggered()

func place_pawns_staggered() -> void:
	var tank_pawn: RigidBody2D = null
	for sid: int in SessionManager.data.keys():
		if sid == 0: continue
		print("BLTRACE pp1 instantiate sid=", sid)
		tank_pawn = load(NEW_TANK_PAWN_PATH).instantiate()
		var target_controller: Node = null
		for controller: Node in controller_container.get_children():
			if controller.sid != sid: continue
			target_controller = controller
			break
		if target_controller == null: continue
		print("BLTRACE pp2 ctrl found sid=", sid)
		target_controller.pawn = tank_pawn
		if target_controller.get_meta("type", "null") == "bot":
			target_controller.MAX_STUCK_POSITION_CHANGE = tank_pawn.linear_speed / PAWN_LINEAR_STUCK_FACTOR
		print("BLTRACE pp3 meta done")
		tank_pawn.controller = target_controller
		tank_pawn.get_node(^"Rest/Image").modulate = SessionManager.data[sid]["color"]
		tank_pawn.get_node(^"DeathParticles").modulate = SessionManager.data[sid]["color"]
		tank_pawn.label_node.text = SessionManager.data[sid]["name"]
		print("BLTRACE pp4 visuals done")
		var selected_cell: Vector2i = ingame_node.maze_cells.get(ingame_node.SEEDED_RNG.randi_range(0, ingame_node.maze_cells.size() - 1))
		tank_pawn.global_position = ingame_node.maze_cell_to_world(selected_cell)
		tank_pawn.rotation = ingame_node.SEEDED_RNG.randf_range(0, PI * 2)
		print("BLTRACE pp5 pos done")
		tank_pawn.connect("shoot_bullet", _on_shoot_bullet)
		if OS.get_environment("BL_DEBUG_NO_PAWN_COLLISION") == "1":
			tank_pawn.collision_layer = 0
			tank_pawn.collision_mask = 0
		if OS.get_environment("BL_DEBUG_NO_PAWN_SYNC") == "1":
			var sync_node: Node = tank_pawn.get_node_or_null(^"Sync")
			if sync_node != null: sync_node.queue_free()
		ingame_node.get_node("TankPawns").add_child(tank_pawn, true)
		## pawns spawn with PROCESS_MODE_DISABLED; the old sync place_pawns ran
		## fully before toggle_pawns(true). Async staggered spawning must enable
		## each pawn itself or it never integrates forces.
		tank_pawn.toggle(true)
		alive_tanks_count += 1
		print("BLTRACE place_pawns done alive=", alive_tanks_count, " sid=", sid)
		## give replication/navigation a frame to settle between pawns
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame

## directly called by destroyed tanks
func _on_tank_die() -> void:
	print("BLTRACE tank_die alive_before=", alive_tanks_count)
	alive_tanks_count -= 1
	MasterManager.play_server_sound(ingame_node.get_node(^"Sounds/DeathNoise"))
	print("BLTRACE tank_die sound done alive=", alive_tanks_count)
	if alive_tanks_count <= 1:
		print("BLTRACE tank_die starting DeathDelay")
		ingame_node.get_node(^"Timers/DeathDelay").start()
		print("BLTRACE tank_die DeathDelay started")

func _on_shoot_bullet(weapon_type: String, tank: RigidBody2D) -> void:
	if OS.get_environment("BL_DEBUG_NO_BULLETS") == "1":
		return
	if tank == null: return
	if weapon_type != "regular":
		tank.equip_weapon.rpc("regular")
	var payload: Dictionary = {}
	var bullet_offset: float
	if weapon_type == "regular":
		bullet_offset = tank.REGULAR_SPAWN_OFFSET
		payload["initial_velocity_speed"] = tank.regular_speed
		payload["type"] = "regular"
	if weapon_type == "laser":
		bullet_offset = tank.LASER_SPAWN_OFFSET
		payload["initial_velocity_speed"] = tank.laser_speed
		payload["lifespan"] = tank.laser_lifespan
		payload["type"] = "laser"
	if weapon_type == "rocket":
		bullet_offset = tank.ROCKET_SPAWN_OFFSET
		payload["initial_velocity_speed"] = tank.rocket_speed
		payload["lifespan"] = tank.rocket_lifespan
		payload["type"] = "rocket"
	if weapon_type == "trap":
		bullet_offset = tank.TRAP_SPAWN_OFFSET
		payload["initial_velocity_speed"] = tank.trap_speed
		payload["type"] = "trap"
	payload["owner"] = tank.get_path()
	payload["initial_velocity_direction"] = tank.rotation
	payload["position"] = tank.position + Vector2(bullet_offset, 0).rotated(tank.rotation)
	if weapon_type == "regular": tank.fired_bullet_count += 1
	ingame_node.get_node("Bullets").spawn(payload)

const NEW_BULLET_FILE := "res://ingame/entities/projectiles/bullet.tscn"
func spawn_bullet(payload: Dictionary) -> Node:
	print("BLTRACE spawn_bullet type=", payload.get("type"))
	var bullet: RigidBody2D = load(NEW_BULLET_FILE).instantiate()
	bullet.position = payload["position"]
	bullet.initial_velocity_speed = payload["initial_velocity_speed"]
	if payload.has("lifespan"): bullet.get_node("LifespanTimer").wait_time = payload["lifespan"]
	bullet.type = payload["type"]
	bullet.initial_velocity_direction = payload["initial_velocity_direction"]
	bullet.owner_node = get_node(payload["owner"])
	if bullet.type == "regular": ingame_node.get_node("Sounds/NormalShootNoise").play()
	if bullet.type == "laser": ingame_node.get_node("Sounds/LaserShootNoise").play()
	if bullet.type == "rocket": ingame_node.get_node("Sounds/RocketShootNoise").play()
	if bullet.type == "trap": ingame_node.get_node("Sounds/TrapPlaceNoise").play()
	return bullet

@rpc("any_peer", "unreliable_ordered", "call_local")
func teleport_tank(pos: Vector2) -> void:
	var pid: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server(): return
	if not SessionManager.is_op(pid): return
	var pawn: Node2D = null
	for controller: Node in controller_container.get_children():
		if controller.sid != pid: continue
		if controller.pawn == null: return
		pawn = controller.pawn
		break
	if pawn == null: return
	pawn.global_position = pos

@rpc("any_peer", "reliable", "call_local")
func change_invincibility() -> void:
	var pid: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server(): return
	if not SessionManager.is_op(pid): return
	var pawn: Node2D = null
	for controller: Node in controller_container.get_children():
		if controller.sid != pid: continue
		if controller.pawn == null: return
		pawn = controller.pawn
		break
	if pawn == null: return
	pawn.is_invincible = not pawn.is_invincible
	var text: String = "invincibility set to "
	if pawn.is_invincible: text += "true "
	else: text += "false "
	text += "for pid = " + SessionManager.encode_session_id(pid)
	ConsoleManager.print_output(text, "admin", 0)

@rpc("any_peer", "reliable", "call_local")
func change_noclip() -> void:
	var pid: int = multiplayer.get_remote_sender_id()
	if not multiplayer.is_server(): return
	if not SessionManager.is_op(pid): return
	var pawn: Node2D = null
	for controller: Node in controller_container.get_children():
		if controller.sid != pid: continue
		if controller.pawn == null: return
		pawn = controller.pawn
		break
	if pawn == null: return
	var is_noclip: bool = not pawn.get_collision_layer_value(2)
	pawn.set_collision_layer_value(2, is_noclip)
	pawn.set_collision_mask_value(1, is_noclip)
	var text: String = "noclip set to "
	if not is_noclip: text += "true "
	else: text += "false "
	text += "for pid = " + SessionManager.encode_session_id(pid)
	ConsoleManager.print_output(text, "admin", 0)
