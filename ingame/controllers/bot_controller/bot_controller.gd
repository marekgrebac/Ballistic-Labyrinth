extends Node2D

var sid: int = 0
var pawn: Node2D = null

func set_sid(id: int) -> void:
	if id >= 0: return
	sid = id

func set_pawn() -> void:
	if pawn == null: return

## if < 0 move backwards
## if = 0 idle
## if > 0 move forwards
var linear_input: int = 0

## if < 0 rotate counterclockwise
## if = 0 idle
## if > 0 rotate clockwise
var angular_input: int = 0

var is_drifting: bool = false

var target: Node2D = null
var is_dodging_bullets: bool = false

func _ready() -> void:
	is_stopping_to_aim = bool(randi_range(0, 1))

func apply_angular_input(delta: float) -> void:
	if pawn == null: return
	var diff: float = angle_difference(pawn.rotation, rotation)
	var max_step: float = pawn.angular_speed * delta
	if abs(diff) >= max_step: angular_input = sign(diff)
	else: angular_input = 0

const IDLE_DISTANCE: float = 1.0
const IDLE_STUCK_RESET: float = 10.0
func apply_linear_input() -> void:
	if is_aiming:
		linear_input = 0
		return
	if not $IdleStartCooldown.is_stopped(): return
	if is_reversing and $IdleEndCooldown.is_stopped():
		linear_input = -1
		return
	linear_input = 1
	if not $IdleEndCooldown.is_stopped():
		if position.distance_to($NavAgent.get_next_path_position()) < IDLE_STUCK_RESET and is_patrol_set:
			$NavAgent.target_position = target.position
		return
	var next_point: Vector2 = $NavAgent.get_next_path_position()
	if abs(position.distance_to(next_point) - previous_position.distance_to(next_point)) <= IDLE_DISTANCE:
		linear_input = 0
		$IdleStartCooldown.start()

func _on_idle_start_cooldown_timeout() -> void:
	$IdleEndCooldown.start()

const LONG_RANGE_SHOOT_DISTANCE: float = 1300.0
@onready var MEDIUM_RANGE_SHOOT_DISTANCE: float = $NavAgent.target_desired_distance
func configure_target_reach_distance() -> void:
	if target.get_meta("entity_type", "null") == "crate":
		$NavAgent.target_desired_distance = CRATE_DESIRED_DISTANCE
	else:
		if pawn.weapon_type == "laser": TARGET_DESIRED_DISTANCE = LONG_RANGE_SHOOT_DISTANCE
		else: TARGET_DESIRED_DISTANCE = MEDIUM_RANGE_SHOOT_DISTANCE
		$NavAgent.target_desired_distance = TARGET_DESIRED_DISTANCE

## randomly set by ingame manager when the controller is created
var is_stopping_to_aim: bool = true

const MAX_SHOOT_ANGLE_DIFFERENCE: float = PI/180 * 15.0
func configure_aiming() -> void:
	is_aiming = false
	if target == null: return
	if is_dodging_bullets: return
	if is_adjacent_wall_to_target: return
	if not $NavAgent.is_navigation_finished(): return
	if target.get_meta("entity_type", "null") == "crate": return
	var auxiliary: float = rotation
	var direction_to_player: float
	look_at(target.position)
	direction_to_player = rotation
	rotation = auxiliary
	if not is_stopping_to_aim:
		if abs(angle_difference(pawn.rotation, direction_to_player)) > MAX_SHOOT_ANGLE_DIFFERENCE: return
	is_aiming = true
	var was_patroling: bool = is_patrol_set
	is_patrol_set = false
	var direction_deviation: float = randf_range(-DIRECTION_DEVIATION, DIRECTION_DEVIATION)
	rotation = direction_to_player + direction_deviation
	if abs(angle_difference(pawn.rotation, direction_to_player)) > MAX_SHOOT_ANGLE_DIFFERENCE: return
	if not $ShootingCooldown.is_stopped(): return
	if was_patroling: return
	$ShootingCooldown.start()
	direction_deviation = randf_range(-DIRECTION_DEVIATION, DIRECTION_DEVIATION)
	rotation += direction_deviation
	pawn.shoot()

