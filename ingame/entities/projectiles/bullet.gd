extends RigidBody2D

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## initialised by parent level node right after instantiation:
## used for correcting the position of the bullet when it touches a wall in the first frame, in order
##		to prevent wall tunneling
var initial_velocity_direction: float
var initial_velocity_speed: float
var owner_node: RigidBody2D = null

var target: Node2D = null

var type: String = "null"

const ROCKET_TEXTURE_PATH: String = "res://ingame/entities/projectiles/bullet_rocket.png"
const ROCKET_SCALE_MODIFIER_TEXTURE: float = 4.2
const ROCKET_SCALE_MODIFIER_REST: float = 0.3
const TRAP_TEXTURE_PATH: String = "res://ingame/entities/projectiles/bullet_trap.png"
const TRAP_SCALE_MODIFIER_TEXTURE: float = 4.2
const TRAP_SCALE_MODIFIER_REST: float = 0.4
func _ready() -> void:
	if multiplayer.is_server(): process_mode = Node.PROCESS_MODE_INHERIT
	else: process_mode = Node.PROCESS_MODE_DISABLED
	if type == "laser": $Rest/LaserTrail.emitting = true
	apply_central_impulse(Vector2(initial_velocity_speed, 0).rotated(initial_velocity_direction))
	if type == "rocket":
		$RocketNavigation.process_mode = Node.PROCESS_MODE_INHERIT
		$Rest/Image.texture = load(ROCKET_TEXTURE_PATH)
		$Rest/Image.scale = Vector2.ONE * ROCKET_SCALE_MODIFIER_TEXTURE
		$Hitbox.scale = Vector2.ONE * ROCKET_SCALE_MODIFIER_REST
		$Rest.scale = Vector2.ONE * ROCKET_SCALE_MODIFIER_REST
		$RocketDelay.start()
	if type == "trap":
		$Rest/Image.texture = load(TRAP_TEXTURE_PATH)
		$Rest/Image.scale = Vector2.ONE * TRAP_SCALE_MODIFIER_TEXTURE
		$Hitbox.scale = Vector2.ONE * TRAP_SCALE_MODIFIER_REST
		$Rest.scale = Vector2.ONE * TRAP_SCALE_MODIFIER_REST
		#$AnimationPlayer.play(&"hide_trap")
	if type != "trap": $LifespanTimer.start()

func determine_closest_target() -> void:
	var result: Node2D = owner_node if is_instance_valid(owner_node) else null
	for tank: RigidBody2D in IngameManager.ingame_container.get_child(0).get_node("TankPawns").get_children():
		if tank.get_node("Rest").visible == false: continue
		if result == null or result.get_node("Rest").visible == false:
			result = tank
			continue
		if position.distance_to(tank.position) <= position.distance_to(result.position):
			result = tank
	if result == null: return
	$RocketNavigation.target_position = result.position
	target = result

func _on_rocket_delay_timeout() -> void:
	MasterManager.play_server_sound($RocketActivate)

const ROCKET_MAX_TURN_SPEED: float = 0.06
func configure_if_rocket() -> void:
	if type != "rocket": return
	if not $RocketDelay.is_stopped(): return
	#var random_turn: float = rng.randf_range(-ROCKET_MAX_TURN_SPEED, ROCKET_MAX_TURN_SPEED)
	#linear_velocity = linear_velocity.rotated(random_turn)
	determine_closest_target()
	var next_point: Vector2 = $RocketNavigation.get_next_path_position()
	var direction: Vector2 = (next_point - global_position).normalized()
	var proper_rotation: float = linear_velocity.angle()
	if target != null:
		$Rest/RocketTrail.emitting = target.get_node("Rest").visible
		if target.get_node("Rest").visible:
			proper_rotation = lerp_angle(proper_rotation, direction.angle(), ROCKET_MAX_TURN_SPEED)
	linear_velocity = (Vector2.RIGHT * linear_velocity.length()).rotated(proper_rotation)

const TRAP_DECAY_SPEED: float = 1.02
var TRAP_HIDE_DISTANCE: float = 30.0
func configure_if_trap() -> void:
	if type != "trap": return
	initial_velocity_speed /= TRAP_DECAY_SPEED
	if initial_velocity_speed <= TRAP_HIDE_DISTANCE:
		play_animation.rpc("hide_trap")
		initial_velocity_speed = 0.0
		TRAP_HIDE_DISTANCE = -1.0

@rpc("authority", "unreliable", "call_local")
func play_animation(animation: String) -> void:
	if not $AnimationPlayer.has_animation(animation): return
	$AnimationPlayer.play(animation)

func set_node_rotations() -> void:
	$Rest/VelocityRaycast1.rotation = linear_velocity.angle() - PI/2
	$Rest/VelocityRaycast2.rotation = linear_velocity.angle() - PI/2 - PI/60
	$Rest/VelocityRaycast3.rotation = linear_velocity.angle() - PI/2 + PI/60
	if type != "trap": $Rest/Image.rotation = linear_velocity.angle()

func _physics_process(_delta: float) -> void:
	if linear_velocity.length() != 0.0: linear_velocity = linear_velocity.normalized() * initial_velocity_speed
	configure_if_rocket()
	configure_if_trap()
	set_node_rotations()

func _on_lifespan_timer_timeout() -> void:
	die("lifespan")

func _on_body_entered(body: Node) -> void:
	if not $Rest.visible: return
	## engine queues body_entered signals; the other side of the contact
	## may be freed before delivery -> get_meta on a dead object segfaults
	if body == null or not is_instance_valid(body): return
	if body.get_meta("entity_type", "NULL") == "wall":
		if type == "laser": MasterManager.play_server_sound($BounceLaser)
		elif type == "trap": MasterManager.play_server_sound($BounceTrap)
		else: MasterManager.play_server_sound($BounceRegular)
	if body.get_meta("entity_type", "NULL") == "tank":
		if body.controller != null and is_instance_valid(owner_node) and owner_node.controller != null:
			if body.controller.sid != owner_node.controller.sid and not body.is_invincible:
				SessionManager.increment_kill(owner_node.controller.sid)
		body.die()
		die("tank")
	if body.get_meta("entity_type", "NULL") == "bullet":
		body.die("bullet")
		die("bullet")

func disable_process_mode() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED

func die(cause: String) -> void:
	print("BLTRACE bullet_die cause=", cause, " type=", type)
	$Rest.visible = false
	if type == "regular" and is_instance_valid(owner_node): owner_node.fired_bullet_count -= 1
	## engine work (particles, audio rpc, queue_free) must leave the physics callback
	call_deferred("_die_deferred", cause)

func _die_deferred(cause: String) -> void:
	disable_process_mode()
	if cause == "lifespan":
		if multiplayer.is_server(): queue_free()
		return
	if cause == "tank":
		$DespawnParticles.restart()
		return
	if cause == "bullet":
		$DespawnParticles.restart()
		MasterManager.play_server_sound($BulletHit)
		return

func _on_despawn_particles_finished() -> void:
	if multiplayer.is_server(): queue_free()
