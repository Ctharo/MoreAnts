class_name SimulationWorld
extends Node2D
## Main world container that manages pheromone fields, entities, and spatial queries

signal pheromone_field_added(field_name: String)
signal food_source_added(source: Node)
signal food_source_depleted(source: Node)

#region Configuration
@export var world_width: float = 2000.0
@export var world_height: float = 2000.0
@export var pheromone_cell_size: float = 10.0
@export var spatial_hash_cell_size: float = 50.0
@export var default_pheromone_types: Array = ["food_trail", "home_trail", "alarm"]
#endregion

#region References
var pheromone_fields: Dictionary = {}  # String -> PheromoneField
var spatial_hash: SpatialHash = null
var colonies: Array = []
var food_sources: Array = []
var obstacles: Array = []  # Obstacle nodes
#endregion

#region Visualization
var _show_pheromones: bool = true
#endregion

#region Physics Tick
var _physics_accumulator: float = 0.0
var _physics_interval: float = 1.0 / 30.0  # 30 Hz
#endregion


func _ready() -> void:
	# Initialize spatial hash
	var SpatialHashScript: Script = load("res://scripts/world/spatial_hash.gd")
	spatial_hash = SpatialHashScript.new(spatial_hash_cell_size)

	# Create default pheromone fields
	for field_name: String in default_pheromone_types:
		create_pheromone_field(field_name)

	# Set reference in GameManager
	GameManager.world = self


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return

	var scaled_delta: float = delta * GameManager.time_scale

	# Update spatial hash every frame
	_rebuild_spatial_hash()

	# Update pheromone fields at physics rate
	_physics_accumulator += scaled_delta
	while _physics_accumulator >= _physics_interval:
		_physics_accumulator -= _physics_interval
		_update_pheromone_fields(_physics_interval)

	# Redraw for pheromone visualization
	if _show_pheromones:
		queue_redraw()


func _rebuild_spatial_hash() -> void:
	spatial_hash.clear()

	# Clean up invalid colonies first
	var c: int = colonies.size() - 1
	while c >= 0:
		if not is_instance_valid(colonies[c]):
			colonies.remove_at(c)
		c -= 1

	# Add all ants (iterate backwards to safely remove invalid entries)
	for colony: Node in colonies:
		if not is_instance_valid(colony):
			continue
		var i: int = colony.ants.size() - 1
		while i >= 0:
			if not is_instance_valid(colony.ants[i]):
				colony.ants.remove_at(i)
			else:
				spatial_hash.insert(colony.ants[i])
			i -= 1

	# Add all food sources (clean up freed ones)
	# Must check is_instance_valid BEFORE accessing the element
	var j: int = food_sources.size() - 1
	while j >= 0:
		if not is_instance_valid(food_sources[j]):
			food_sources.remove_at(j)
		elif _is_food_available(food_sources[j]):
			spatial_hash.insert(food_sources[j])
		j -= 1
	
	# Add all obstacles
	var k: int = obstacles.size() - 1
	while k >= 0:
		if not is_instance_valid(obstacles[k]):
			obstacles.remove_at(k)
		else:
			spatial_hash.insert(obstacles[k])
		k -= 1


## Safely check if a node is valid and not queued for deletion
func _is_valid_node(node: Node) -> bool:
	if node == null:
		return false
	if not is_instance_valid(node):
		return false
	if node.is_queued_for_deletion():
		return false
	return true


## Safely check if food is available for spatial hash
func _is_food_available(food: Node) -> bool:
	if not _is_valid_node(food):
		return false
	if not food.is_inside_tree():
		return false
	# Use get() to safely access property
	var picked_up: bool = food.get("is_picked_up") if "is_picked_up" in food else true
	return not picked_up


func _update_pheromone_fields(delta: float) -> void:
	for field_name: String in pheromone_fields:
		pheromone_fields[field_name].update(delta)


