extends Node

const INGAME_CAMERA_ZOOM: float = 2.0

## those variables are modified by the origin scene(origin.tscn)
var DEBUG_is_checking_maze: bool = false
var DEBUG_is_showing_dodging: bool = false
var bot_friendly_fire: bool = true
var maze_carve_offset: Vector2i = Vector2i.ZERO
var player_color: Color = Color.WHITE

signal dimensions_finished
#signal carve_finished
signal generation_finished
#signal wall_remove_finished

var is_finished_loading: bool = false

const MAZE_GENERATION_NOISE_VARIANCE: float = 0.1
@onready var MAZE_GENERATION_NOISE_SCALE: float = $Sounds/MazeGenerationNoise.pitch_scale

@onready var scale_ratio: int = $Map/Ground.scale.x / $Map/Walls.scale.x

var SEEDED_RNG: RandomNumberGenerator = RandomNumberGenerator.new()

const CAMERA_MARGIN: float = 300.0
func setup_camera_and_background_noise() -> void:
	if not NetworkManager.is_dedicated_server:
		var maze_w: int = IngameManager.current_maze_dimensions.x
		var maze_h: int = IngameManager.current_maze_dimensions.y
		var first_cell: Vector2 = maze_cell_to_world(Vector2i.ZERO)
		var last_cell: Vector2 = maze_cell_to_world(Vector2i(maze_w - 1, maze_h - 1))
		$Camera.global_position = (first_cell + last_cell) / 2
		var rect_size: Vector2 = (first_cell - last_cell).abs() + Vector2.ONE * CAMERA_MARGIN
		var zoom: Vector2 = get_viewport().get_visible_rect().size
		zoom.x /= rect_size.x
		zoom.y /= rect_size.y
		var zoom_factor: float = max(0.01, min(zoom.x, zoom.y))
		$Camera.zoom = Vector2.ONE * zoom_factor
		#$Camera.position.x = $Map/Ground.tile_set.tile_size.x * $Map/Ground.scale.x * IngameManager.current_maze_dimensions.x / 2
		#$Camera.position.y = $Map/Ground.tile_set.tile_size.y * $Map/Ground.scale.y * IngameManager.current_maze_dimensions.y / 2
		#$Camera.zoom = Vector2.ONE * CAMERA_ZOOM_FACTOR / IngameManager.current_maze_dimensions.x / IngameManager.current_maze_dimensions.y
		$Map/GroundNoise.position = $Camera.position
	var texture_noise_seed: int = SEEDED_RNG.randi_range(0, 10000)
	if NetworkManager.is_dedicated_server: return
	$Map/GroundNoise.texture.noise.seed = texture_noise_seed

var is_generation_animated: bool = false

func configure_spawners() -> void:
	$Crates.spawn_function = spawn_crate
	$Bullets.spawn_function = IngameManager.spawn_bullet

func _ready() -> void:
	IngameManager.set_current_state(IngameManager.State.ANIMATING)
	is_generation_animated = false #IngameManager.current_is_animated_generation
	process_mode = Node.PROCESS_MODE_INHERIT
	SEEDED_RNG.seed = IngameManager.current_seed
	configure_spawners()
	setup_camera_and_background_noise()
	create_maze_rectangle()
	if is_generation_animated: await dimensions_finished
	generate_maze_with_randomized_prim()
	if is_generation_animated: await generation_finished
	remove_remaining_maze_cells()
	#remove_random_maze_walls()
	#if is_generation_animated: await wall_remove_finished
	implement_maze_edges_physics()
	implement_maze_walls_physics()
	implement_navigation()
	is_finished_loading = true
	IngameManager.current_is_animated_generation = true
	IngameManager.broadcast_generation_finish()


func activate_crate_spawn_timer() -> void:
	$Timers/CrateSpawnDelay.process_mode = Node.PROCESS_MODE_INHERIT
	$Timers/CrateSpawnDelay.start()

const SCROLL_VALUE: float = 1.1

signal finish_await
func _on_await_timeout() -> void:
	finish_await.emit()
func _on_main_menu_visibility_changed() -> void:
	finish_await.emit()

var maze_bottom_corner: Vector2i = Vector2i.ZERO
func create_maze_rectangle() -> void:
	for row: int in range(0, IngameManager.current_maze_dimensions.y):
		for column: int in range(0, IngameManager.current_maze_dimensions.x):
			if is_generation_animated:
				$Timers/Await.start()
				await finish_await
				$Sounds/DimensionsGenerationNoise.play()
			var selected_cell: Vector2i = Vector2i(column, row)
			$Map/Ground.set_cell(selected_cell, 0, Vector2i(0, 0), 1)
			maze_cells.push_back(selected_cell)
			create_maze_visual_wall(selected_cell, 0)
			create_maze_visual_wall(selected_cell, 1)
			create_maze_visual_wall(selected_cell, 2)
			create_maze_visual_wall(selected_cell, 3)
	dimensions_finished.emit()

