extends RigidBody2D

var controller: Node = null

var max_linear_speed: float = 200.0
var linear_speed: float = 200.0
var drift_speed: float = 600.0
var angular_speed: float = 6.0

var max_bullet_count: int = 5
var fired_bullet_count: int = 0

const REGULAR_SPAWN_OFFSET: float = 30.0
const ROCKET_SPAWN_OFFSET: float = 40.0
const LASER_SPAWN_OFFSET: float = 30.0
const TRAP_SPAWN_OFFSET: float = 60.0

var regular_speed: float = 300.0
var regular_lifespan: float = 0.0
var laser_speed: float = 3000.0
var laser_lifespan: float = 1.0
var rocket_speed: float = 300.0
var rocket_lifespan: float = 15.0
var trap_speed: float = 700.0

var weapon_type: String = "regular"

var label_node: Label

func _notification(what: int) -> void:
	if what != NOTIFICATION_SCENE_INSTANTIATED: return
	label_node = %NameLabel

func toggle(value: bool) -> void:
	if value:
		visible = true
		process_mode = Node.PROCESS_MODE_INHERIT
	elif not $Rest.visible:
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	$Sync.set_multiplayer_authority(1)
	#if not multiplayer.is_server(): set_physics_process(false) ## disabled for client-side prediction

signal shoot_bullet
func shoot() -> void:
	if not multiplayer.is_server(): return
	if not $ShootCooldown.is_stopped(): return
	if fired_bullet_count >= max_bullet_count and weapon_type == "regular":
		MasterManager.play_server_sound($NoAmmoNoise)
		return
	for body: Node2D in $TunnelHitbox.get_overlapping_bodies():
		if body is StaticBody2D: return
	shoot_bullet.emit(weapon_type, self)
	$ShootCooldown.start()

const SKIN_PATH_PREFIX: String = "res://ingame/entities/tank_pawn/tank_"
const SKIN_EXTENSION: String = ".png"
@rpc("authority", "reliable", "call_local")
func equip_weapon(type: String) -> void:
	weapon_type = type
	$Rest/Image.texture = load(SKIN_PATH_PREFIX + type + SKIN_EXTENSION)

func _physics_process(_delta: float) -> void:
	if not controller:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		return
	if not controller.is_drifting:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
	angular_velocity = controller.angular_input * angular_speed
	var forward_direction := Vector2.RIGHT.rotated(rotation)
	if controller.is_drifting: apply_central_force(forward_direction * sign(controller.linear_input) * drift_speed)
	else: apply_central_impulse(forward_direction * sign(controller.linear_input) * linear_speed)
	if linear_velocity.length() > max_linear_speed: linear_velocity = linear_velocity.normalized() * max_linear_speed
	if not multiplayer.is_server(): return

var is_invincible: bool = false
## called by bullet scenes that hit the player
func die() -> void:
	if is_invincible: return
	print("BLTRACE pawn_die start sid=", controller.sid if (controller != null and is_instance_valid(controller)) else -999)
	$Rest.visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	## engine work (particles, death bookkeeping) must leave the physics callback
	call_deferred("_die_deferred")

func _die_deferred() -> void:
	$DeathParticles.restart()
	print("BLTRACE pawn_die particles restarted")
	if controller != null and is_instance_valid(controller):
		SessionManager.increment_death(controller.sid)
	print("BLTRACE pawn_die death incremented")
	IngameManager._on_tank_die()
	print("BLTRACE pawn_die on_tank_die returned")