## Create a new pheromone field
func create_pheromone_field(field_name: String, diffusion: float = 0.05, evaporation: float = 0.003) -> PheromoneField:
	if pheromone_fields.has(field_name):
		return pheromone_fields[field_name]

	var PheromoneFieldScript: Script = load("res://scripts/world/pheromone_field.gd")
	var field: PheromoneField = PheromoneFieldScript.new(field_name, world_width, world_height, pheromone_cell_size)
	field.diffusion_rate = diffusion
	field.evaporation_rate = evaporation

	# Set default colors and properties per field type
	match field_name:
		"food_trail":
			field.color = Color(0.2, 0.95, 0.2, 0.9)  # Bright green
			field.evaporation_rate = 0.003
		"home_trail":
			field.color = Color(0.3, 0.5, 1.0, 0.9)  # Brighter blue
			field.evaporation_rate = 0.002  # Slower evaporation for home trails
		"alarm":
			field.color = Color(0.9, 0.2, 0.2, 0.8)  # Red
			field.evaporation_rate = 0.05  # Alarm fades faster
			field.diffusion_rate = 0.2   # Alarm spreads faster
		_:
			field.color = Color(0.5, 0.5, 0.5, 0.6)

	pheromone_fields[field_name] = field
	pheromone_field_added.emit(field_name)

	return field


## Deposit pheromone at a position
func deposit_pheromone(field_name: String, pos: Vector2, amount: float) -> void:
	if pheromone_fields.has(field_name):
		pheromone_fields[field_name].deposit(pos, amount)
		GameManager.global_stats.total_pheromone_deposited += amount


## Deposit pheromone with spread
func deposit_pheromone_spread(field_name: String, pos: Vector2, amount: float, radius: int = 1) -> void:
	if pheromone_fields.has(field_name):
		pheromone_fields[field_name].deposit_spread(pos, amount, radius)
		GameManager.global_stats.total_pheromone_deposited += amount


## Get all pheromone fields
func get_pheromone_fields() -> Dictionary:
	return pheromone_fields


## Get the spatial hash for queries
func get_spatial_hash() -> SpatialHash:
	return spatial_hash


## Register a colony with the world
func register_colony(colony: Node) -> void:
	if colony not in colonies:
		colonies.append(colony)
		colony.initialize(self)


## Add a food source to the world
func add_food_source(food: Node) -> void:
	if food not in food_sources:
		food_sources.append(food)
		food.add_to_group("food")
		if not food.is_inside_tree():
			add_child(food)
		food_source_added.emit(food)

		# Connect to depletion signal if available
		if food.has_signal("depleted"):
			food.depleted.connect(_on_food_depleted.bind(food))


func _on_food_depleted(food: Node) -> void:
	food_sources.erase(food)
	food_source_depleted.emit(food)


## Create a food source at a position
func spawn_food_source(pos: Vector2, amount: float = 100.0) -> Node:
	var FoodSourceScript: Script = load("res://scripts/entities/food_source.gd")
	var food: Node = FoodSourceScript.new()
	food.global_position = pos
	food.food_amount = amount
	food.max_food = amount
	add_food_source(food)
	return food


## Spawn multiple food sources in a cluster
func spawn_food_cluster(center: Vector2, count: int, radius: float, total_food: float) -> void:
	var food_per_source: float = total_food / count
	for i: int in range(count):
		var angle: float = randf() * TAU
		var dist: float = randf() * radius
		var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * dist
		spawn_food_source(pos, food_per_source)


#region Obstacle Management
## Add an obstacle to the world
func add_obstacle(obstacle: Node) -> void:
	if obstacle not in obstacles:
		obstacles.append(obstacle)
		obstacle.add_to_group("obstacles")
		if not obstacle.is_inside_tree():
			add_child(obstacle)


## Create and add a circular obstacle
func spawn_obstacle_circle(pos: Vector2, radius: float) -> Node:
	var ObstacleScript: Script = load("res://scripts/entities/obstacle.gd")
	var obstacle: Node = ObstacleScript.new()
	obstacle.global_position = pos
	obstacle.obstacle_radius = radius
	obstacle.shape_type = 0  # CIRCLE
	add_obstacle(obstacle)
	return obstacle


## Create and add a rectangular obstacle
func spawn_obstacle_rect(pos: Vector2, size: Vector2, rotation_deg: float = 0.0) -> Node:
	var ObstacleScript: Script = load("res://scripts/entities/obstacle.gd")
	var obstacle: Node = ObstacleScript.new()
	obstacle.global_position = pos
	obstacle.obstacle_size = size
	obstacle.shape_type = 1  # RECTANGLE
	obstacle.rotation_degrees = rotation_deg
	add_obstacle(obstacle)
	return obstacle


