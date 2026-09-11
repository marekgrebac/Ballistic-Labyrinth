extends MultiplayerSynchronizer

var sid: int = 0
var pawn: Node = null

func set_sid(id: int) -> void:
	if id <= 0: return
	sid = id
	set_multiplayer_authority(id)

func set_pawn() -> void:
	if pawn == null: return

## if < 0 move backwards
## if = 0 idle
## if > 0 move forwards
@export var linear_input: int = 0

## if < 0 rotate counterclockwise
## if = 0 idle
## if > 0 rotate clockwise
@export var angular_input: int = 0

@export var is_drifting: bool = false

func _ready() -> void:
	set_process(is_multiplayer_authority())

func _process(_delta: float) -> void:
	if UIManager.is_ui_configured:
		if UIManager.chat_menu_node.is_blocked: return
	linear_input = int(Input.get_axis(&"MoveBackward", &"MoveForward"))
	angular_input = int(Input.get_axis(&"RotateCounterclockwise", &"RotateClockwise"))
	is_drifting = Input.is_action_pressed(&"Drift")
	if Input.is_action_just_pressed(&"Shoot"): request_shoot()
	if Input.is_action_just_pressed(&"Teleport"):
		if IngameManager.ingame_container.get_child_count() == 0: return
		if not SessionManager.is_op(multiplayer.get_unique_id()): return
		var mouse_position: Vector2 = IngameManager.ingame_container.get_child(0).get_global_mouse_position()
		IngameManager.teleport_tank.rpc_id(1, mouse_position)
	if Input.is_action_just_pressed(&"Invincibility"):
		if not SessionManager.is_op(multiplayer.get_unique_id()): return
		IngameManager.change_invincibility.rpc_id(1)
	if Input.is_action_just_pressed(&"NoClip"):
		if not SessionManager.is_op(multiplayer.get_unique_id()): return
		IngameManager.change_noclip.rpc_id(1)

func request_shoot() -> void:
	if not NetworkManager.is_online: return
	if multiplayer.is_server():
		if pawn == null or not is_instance_valid(pawn): return
		pawn.shoot()
		return
	rpc_shoot.rpc_id(1)

@rpc("any_peer", "reliable")
func rpc_shoot() -> void:
	if pawn == null or not is_instance_valid(pawn): return
	pawn.shoot()