var maze_cells: Array[Vector2i] = []
#func carve_maze_rectangle() -> void:
	#var effective_vertical_margins: Array[Vector2i] = []
	#var effective_horizontal_margins: Array[Vector2i] = []
	#
	### random crop at every margin: it doesn't keep track of the previous margin(neighbour) for now
	#var MAX_CARVE_LENGTH: int = min(MAZE_SIZE.x, MAZE_SIZE.y) / 3
	#var random_offset: int = SEEDED_RNG.randi_range(0, MAX_CARVE_LENGTH)
	#var result_interval: Vector2i
	#var result_cell: Vector2i
	#for x: int in range(0, MAZE_SIZE.x):
		#random_offset = SEEDED_RNG.randi_range(maze_carve_offset.x, maze_carve_offset.y)
		#result_interval.x = random_offset
		#random_offset = SEEDED_RNG.randi_range(maze_carve_offset.x, maze_carve_offset.y)
		#result_interval.y = MAZE_SIZE.y - 1 - random_offset
		#for y: int in range(result_interval.x, result_interval.y + 1):
			#result_cell = Vector2i(x, y)
			#effective_vertical_margins.append(result_cell)
			#$Map/VerticalIntervals.set_cell(result_cell, 0, Vector2i(0, 0), 3)
			#$SingleIntervalNoise.play()
			#await get_tree().create_timer(WAIT_TIME).timeout
	#for y: int in range(0, MAZE_SIZE.y):
		#random_offset = SEEDED_RNG.randi_range(maze_carve_offset.x, maze_carve_offset.y)
		#result_interval.x = random_offset
		#random_offset = SEEDED_RNG.randi_range(maze_carve_offset.x, maze_carve_offset.y)
		#result_interval.y = MAZE_SIZE.x - 1 - random_offset
		#for x: int in range(result_interval.x, result_interval.y + 1):
			#result_cell = Vector2i(x, y)
			#effective_horizontal_margins.append(result_cell)
			#$Map/HorizontalIntervals.set_cell(result_cell, 0, Vector2i(0, 0), 3)
			#if effective_vertical_margins.find(result_cell) != -1:
				#$DoubleIntervalNoise.play()
			#else: $SingleIntervalNoise.play()
			#await get_tree().create_timer(WAIT_TIME).timeout
	#
	#$Map/VerticalIntervals.clear()
	#$Map/HorizontalIntervals.clear()
	#for x: int in range(0, MAZE_SIZE.x):
		#for y: int in range(0, MAZE_SIZE.y):
			#var selected_cell: Vector2i = Vector2i(x, y)
			#await get_tree().create_timer(WAIT_TIME).timeout
			#$TerrainGenerationNoise.play()
			#if effective_vertical_margins.find(selected_cell) != -1:
				#if effective_horizontal_margins.find(selected_cell) != -1:
					#maze_cells.append(selected_cell)
					##$Map/Ground.set_cell(current_cell, 0, Vector2i(0, 0), 1) # redundant
					#create_maze_visual_wall(selected_cell, 0)
					#create_maze_visual_wall(selected_cell, 1)
					#create_maze_visual_wall(selected_cell, 2)
					#create_maze_visual_wall(selected_cell, 3)
					#continue
			#var random_index: int = SEEDED_RNG.randi_range(0, 1)
			#$Map/Ground.set_cell(selected_cell, 1, Vector2i(random_index, 0))
	#
	#carve_finished.emit()

## maze walls are accessed by two variables: one of the adjacent ground cells' map coordinates and
##	an integer that is 0, 1, 2 or 3 that marks on which direction the wall is positioned relative to the first variable

## for adjacency:
##	-	0 means right
##	-	1 means down
##	-	2 means left
##	-	3 means up

func get_maze_primary_wall(map_coordinates: Vector2i, adjacency: int) -> Vector2i:
	if adjacency <= -1 or adjacency >= 4: return Vector2i.ONE * -1
	# scale ratio has to effectively be an integer(for now, at least)
	var wall_coordinates: Vector2i
	wall_coordinates.x = (map_coordinates.x - map_coordinates.y) * scale_ratio
	wall_coordinates.y = (map_coordinates.x + map_coordinates.y) * scale_ratio
	if adjacency == 0:
		wall_coordinates.x += 1
		wall_coordinates.y += scale_ratio
	if adjacency == 1:
		wall_coordinates.x -= scale_ratio
		wall_coordinates.y += scale_ratio
	if adjacency == 2:
		wall_coordinates.x -= 1
	if adjacency == 3: ## it's already calculated for adjacency == 3 by default
		pass
	return wall_coordinates

func get_maze_primary_wall_increment(adjacency: int) -> Vector2i:
	if adjacency == 0: return Vector2i(-1, 1)
	if adjacency == 1: return Vector2i(1, 1)
	if adjacency == 2: return Vector2i(-1, 1)
	if adjacency == 3: return Vector2i(1, 1)
	return Vector2i.ZERO

func create_maze_visual_wall(map_coordinates: Vector2i, adjacency: int) -> void:
	if adjacency <= -1 or adjacency >= 4: return
	var wall_coordinates: Vector2i = get_maze_primary_wall(map_coordinates, adjacency)
	$Map/Walls.set_cell(wall_coordinates, 1, Vector2i.ZERO, (adjacency + 1) % 2)
	wall_coordinates += get_maze_primary_wall_increment(adjacency)
	$Map/Walls.set_cell(wall_coordinates, 1, Vector2i.ZERO, (adjacency + 1) % 2)

func delete_maze_visual_wall(map_coordinates: Vector2i, adjacency: int) -> void:
	if adjacency <= -1 or adjacency >= 4: return
	var wall_coordinates: Vector2i = get_maze_primary_wall(map_coordinates, adjacency)
	$Map/Walls.set_cell(wall_coordinates)
	wall_coordinates += get_maze_primary_wall_increment(adjacency)
	$Map/Walls.set_cell(wall_coordinates)

func maze_visual_wall_exists(map_coordinates: Vector2i, adjacency: int) -> bool:
	if adjacency <= -1 or adjacency >= 4: return false
	var result: int = $Map/Walls.get_cell_source_id(get_maze_primary_wall(map_coordinates, adjacency))
	if OS.is_debug_build() and DEBUG_is_checking_maze:
		print("maze_visual_wall_exists(", map_coordinates, ", ", adjacency, "): ", result)
	return $Map/Walls.get_cell_source_id(get_maze_primary_wall(map_coordinates, adjacency)) != -1