func idle_if_no_tanks() -> bool:
	if not tanks_exist and not is_dodging_bullets:
		linear_input = 0
		angular_input = 0
		return true
	return false

var is_aiming: bool = false

## run expensive scans only every AI_TICKS-th physics frame, staggered per bot
const AI_TICKS: int = 4
var ai_tick: int = 0

func ai_tick_skipped() -> bool:
	ai_tick = (ai_tick + 1) % AI_TICKS
	return ai_tick != abs(sid * 9973) % AI_TICKS

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server(): return
	if OS.get_environment("BL_DEBUG_BOTS_OFF") == "1": return
	if pawn == null or not is_instance_valid(pawn): return
	if pawn.get_node(^"Rest").visible == false: return
	if IngameManager.ingame_container.get_child_count() == 0: return
	global_position = pawn.global_position
	rotation = pawn.rotation
	if not ai_tick_skipped():
		determine_target()
		check_nearby_bullets()
		configure_patrol()
	if idle_if_no_tanks(): return
	determine_if_wall_to_target()
	point_to_target_if_seen()
	configure_nav_agent_process()
	configure_reversing()
	configure_target_reach_distance()
	configure_aiming()
	var next_point: Vector2 = $NavAgent.get_next_path_position()
	var direction: Vector2 = (next_point - global_position).normalized()
	if target != null:
		rotation = lerp_angle(rotation, direction.angle(), ROTATION_INTERPOLATION_WEIGHT)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if target != null or is_dodging_bullets:
		rotation += rng.randf_range(-ANGLE_DILATION, ANGLE_DILATION)
	if not $PathStuckDelay.is_stopped():
		initial_path_stuck_distance = global_position.distance_to($NavAgent.get_next_path_position())
		$PathStuckDelay.start()
	apply_angular_input(delta)
	apply_linear_input()
	previous_position = position
	previous_rotation = rotation

var initial_path_stuck_distance: float = 0.0
const PATH_STUCK_DISTANCE: float = 3000.0
func _on_path_stuck_delay_timeout() -> void:
	var current_polygon_distance: float = global_position.distance_to($NavAgent.get_next_path_position())
	if current_polygon_distance > PATH_STUCK_DISTANCE: return
	if abs(current_polygon_distance - initial_path_stuck_distance) <= 10.0: is_path_stuck = true

@onready var TARGET_DESIRED_DISTANCE: float = $NavAgent.target_desired_distance
const CRATE_DESIRED_DISTANCE: float = 5.0
const TARGET_PATROL_DISTANCE: float = 400.0

## modified by ingame manager so it depends on the attached pawn's linear speed
var MAX_STUCK_POSITION_CHANGE: float = 3.2

var previous_position: Vector2 = Vector2.ZERO
var previous_rotation: float = 0.0

const WALL_RAYCAST_OFFSET: float = 20.0
var is_adjacent_wall_to_target: bool = false
func determine_if_wall_to_target() -> void:
	is_adjacent_wall_to_target = false
	if target == null: return
	if target.get_meta("entity_type", "null") == "crate": return
	for raycast: RayCast2D in $WallRaycasts.get_children():
		#raycast.rotation = -rotation
		raycast.global_position = pawn.global_position
		raycast.target_position = raycast.to_local(target.global_position)
		var deviation: Vector2 = (raycast.target_position - raycast.global_position).normalized()
		if raycast.name == "Left": deviation = deviation.rotated(-PI/2) * WALL_RAYCAST_OFFSET
		if raycast.name == "Center": deviation = Vector2.ZERO
		if raycast.name == "Right": deviation = deviation.rotated(PI/2) * WALL_RAYCAST_OFFSET
		raycast.target_position += deviation
		if not raycast.is_colliding(): continue
		is_adjacent_wall_to_target = true
		return

func point_to_target_if_seen() -> void:
	if target == self: return
	for ray: RayCast2D in $TankDetectors.get_children():
		if ray.get_collider() != target: continue
		$NavAgent.target_position = target.global_position
		if global_position.distance_to(target.global_position) >= FLANK_RADIUS:
			is_patrol_set = true
		else: is_patrol_set = false
		return

