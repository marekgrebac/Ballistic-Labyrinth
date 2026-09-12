extends Area2D

# needed for making bot target as crate work(temporary fix)
var linear_velocity: Vector2 = Vector2.ZERO

## self variables determind by the level scene:
## position

## these variables will be set by the level scene
# no such variables for now

## the dictionary is only going to be used for selecting a random type:
## managing types by integer IDs is kinda bad when adding dozens of weapons
const TYPE_DICTIONARY: Dictionary = {
	1: "laser",
	2: "rocket",
	3: "trap"
}

## may be overwritten by spawn function before network_ready executes
var type: String = "null"

const TEXTURE_PATH_PREFIX: String = "res://ingame/entities/crates/crate_"
const TEXTURE_EXTENSION: String = ".png"

var rng_seed: int = 0

func network_ready() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed
	if type == "null": type = TYPE_DICTIONARY[rng.randi_range(1, TYPE_DICTIONARY.size())]
	$Image.texture = load(TEXTURE_PATH_PREFIX + type + TEXTURE_EXTENSION)
	rotation = rng.randf_range(-PI, PI)

signal equip_weapon(tank: RigidBody2D, type: String)
func _on_body_entered(body: Node2D) -> void:
	if body == null or not is_instance_valid(body): return
	if body.get_meta("entity_type", "NULL") != "tank": return
	if body.weapon_type != "regular": return
	equip_weapon.emit(body, type)
	if multiplayer.is_server(): queue_free()