func get_visual_wall_world_coordinates(map_coordinates: Vector2i, adjacency: int) -> Vector2:
	if adjacency <= -1 or adjacency >= 4: return Vector2.ONE * -1
	var primary_wall: Vector2 = get_maze_primary_wall(map_coordinates, adjacency)
	var secondary_wall: Vector2 = Vector2i(primary_wall) + get_maze_primary_wall_increment(adjacency)
	primary_wall = $Map/Walls.map_to_local(primary_wall) / scale_ratio - Vector2(0, scale_ratio * 2)
	secondary_wall = $Map/Walls.map_to_local(secondary_wall) / scale_ratio - Vector2(0, scale_ratio * 2)
	return (primary_wall + secondary_wall) / 2

## direction == 0 means positive y axis
## direction == 1 means negative x axis
## direction == 2 means negative y axis
## direction == 3 means positive x axis
func modify_physics_wall_length(wall_node: StaticBody2D, wall_increment: int, direction: int) -> void:
	if direction <= -1 or direction >= 4: return
	var primary_wall: Vector2 = get_maze_primary_wall(Vector2i.ZERO, 1)
	var secondary_wall: Vector2 = Vector2i(primary_wall) + get_maze_primary_wall_increment(1)
	var unit_wall_length: float = ($Map/Walls.map_to_local(secondary_wall) - $Map/Walls.map_to_local(primary_wall)).x
	var int_is_positive_axis: int = int(direction == 0 or direction == 3) * 2 - 1
	# idk how to calculate magic_tile_offset for now, neither how to name it, but it makes the code work ;)
	var magic_tile_offset: int = 8
	if direction == 1 or direction == 3:
		wall_node.position.x += unit_wall_length * wall_increment / 2 * int_is_positive_axis
		wall_node.scale.x += (unit_wall_length * wall_increment / 2 + magic_tile_offset) * int_is_positive_axis
	if direction == 0 or direction == 2:
		wall_node.position.y += unit_wall_length * wall_increment / 2 * int_is_positive_axis
		wall_node.scale.y += (unit_wall_length * wall_increment / 2 + magic_tile_offset) * int_is_positive_axis

var MAX_PRIM_EXTRA_CELLS: int = 5
## Randomized Prim's Algorithm: it's the primary maze generating algorithm for this project
func generate_maze_with_randomized_prim() -> void:
	var selected_cell: Vector2i
	## all vector entries should be integers, but this is what Godot offers for optimisation
	var final_maze_cells: PackedVector2Array
	var frontier_cells: PackedVector2Array
	selected_cell = maze_cells[SEEDED_RNG.randi_range(0, maze_cells.size() - 1)]
	$Map/Ground.set_cell(selected_cell, 0, Vector2i((selected_cell.x + selected_cell.y) % 3, 0), 0)
	final_maze_cells.append(selected_cell)
	if maze_cells.find(selected_cell + Vector2i.RIGHT) != -1:
		frontier_cells.append(selected_cell + Vector2i.RIGHT)
		delete_maze_visual_wall(selected_cell, 0)
	if maze_cells.find(selected_cell + Vector2i.DOWN) != -1:
		frontier_cells.append(selected_cell + Vector2i.DOWN)
		delete_maze_visual_wall(selected_cell, 1)
	if maze_cells.find(selected_cell + Vector2i.LEFT) != -1:
		frontier_cells.append(selected_cell + Vector2i.LEFT)
		delete_maze_visual_wall(selected_cell, 2)
	if maze_cells.find(selected_cell + Vector2i.UP) != -1:
		frontier_cells.append(selected_cell + Vector2i.UP)
		delete_maze_visual_wall(selected_cell, 3)
	var selected_frontier_cell_index: int
	#var i: int = 0
	while frontier_cells.size() != 0:
		if is_generation_animated:
			$Timers/Await.start()
			await finish_await
			$Sounds/MazeGenerationNoise.play()
		if SEEDED_RNG.randi_range(0, 2) == 0:
			selected_frontier_cell_index = 0
		elif SEEDED_RNG.randi_range(0, 2) == 0:
			selected_frontier_cell_index = frontier_cells.size() - 1
		else: selected_frontier_cell_index = SEEDED_RNG.randi_range(0, frontier_cells.size() - 1)
		selected_cell = frontier_cells[selected_frontier_cell_index]
		frontier_cells.remove_at(selected_frontier_cell_index)
		configure_as_maze_cell(selected_cell, final_maze_cells, frontier_cells)
		if frontier_cells.size() == 0: break
		if SEEDED_RNG.randi_range(0, 4) == 0: continue
		## for removing some extra walls for more loops and space
		configure_as_maze_cell(frontier_cells[SEEDED_RNG.randi_range(0, frontier_cells.size() - 1)], final_maze_cells, frontier_cells)
		#i += 1
	generation_finished.emit()

func configure_as_maze_cell(selected_cell: Vector2i, final_maze_cells: PackedVector2Array, frontier_cells: PackedVector2Array) -> void:
	final_maze_cells.append(selected_cell)
	$Map/Ground.set_cell(selected_cell, 0, Vector2i((selected_cell.x + selected_cell.y) % 3, 0), 0)
	
	## remove one adjacent maze cell's wall
	## only one adjacent wall will be deleted(at least for now)
	## it will always yield at least one because the selected cell is a former frontier cell
	var num_neighboring_maze_cells: int = 0
	var possible_directions: Array[int] ## min size should be 1, max size should be 4
	var neighboring_cell_offset: Vector2i = Vector2i.RIGHT
	var selected_neighbor_cell: Vector2i
	for index: int in range(4):
		selected_neighbor_cell = selected_cell + Vector2i(neighboring_cell_offset)
		if maze_cells.find(selected_neighbor_cell) != -1:
			if final_maze_cells.find(selected_neighbor_cell) != -1:
				num_neighboring_maze_cells += 1
				possible_directions.append(index)
		neighboring_cell_offset = rotate_integer_vector(neighboring_cell_offset)
	var random_direction: int = possible_directions[SEEDED_RNG.randi_range(0, num_neighboring_maze_cells - 1)]
	delete_maze_visual_wall(selected_cell, random_direction)
	
	## mark neighboring cells as frontier cells
	neighboring_cell_offset = Vector2i.RIGHT
	for i: int in range(4):
		selected_neighbor_cell = selected_cell + neighboring_cell_offset
		if maze_cells.find(selected_neighbor_cell) != -1:
			if frontier_cells.find(selected_neighbor_cell) == -1:
				# this third if statement is a temporary fix for the problem of frontier cells not being removed when
				#	transformed to maze cells
				if final_maze_cells.find(selected_neighbor_cell) == -1:
					$Map/Ground.set_cell(selected_neighbor_cell, 0, Vector2i(0, 0), 2)
					frontier_cells.append(selected_neighbor_cell)
		neighboring_cell_offset = rotate_integer_vector(neighboring_cell_offset)