var FLANK_RESET: float = 800.0
var FLANK_RADIUS: float = 500.0
var FLANK_MIN_INTERVAL: float = 50.0
var FLANK_MAX_INTERVAL: float = 200.0
var FLANK_FRONT_DISTANCE: float = 400.0
const DIRECTION_DEVIATION: float = PI/180*10
var is_patrol_set: bool = false
var is_reversing: bool = false

var tanks_exist: bool = false
func determine_target() -> void:
	target = null
	tanks_exist = false
	for tank: RigidBody2D in IngameManager.ingame_container.get_child(0).get_node(^"TankPawns").get_children():
		if tank == pawn: continue
		if tank.get_node("Rest").visible == false: continue
		tanks_exist = true
		if target == null:
			target = tank
			continue
		if global_position.distance_to(tank.position) < global_position.distance_to(target.position):
			target = tank
	for crate: Area2D in IngameManager.ingame_container.get_child(0).get_node(^"Crates").get_children():
		if pawn.weapon_type != "regular": break
		if target == null:
			target = crate
			continue
		if global_position.distance_to(crate.position) < global_position.distance_to(target.position):
			target = crate
	if target == null:
		$NavAgent.target_desired_distance = 0.0
		return
	if is_patrol_set: return
	if target.get_meta("entity_type", "null") == "crate":
		$NavAgent.target_desired_distance = CRATE_DESIRED_DISTANCE
	else: $NavAgent.target_desired_distance = TARGET_DESIRED_DISTANCE

var is_path_stuck: bool = false
func configure_patrol() -> void:
	if target == null:
		$NavAgent.target_position = global_position
		is_patrol_set = false
		return
	if is_path_stuck:
		is_path_stuck = false
		$NavAgent.target_position = target.position
		is_patrol_set = true
		return
	if global_position.distance_to(target.global_position) >= FLANK_RESET:
		$NavAgent.target_position = target.global_position
		is_patrol_set = false
	elif global_position.distance_to(target.global_position) >= FLANK_RADIUS:
		if is_patrol_set: return ## ensures that this block only executes once when it detects a change in radius
		var random_sign: float
		var random_x: float = randf_range(FLANK_MIN_INTERVAL, FLANK_MAX_INTERVAL)
		random_sign = sign(randi_range(0,1))*2-1
		random_x *= random_sign
		var random_y: float = randf_range(FLANK_MIN_INTERVAL, FLANK_MAX_INTERVAL)
		random_sign = sign(randi_range(0,1))*2-1
		random_y *= random_sign
		var random_offset: Vector2 = Vector2(random_x, random_y)
		$NavAgent.target_position = target.global_position + random_offset
		if target.linear_velocity.length() >= 0.1:
			var offset: Vector2 = Vector2(FLANK_FRONT_DISTANCE, 0)
			$NavAgent.target_position += offset * target.linear_velocity.angle()
		is_patrol_set = true
	else:
		$NavAgent.target_position = target.global_position
		is_patrol_set = false
	if is_patrol_set: $NavAgent.target_desired_distance = TARGET_PATROL_DISTANCE
	else: $NavAgent.target_desired_distance = TARGET_DESIRED_DISTANCE

func configure_reversing() -> void:
	if is_aiming: return
	var is_stuck: bool = (previous_position - global_position).length() <= MAX_STUCK_POSITION_CHANGE
	if not is_reversing and not $NavAgent.is_target_reached() and is_stuck:
		is_stuck = false
		is_reversing = true
		$WallStuckCooldown.start()
	elif $WallStuckCooldown.is_stopped(): is_reversing = false
	if is_reversing and is_stuck:
		is_stuck = false
		is_reversing = false
		$WallStuckCooldown.stop()
	if is_dodging_bullets:
		is_reversing = false
		$WallStuckCooldown.stop()

func configure_nav_agent_process() -> void:
	if target == null: $NavAgent.process_mode = Node.PROCESS_MODE_DISABLED
	else: $NavAgent.process_mode = Node.PROCESS_MODE_INHERIT

func check_nearby_bullets() -> void:
	is_dodging_bullets = false
	for bullet: CollisionObject2D in $BulletDetectionArea.get_overlapping_bodies():
		if not is_bullet_dangerous(bullet): return
		is_dodging_bullets = true
		dodge_bullet(bullet)