## Create a wall (thin rectangle)
func spawn_wall(start: Vector2, end: Vector2, thickness: float = 10.0) -> Node:
	var center: Vector2 = (start + end) / 2.0
	var length: float = start.distance_to(end)
	var angle: float = (end - start).angle()
	
	var ObstacleScript: Script = load("res://scripts/entities/obstacle.gd")
	var obstacle: Node = ObstacleScript.new()
	obstacle.global_position = center
	obstacle.obstacle_size = Vector2(length, thickness)
	obstacle.shape_type = 1  # RECTANGLE
	obstacle.rotation = angle
	add_obstacle(obstacle)
	return obstacle


## Remove an obstacle
func remove_obstacle(obstacle: Node) -> void:
	obstacles.erase(obstacle)
	if is_instance_valid(obstacle):
		obstacle.queue_free()


## Query obstacles near a position (for ant sensing)
func query_obstacles_near(pos: Vector2, radius: float) -> Array:
	return spatial_hash.query_radius_group(pos, radius, "obstacles")


## Check if a point is inside any obstacle
func is_point_blocked(pos: Vector2) -> bool:
	var nearby: Array = query_obstacles_near(pos, 100.0)  # Check nearby obstacles
	for obs: Node in nearby:
		if not is_instance_valid(obs):
			continue
		if obs.has_method("contains_point") and obs.contains_point(pos):
			return true
	return false


## Get the nearest obstacle surface point and normal for avoidance
func get_obstacle_avoidance(pos: Vector2, heading: float, sense_distance: float) -> Dictionary:
	## Returns {blocked: bool, avoidance_heading: float, distance: float}
	var result: Dictionary = {
		"blocked": false,
		"avoidance_heading": heading,
		"distance": INF,
	}
	
	# Sample points ahead in a cone
	var sample_angles: Array[float] = [0.0, -0.3, 0.3, -0.6, 0.6]  # Center, left, right
	var nearest_block_dist: float = INF
	var block_direction: float = 0.0
	
	for angle_offset: float in sample_angles:
		var sample_angle: float = heading + angle_offset
		var sample_pos: Vector2 = pos + Vector2.from_angle(sample_angle) * sense_distance
		
		var nearby: Array = query_obstacles_near(sample_pos, 20.0)
		for obs: Node in nearby:
			if not is_instance_valid(obs):
				continue
			if obs.has_method("get_distance_to_surface"):
				var dist: float = obs.get_distance_to_surface(pos)
				if dist < nearest_block_dist:
					nearest_block_dist = dist
					block_direction = angle_offset
					result.blocked = true
					result.distance = dist
	
	if result.blocked:
		# Steer away from the blocked direction
		if block_direction <= 0:
			result.avoidance_heading = heading + PI / 3  # Turn right
		else:
			result.avoidance_heading = heading - PI / 3  # Turn left
	
	return result
#endregion


func _draw() -> void:
	# Draw world bounds
	draw_rect(Rect2(0, 0, world_width, world_height), Color(0.2, 0.2, 0.2), false, 2.0)
	
	# Draw pheromone fields
	if _show_pheromones:
		_draw_pheromones()


func _draw_pheromones() -> void:
	for field_name: String in pheromone_fields:
		var field: PheromoneField = pheromone_fields[field_name]
		var cell_size: float = field.cell_size
		
		for y: int in range(field.height):
			for x: int in range(field.width):
				var value: float = field.get_at(x, y)
				if value > 0.05:  # Lower threshold for visibility
					# Use logarithmic scaling for better visibility of faint trails
					var normalized: float = log(1.0 + value) / log(1.0 + 30.0)
					var intensity: float = clampf(normalized, 0.0, 1.0)
					var draw_color: Color = field.color
					draw_color.a = intensity * 0.8
					
					var rect: Rect2 = Rect2(
						x * cell_size, 
						y * cell_size, 
						cell_size, 
						cell_size
					)
					draw_rect(rect, draw_color, true)


## Toggle pheromone visualization
func toggle_pheromone_display(show: bool) -> void:
	_show_pheromones = show


## Get world statistics
func get_stats() -> Dictionary:
	var total_pheromone: float = 0.0
	for field_name: String in pheromone_fields:
		total_pheromone += pheromone_fields[field_name].current_total

	return {
		"world_size": Vector2(world_width, world_height),
		"pheromone_field_count": pheromone_fields.size(),
		"total_pheromone": total_pheromone,
		"colony_count": colonies.size(),
		"food_source_count": food_sources.size(),
		"obstacle_count": obstacles.size(),
	}