func rotate_integer_vector(vector: Vector2i) -> Vector2i:
	if vector == Vector2i.RIGHT: return Vector2i.DOWN
	if vector == Vector2i.DOWN: return Vector2i.LEFT
	if vector == Vector2i.LEFT: return Vector2i.UP
	if vector == Vector2i.UP: return Vector2i.RIGHT
	return Vector2i.ZERO ## invalid input handler

func remove_remaining_maze_cells() -> void:
	var selected_cell: Vector2i
	for x: int in range(0, IngameManager.current_maze_dimensions.x):
		for y: int in range(0, IngameManager.current_maze_dimensions.y):
			selected_cell = Vector2i(x, y)
			var is_black_cell: bool = $Map/Ground.get_cell_alternative_tile(selected_cell) == 1
			var is_visual_outside_cell: bool = $Map/Ground.get_cell_source_id(selected_cell) == 1
			var is_array_maze_cell: bool = maze_cells.find(selected_cell) != -1
			var is_invalid_outside_cell: bool = is_visual_outside_cell and is_array_maze_cell
			if is_black_cell or is_invalid_outside_cell:
				maze_cells.remove_at(maze_cells.find(selected_cell, 0))
				$Map/Ground.set_cell(selected_cell, 1, Vector2i(0, 0))
				for adjacency: int in range(4):
					var neighbor_cell: Vector2i = get_maze_cell_neighbor(selected_cell, adjacency)
					if maze_cells.find(neighbor_cell, 0) == -1:
						delete_maze_visual_wall(selected_cell, 0)
						delete_maze_visual_wall(selected_cell, 1)
						delete_maze_visual_wall(selected_cell, 2)
						delete_maze_visual_wall(selected_cell, 3)

#var wall_remove_interval: Vector2i = Vector2i(0, 0)
#func remove_random_maze_walls() -> void:
	#var remove_count: int = SEEDED_RNG.randi_range(wall_remove_interval.x, wall_remove_interval.y)
	#await get_tree().create_timer(0.01).timeout
	#if remove_count == 0:
		#wall_remove_finished.emit()
		#return
	#var removed: int = 0
	#while removed < remove_count:
		#await get_tree().create_timer(0.03).timeout
		#$Sounds/WallRemoveNoise.play()
		#var selected_cell: Vector2i = maze_cells.get(SEEDED_RNG.randi_range(0, maze_cells.size() - 1))
		#var possible_adjacencies: Array[int] = []
		#for selected_adjacency: int in range(4):
			#var selected_wall_exists: bool = maze_visual_wall_exists(selected_cell, selected_adjacency)
			#var selected_neighbor_is_maze_cell: bool = maze_cells.find(get_maze_cell_neighbor(selected_cell, selected_adjacency), 0) != -1
			#if selected_wall_exists and selected_neighbor_is_maze_cell:
				#possible_adjacencies.push_back(selected_adjacency)
		#if possible_adjacencies.size() == 0: continue
		#var deleted_adjacency: int = SEEDED_RNG.randi_range(0, possible_adjacencies.size() - 1)
		#deleted_adjacency = possible_adjacencies[deleted_adjacency]
		#delete_maze_visual_wall(selected_cell, deleted_adjacency)
		#removed += 1
	#wall_remove_finished.emit()

func get_maze_cell_neighbor(selected_cell: Vector2i, adjacency: int) -> Vector2i:
	if adjacency < 0 or adjacency > 3: return Vector2i.ONE * -1
	var result: Vector2i = selected_cell
	if adjacency == 0: result += Vector2i.RIGHT
	if adjacency == 1: result += Vector2i.DOWN
	if adjacency == 2: result += Vector2i.LEFT
	if adjacency == 3: result += Vector2i.UP
	return result

func implement_maze_edges_physics() -> void:
	var maze_corner: Vector2
	maze_corner.x = IngameManager.current_maze_dimensions.x * $Map/Ground.scale.x * $Map/Ground.scale.x / $Map/Walls.scale.x
	maze_corner.y = IngameManager.current_maze_dimensions.y * $Map/Ground.scale.y * $Map/Ground.scale.y / $Map/Walls.scale.y
	
	%RightEdgeWall.position.x = maze_corner.x
	%RightEdgeWall.position.y = maze_corner.y / 2
	%RightEdgeWall.scale.y = IngameManager.current_maze_dimensions.y * $Map/Ground.scale.y * $Map/Ground.scale.y / $Map/Walls.scale.y
	
	%DownEdgeWall.position.x = maze_corner.x / 2
	%DownEdgeWall.position.y = maze_corner.y
	%DownEdgeWall.scale.x = IngameManager.current_maze_dimensions.x * $Map/Ground.scale.x * $Map/Ground.scale.x / $Map/Walls.scale.x
	
	%LeftEdgeWall.position.x = 0
	%LeftEdgeWall.position.y = maze_corner.y / 2
	%LeftEdgeWall.scale.y = IngameManager.current_maze_dimensions.y * $Map/Ground.scale.y * $Map/Ground.scale.y / $Map/Walls.scale.y
	
	%UpEdgeWall.position.x = maze_corner.x / 2
	%UpEdgeWall.position.y = 0
	%UpEdgeWall.scale.x = IngameManager.current_maze_dimensions.x * $Map/Ground.scale.x * $Map/Ground.scale.x / $Map/Walls.scale.x
	for body: StaticBody2D in $Map/Edges.get_children():
		body.set_meta("entity_type", "wall")