@export var BULLET_DANGER_SENSITIVITY: float = 0.4
func is_bullet_dangerous(bullet: RigidBody2D) -> bool:
	if bullet == null or not is_instance_valid(bullet): return false
	if bullet.get_meta("entity_type", "NULL") != "bullet": return false
	if (previous_position - global_position).length() == 0.0:
		var is_raycast_hitting_bot: bool = bullet.get_node(^"Rest/VelocityRaycast1").get_collider() == self
		is_raycast_hitting_bot = is_raycast_hitting_bot or bullet.get_node(^"Rest/VelocityRaycast2").get_collider() == self
		is_raycast_hitting_bot = is_raycast_hitting_bot or bullet.get_node(^"Rest/VelocityRaycast3").get_collider() == self
		if not is_raycast_hitting_bot: return false
	var distance_to_bot: Vector2 = global_position - bullet.global_position
	var bullet_velocity_direction: Vector2 = bullet.linear_velocity.normalized()
	## dot product is positive if bullet is moving towards the bot
	return distance_to_bot.normalized().dot(bullet_velocity_direction) > BULLET_DANGER_SENSITIVITY

## whether it's a bullet is verified by the is_bullet_dangerous() function
const PERPENDICULAR_VELOCITY_DOT_OFFSET: float = 75.0
const DODGE_INTERPOLATE_FACTOR: float = 2.7
@export var ROTATION_INTERPOLATION_WEIGHT: float = 0.25
@export var ANGLE_DILATION: float = 0.1
func dodge_bullet(bullet: RigidBody2D) -> void:
	var bullet_velocity_direction: Vector2 = bullet.linear_velocity.normalized()
	var left_bullet_dot: Vector2 = bullet.global_position
	var right_bullet_dot: Vector2 = bullet.global_position
	var left_offset_vector: Vector2 = Vector2(PERPENDICULAR_VELOCITY_DOT_OFFSET, 0).rotated(bullet_velocity_direction.angle() - PI/2)
	left_bullet_dot += left_offset_vector
	right_bullet_dot -= left_offset_vector
	var chosen_direction: Vector2
	$DEBUGLeftBulletDot.global_position = left_bullet_dot
	$DEBUGRightBulletDot.global_position = right_bullet_dot
	
	$NavAgent.target_desired_distance = 0.0
	## left bullet dot navigation distance
	$NavAgent.target_position = left_bullet_dot
	var navigation_path: PackedVector2Array = $NavAgent.get_current_navigation_path()
	var navigation_distance_to_left: float = 0.0
	for i: int in range(navigation_path.size() - 1):
		navigation_distance_to_left += navigation_path[i].distance_to(navigation_path[i + 1])
	## right bullet dot navigation distance
	$NavAgent.target_position = right_bullet_dot
	navigation_path = $NavAgent.get_current_navigation_path()
	var navigation_distance_to_right: float = 0.0
	for i: int in range(navigation_path.size() - 1):
		navigation_distance_to_right += navigation_path[i].distance_to(navigation_path[i + 1])
	## final navigation distance
	if target == null: $NavAgent.target_position = bullet.global_position
	else: $NavAgent.target_position = target.global_position
	var left_is_closer_than_right_navigation: bool = navigation_distance_to_left < navigation_distance_to_right
	var left_is_closer_than_right_euclidean: bool = global_position.distance_to(left_bullet_dot) < global_position.distance_to(right_bullet_dot)
	if navigation_distance_to_left != navigation_distance_to_right:
		if left_is_closer_than_right_navigation:
			chosen_direction = left_bullet_dot
		else: chosen_direction = right_bullet_dot
	elif left_is_closer_than_right_euclidean:
		chosen_direction = left_bullet_dot
	else: chosen_direction = right_bullet_dot
	var auxiliary: float = rotation
	look_at(chosen_direction)
	var dodge_angle: float = rotation
	rotation = auxiliary
	rotation = lerp_angle(pawn.rotation, dodge_angle, ROTATION_INTERPOLATION_WEIGHT * DODGE_INTERPOLATE_FACTOR)