const TILE_MAZE_WALL_PATH: String = "res://ingame/tiles/tile_maze_wall.png"
var EFFECTIVE_TILE_WIDTH: int = load(TILE_MAZE_WALL_PATH).get_width() - 1
func implement_maze_walls_physics() -> void:
	implement_maze_horizontal_walls_physics()
	implement_maze_vertical_walls_physics()
	for body: StaticBody2D in $Map/PhysicsWalls.get_children():
		body.set_meta("entity_type", "wall")

func new_collision_shape() -> CollisionShape2D:
	var physics_shape_ref: CollisionShape2D = CollisionShape2D.new()
	var shape_ref: RectangleShape2D = RectangleShape2D.new()
	#var temporary_debug: Texture2D = load(TEMPORARY_DEBUG_WALL_PHYSICS_TEXTURE_PATH)
	shape_ref.set_size(Vector2.ONE)
	physics_shape_ref.shape = shape_ref
	return physics_shape_ref

func print_debug_log(condition: bool, message: String) -> void:
	if not OS.is_debug_build(): return
	if not condition: return
	print(message)

func implement_maze_horizontal_walls_physics() -> void:
	var selected_cell: Vector2i
	var is_extending_wall: bool
	var physics_wall_ins: StaticBody2D
	print_debug_log(DEBUG_is_checking_maze, "\t\t\t\t\t\t\t\t\t\timplementing maze horizontal walls physics")
	for row: int in range(0, IngameManager.current_maze_dimensions.y - 1):
		print_debug_log(DEBUG_is_checking_maze, "on row: " + str(row))
		is_extending_wall = false
		for column: int in range(0, IngameManager.current_maze_dimensions.x):
			print_debug_log(DEBUG_is_checking_maze, "on column: " + str(column))
			selected_cell = Vector2i(column, row)
			print_debug_log(DEBUG_is_checking_maze, "selected cell: " + str(selected_cell))
			if maze_visual_wall_exists(selected_cell, 1) and not is_extending_wall:
				print_debug_log(DEBUG_is_checking_maze, "\t\tvisual wall exists and can initiate!")
				physics_wall_ins = StaticBody2D.new()
				var collision_shape: CollisionShape2D = new_collision_shape()
				physics_wall_ins.add_child(collision_shape)
				$Map/PhysicsWalls.add_child(physics_wall_ins)
				physics_wall_ins.owner = self
				physics_wall_ins.position = get_visual_wall_world_coordinates(selected_cell, 1)
				physics_wall_ins.scale.x = EFFECTIVE_TILE_WIDTH
				is_extending_wall = true
				continue
			if maze_visual_wall_exists(selected_cell, 1) and is_extending_wall:
				print_debug_log(DEBUG_is_checking_maze, "\t\tvisual wall exists and can extend!")
				modify_physics_wall_length(physics_wall_ins, 1, 3)
			if not maze_visual_wall_exists(selected_cell, 1):
				print_debug_log(DEBUG_is_checking_maze, "\t\t\tVISUAL WALL DOESN'T EXIST HERE...")
				is_extending_wall = false

func implement_maze_vertical_walls_physics() -> void:
	var selected_cell: Vector2i
	var is_extending_wall: bool
	var physics_wall_ins: StaticBody2D
	print_debug_log(DEBUG_is_checking_maze, "\t\t\t\t\t\t\t\t\t\timplementing maze vertical walls physics")
	for column: int in range(0, IngameManager.current_maze_dimensions.x - 1):
		print_debug_log(DEBUG_is_checking_maze, "on column: " + str(column))
		is_extending_wall = false
		for row: int in range(0, IngameManager.current_maze_dimensions.y):
			print_debug_log(DEBUG_is_checking_maze, "on row: " + str(row))
			selected_cell = Vector2i(column, row)
			print_debug_log(DEBUG_is_checking_maze, "selected cell: " + str(selected_cell))
			if maze_visual_wall_exists(selected_cell, 0) and not is_extending_wall:
				print_debug_log(DEBUG_is_checking_maze, "\t\tvisual wall exists and can initiate!")
				physics_wall_ins = StaticBody2D.new()
				var collision_shape: CollisionShape2D = new_collision_shape()
				physics_wall_ins.add_child(collision_shape)
				$Map/PhysicsWalls.add_child(physics_wall_ins)
				physics_wall_ins.owner = self
				physics_wall_ins.position = get_visual_wall_world_coordinates(selected_cell, 0)
				physics_wall_ins.scale.y = EFFECTIVE_TILE_WIDTH
				is_extending_wall = true
				continue
			if maze_visual_wall_exists(selected_cell, 0) and is_extending_wall:
				print_debug_log(DEBUG_is_checking_maze, "\t\tvisual wall exists and can extend!")
				modify_physics_wall_length(physics_wall_ins, 1, 0)
			if not maze_visual_wall_exists(selected_cell, 0):
				print_debug_log(DEBUG_is_checking_maze, "\t\t\tVISUAL WALL DOESN'T EXIST HERE...")
				is_extending_wall = false

# this function presupposes that at every maze cell has at least one accessible neighbour
# probably could be optimised
func implement_navigation() -> void:
	for row: int in range(0, IngameManager.current_maze_dimensions.y):
		for column: int in range(0, IngameManager.current_maze_dimensions.x):
			var directions: Array[bool]
			for i: int in range(4):
				directions.push_back(not maze_visual_wall_exists(Vector2i(column, row), i))
			var occurences: Array[int]
			occurences.push_back(directions.find(true, 0))
			occurences.push_back(directions.find(true, occurences[0] + 1))
			if occurences[1] == -1:
				$Map/Navigation.set_cell(Vector2(column, row), 0, Vector2i(1, 0), occurences[0])
				continue
			occurences.push_back(directions.find(true, occurences[1] + 1))
			if occurences[2] == -1:
				if (occurences[1] - occurences[0]) % 2 == 0:
					var is_alternative_tile: bool = (occurences[1] + occurences[0]) % 4 == 0
					$Map/Navigation.set_cell(Vector2(column, row), 0, Vector2i(0, 1), is_alternative_tile)
				else:
					if occurences[0] == 0 and occurences[1] == 3: ## because of looping, this is an exception to the rule
						$Map/Navigation.set_cell(Vector2(column, row), 0, Vector2i(2, 0), 0)
					else: $Map/Navigation.set_cell(Vector2(column, row), 0, Vector2i(2, 0), occurences[1])
				continue
			occurences.push_back(directions.find(true, occurences[2] + 1))
			if occurences[3] == -1:
				if occurences[0] == 0 and occurences[1] == 2 and occurences[2] == 3: ## because of looping, this is an exception to the rule
					$Map/Navigation.set_cell(Vector2(column, row), 0, Vector2i(1, 1), 0)
				elif occurences[0] == 0 and occurences[1] == 1 and occurences[2] == 3: ## because of looping, this is an exception to the rule
					$Map/Navigation.set_cell(Vector2(column, row), 0, Vector2i(1, 1), 1)
				else: $Map/Navigation.set_cell(Vector2(column, row), 0, Vector2i(1, 1), occurences[2])
				continue
			$Map/Navigation.set_cell(Vector2(column, row), 0, Vector2i(2, 1), 0)

## the selected cell doesn't need to be part of the maze
func maze_cell_to_world(selected_cell: Vector2i) -> Vector2:
	var result: Vector2 = $Map/Ground.map_to_local(selected_cell)
	result.x *= $Map/Ground.scale.x
	result.y *= $Map/Ground.scale.y
	return result

const GROUND_TILE_SET: String = "res://ingame/tiles/base_tileset.tres"
const OFFSET_SUBTRACT: float = 20.0
#func place_player_on_map() -> void:
	#var selected_cell: Vector2i
	##var ground_tile_size: Vector2i = load(GROUND_TILE_SET).tile_size
	#selected_cell = maze_cells.get(SEEDED_RNG.randi_range(0, maze_cells.size() - 1))
	#var selected_position: Vector2 = maze_cell_to_world(selected_cell)
	#$Players/Player.position = selected_position
	#var offset_vector: Vector2
	#var max_offset_scalar: Vector2 = $Map/Ground.scale / 2 - Vector2.ONE * OFFSET_SUBTRACT
	#offset_vector.x = SEEDED_RNG.randf_range(-max_offset_scalar.x, max_offset_scalar.x)
	#offset_vector.y = SEEDED_RNG.randf_range(-max_offset_scalar.y, max_offset_scalar.y)
	#$Players/Player.position += offset_vector
	#$Players/Player.rotation = SEEDED_RNG.randf_range(0, PI * 2)
	#$Players/Player.visible = true
	#$Players/Player.process_mode = Node.PROCESS_MODE_INHERIT
	##$Players/Player.modulate = player_color
	#alive_tanks_count += 1

const ENEMY_LINEAR_SPEED_DEVIATION: float = 30.0
const ENEMY_ANGULAR_SPEED_DEVIATION: float = 100.0
const ENEMY_MAX_BULLET_DEVIATION: int = 3
const ENEMY_FLANK_RESET_DEVIATION: float = 100.0
const ENEMY_FLANK_RADIUS_DEVIATION: float = 20.0
const ENEMY_FLANK_MIN_INTERVAL_DEVIATION: float = 100.0
const ENEMY_FLANK_MAX_INTERVAL_DEVIATION: float = 200.0
const ENEMY_FRONT_DISTANCE_DEVIATION: float = 200.0
func set_bot_personality(bot: RigidBody2D) -> void:
	bot.get_node("Rest/Image").modulate.r += 0.02*randf_range(-1.0, 1.0)
	bot.get_node("Rest/Image").modulate.g += 0.02*randf_range(-1.0, 1.0)
	bot.get_node("Rest/Image").modulate.b += 0.02*randf_range(-1.0, 1.0)
	bot.LINEAR_SPEED += randf_range(-ENEMY_LINEAR_SPEED_DEVIATION, ENEMY_LINEAR_SPEED_DEVIATION)
	bot.ANGULAR_SPEED += randf_range(-ENEMY_ANGULAR_SPEED_DEVIATION, ENEMY_ANGULAR_SPEED_DEVIATION)
	bot.MAX_BULLET_COUNT += randi_range(-ENEMY_MAX_BULLET_DEVIATION, ENEMY_MAX_BULLET_DEVIATION)
	bot.FLANK_RESET += randf_range(-ENEMY_FLANK_RESET_DEVIATION, ENEMY_FLANK_RESET_DEVIATION)
	bot.FLANK_RADIUS = bot.FLANK_RADIUS + randf_range(-ENEMY_FLANK_RADIUS_DEVIATION, ENEMY_FLANK_RADIUS_DEVIATION)
	bot.FLANK_MIN_INTERVAL += randf_range(-ENEMY_FLANK_MIN_INTERVAL_DEVIATION, ENEMY_FLANK_MIN_INTERVAL_DEVIATION)
	bot.FLANK_MAX_INTERVAL += randf_range(-ENEMY_FLANK_MAX_INTERVAL_DEVIATION, ENEMY_FLANK_MAX_INTERVAL_DEVIATION)
	bot.FLANK_FRONT_DISTANCE += randf_range(-ENEMY_FRONT_DISTANCE_DEVIATION, ENEMY_FRONT_DISTANCE_DEVIATION)

#@export var MIN_SPAWNPOINT_DISTANCING: float = 800.0
#var bot_count: int
#const NEW_ENEMY_INSTANCE_PATH: String = "res://ingame/entities/bot/bot.tscn"
#var bot_count_interval: Vector2i = Vector2i(3, 10)
#func place_bots_on_map() -> void:
	#bot_count = SEEDED_RNG.randi_range(bot_count_interval.x, bot_count_interval.y)
	#alive_tanks_count += bot_count
	#var tank_pawn: RigidBody2D = null
	#for index: int in range(0, bot_count):
		#tank_pawn = load(NEW_ENEMY_INSTANCE_PATH).instantiate()
		#set_bot_personality(tank_pawn)
		#$Bots.add_child(tank_pawn)
		#tank_pawn.global_position = $Players/Player.global_position
		#tank_pawn.player_parent_node = $Players
		#tank_pawn.bot_parent_node = $Bots
		#tank_pawn.crate_parent_node = $Crates
		#tank_pawn.bot_friendly_fire = bot_friendly_fire
		#while ($Players/Player.global_position - tank_pawn.global_position).length() <= MIN_SPAWNPOINT_DISTANCING:
			#tank_pawn.process_mode = Node.PROCESS_MODE_DISABLED
			#tank_pawn.visible = false
			#var selected_cell: Vector2i
			##var ground_tile_size: Vector2i = load(GROUND_TILE_SET).tile_size
			#selected_cell = maze_cells.get(SEEDED_RNG.randi_range(0, maze_cells.size() - 1))
			#var selected_position: Vector2 = maze_cell_to_world(selected_cell)
			#tank_pawn.position = selected_position
			#var offset_vector: Vector2
			#var max_offset_scalar: Vector2 = $Map/Ground.scale / 2 - Vector2.ONE * OFFSET_SUBTRACT
			#offset_vector.x = SEEDED_RNG.randf_range(-max_offset_scalar.x, max_offset_scalar.x)
			#offset_vector.y = SEEDED_RNG.randf_range(-max_offset_scalar.y, max_offset_scalar.y)
			#tank_pawn.position += offset_vector
			#tank_pawn.rotation = SEEDED_RNG.randf_range(0, PI * 2)
			#tank_pawn.visible = true
			#if not tank_pawn.is_connected("shoot", _on_bot_shoot):
				#tank_pawn.connect("shoot", _on_bot_shoot)
			#if not tank_pawn.is_connected("level_die", _on_bot_level_die):
				#tank_pawn.connect("level_die", _on_bot_level_die)
			#tank_pawn.process_mode = Node.PROCESS_MODE_INHERIT
			##tank_pawn.get_node("Rest/Image").scale += Vector2.ONE * SEEDED_RNG.randf_range(-0.1, 0.1)

const NEW_BULLET_PATH: String = "res://ingame/entities/projectiles/bullet.tscn"
const REGULAR_SPAWN_OFFSET: float = 26.0
const LASER_SPAWN_OFFSET: float = 26.0
const LASER_SPEED: float = 3000.0
const LASER_LIFESPAN: float = 1.0
const ROCKET_SPAWN_OFFSET: float = 30.0
const ROCKET_SPEED: float = 300.0
const ROCKET_LIFESPAN: float = 15.0
const TRAP_SPAWN_OFFSET: float = 60.0
const REGULAR_SPEED: float = 300.0

var bullet_ins: RigidBody2D = null
func _on_player_shoot(weapon_type: String) -> void:
	if weapon_type == "regular" and $Players/Player.bullet_count >= $Players/Player.MAX_BULLET_COUNT:
		$Sounds/NoAmmoNoise.play()
		return
	if weapon_type != "regular":
		$Players/Player.equip_weapon("regular")
	bullet_ins = load(NEW_BULLET_PATH).instantiate()
	var bullet_offset: float
	#var bullet_speed: float
	if weapon_type == "regular":
		bullet_offset = REGULAR_SPAWN_OFFSET
		bullet_ins.initial_velocity_speed = REGULAR_SPEED
		bullet_ins.type = "regular"
		$Sounds/NormalShootNoise.play()
	if weapon_type == "laser":
		bullet_offset = LASER_SPAWN_OFFSET
		bullet_ins.initial_velocity_speed = LASER_SPEED
		bullet_ins.get_node("LifespanTimer").wait_time = LASER_LIFESPAN
		bullet_ins.get_node("Rest/LaserTrail").emitting = true
		bullet_ins.type = "laser"
		$Sounds/LaserShootNoise.play()
	if weapon_type == "rocket":
		bullet_offset = ROCKET_SPAWN_OFFSET
		bullet_ins.initial_velocity_speed = ROCKET_SPEED
		bullet_ins.get_node("LifespanTimer").wait_time = ROCKET_LIFESPAN
		bullet_ins.type = "rocket"
		bullet_ins.room_node = self
		$Sounds/RocketShootNoise.play()
	if weapon_type == "trap":
		bullet_offset = TRAP_SPAWN_OFFSET
		bullet_ins.initial_velocity_speed = 0.0
		bullet_ins.type = "trap"
		$Sounds/TrapPlaceNoise.play()
	$Bullets.add_child(bullet_ins)
	bullet_ins.owner_node = $Players/Player
	bullet_ins.initial_velocity_direction = $Players/Player.rotation
	bullet_ins.position = $Players/Player.position + Vector2(bullet_offset, 0).rotated($Players/Player.rotation)
	if weapon_type != "trap": bullet_ins.connect("despawn", on_bullet_despawn)
	if weapon_type == "regular": $Players/Player.bullet_count += 1
	bullet_ins.modified_ready()
	bullet_ins.process_mode = Node.PROCESS_MODE_INHERIT

func _on_bot_shoot(bot: RigidBody2D, weapon_type: String) -> void:
	if weapon_type == "regular" and bot.bullet_count >= bot.MAX_BULLET_COUNT:
		$Sounds/NoAmmoNoise.play()
		return
	if weapon_type != "regular":
		bot.equip_weapon("regular")
	bullet_ins = load(NEW_BULLET_PATH).instantiate()
	var bullet_offset: float
	#var bullet_speed: float
	if weapon_type == "regular":
		bullet_offset = REGULAR_SPAWN_OFFSET
		bullet_ins.initial_velocity_speed = REGULAR_SPEED
		bullet_ins.type = "regular"
		$Sounds/NormalShootNoise.play()
	if weapon_type == "laser":
		bullet_offset = LASER_SPAWN_OFFSET
		bullet_ins.initial_velocity_speed = LASER_SPEED
		bullet_ins.get_node("LifespanTimer").wait_time = LASER_LIFESPAN
		bullet_ins.get_node("Rest/LaserTrail").emitting = true
		bullet_ins.type = "laser"
		$Sounds/LaserShootNoise.play()
	if weapon_type == "rocket":
		bullet_offset = ROCKET_SPAWN_OFFSET
		bullet_ins.initial_velocity_speed = ROCKET_SPEED
		bullet_ins.get_node("LifespanTimer").wait_time = ROCKET_LIFESPAN
		bullet_ins.type = "rocket"
		bullet_ins.room_node = self
		$Sounds/RocketShootNoise.play()
	if weapon_type == "trap":
		bullet_offset = TRAP_SPAWN_OFFSET
		bullet_ins.initial_velocity_speed = 0.0
		bullet_ins.type = "trap"
		$Sounds/TrapPlaceNoise.play()
	$Bullets.add_child(bullet_ins)
	bullet_ins.owner_node = bot
	bullet_ins.initial_velocity_direction = bot.rotation
	bullet_ins.position = bot.position + Vector2(bullet_offset, 0).rotated(bot.rotation)
	if weapon_type != "trap": bullet_ins.connect("despawn", on_bullet_despawn)
	if weapon_type == "regular": bot.bullet_count += 1
	bullet_ins.modified_ready()
	bullet_ins.process_mode = Node.PROCESS_MODE_INHERIT

## connected to each bullet's despawn signal
func on_bullet_despawn(bullet: RigidBody2D) -> void:
	if bullet.type == "regular": bullet.owner_node.bullet_count -= 1

var crate_count: int = 0
func _on_crate_spawn_delay_timeout(type: String = "null") -> void:
	if not multiplayer.is_server(): return
	var selected_maze_cell: Vector2i = maze_cells[SEEDED_RNG.randi_range(0, maze_cells.size() - 1)]
	var pos: Vector2 = maze_cell_to_world(selected_maze_cell)
	var spawn_data := {
		"pos": pos,
		"seed": SEEDED_RNG.randi(),
		"type": type
	}
	## if a type is provided or it's "bulk", that means it's executed by staff using console, so bypass max count
	if type == "null" and type != "bulk":
		if crate_count >= IngameManager.alive_tanks_count: return
	crate_count += 1
	$Crates.spawn(spawn_data)

const NEW_CRATE_PATH: String = "res://ingame/entities/crates/crate.tscn"
func spawn_crate(spawn_data: Dictionary) -> Node:
	$Sounds/CrateSpawnNoise.play()
	var crate: Area2D = null
	crate = load(NEW_CRATE_PATH).instantiate()
	crate.connect("equip_weapon", equip_weapon)
	crate.position = spawn_data["pos"]
	crate.rng_seed = spawn_data["seed"]
	if spawn_data["type"] == "bulk": spawn_data["type"] = "null"
	crate.type = spawn_data["type"]
	crate.network_ready()
	return crate

## connected to crates when one of them gets picked up by a tank
func equip_weapon(tank: RigidBody2D, type: String) -> void:
	if not multiplayer.is_server(): return
	crate_count -= 1
	MasterManager.play_server_sound($Sounds/EquipWeaponNoise)
	tank.equip_weapon.rpc(type)

func _on_death_delay_timeout() -> void:
	if IngameManager.alive_tanks_count > 1: return
	## mass-delete the round content NOW so frees/despawns settle during
	## NextRoundDelay instead of 0.6s right before the next spawn burst
	IngameManager.delete_ingame(false)
	$Timers/NextRoundDelay.start()
	if IngameManager.alive_tanks_count == 1:
		var winner_controller: Node = null
		for tank: Node in $TankPawns.get_children():
			if not tank.get_node("Rest").visible: continue
			winner_controller = tank.controller
			break
		if winner_controller != null: SessionManager.increment_score(winner_controller.sid)
	MasterManager.play_server_sound($Sounds/NextRoundNoise)
	process_mode = Node.PROCESS_MODE_DISABLED

func reset() -> void:
	#%DrawTitle.visible = false
	$Players/Player.process_mode = Node.PROCESS_MODE_DISABLED
	$Players/Player.visible = false
	maze_cells.clear()
	$Timers/CrateSpawnDelay.stop()
	
	for node: Node in $Map.get_children():
		if not node is TileMapLayer: continue
		node.clear()
	for physics_shape: Node in $Map/PhysicsWalls.get_children():
		physics_shape.queue_free()
	for crate: Node in $Crates.get_children():
		crate.queue_free()
	for bullet: Node in $Bullets.get_children():
		bullet.queue_free()
	for bot: Node in $Bots.get_children():
		bot.queue_free()

func _on_next_round_delay_timeout() -> void:
	IngameManager._on_ingame_next_round()

@rpc("authority", "reliable", "call_local")
func toggle_pawns(value: bool) -> void:
	for pawn: Node in $TankPawns.get_children(): pawn.toggle(value)
