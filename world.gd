class_name SimulationWorld
extends Node2D
## Main world container that manages pheromone fields, entities, and spatial queries

signal pheromone_field_added(field_name: String)
signal food_source_added(source: Node)
signal food_source_depleted(source: Node)

# World configuration
@export var world_width: float = 2000.0
@export var world_height: float = 2000.0
@export var pheromone_cell_size: float = 10.0
@export var spatial_hash_cell_size: float = 50.0

# Pheromone field configuration
@export var default_pheromone_types: Array = ["food_trail", "home_trail", "alarm"]

# References
var pheromone_fields: Dictionary = {}  # String -> PheromoneField
var spatial_hash  # SpatialHash
var colonies: Array = []
var food_sources: Array = []

# Visualization
var _pheromone_visualizer: Node2D
var _show_pheromones: bool = true

# Physics tick tracking
var _physics_accumulator: float = 0.0
var _physics_interval: float = 1.0 / 30.0  # 30 Hz


func _ready() -> void:
	# Initialize spatial hash
	var SpatialHashScript = load("res://scripts/world/spatial_hash.gd")
	spatial_hash = SpatialHashScript.new(spatial_hash_cell_size)
	
	# Create default pheromone fields
	for field_name in default_pheromone_types:
		create_pheromone_field(field_name)
	
	# Set up pheromone visualization
	_setup_visualization()
	
	# Set reference in GameManager
	GameManager.world = self


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return
	
	var scaled_delta = delta * GameManager.time_scale
	
	# Update spatial hash every frame
	_rebuild_spatial_hash()
	
	# Update pheromone fields at physics rate
	_physics_accumulator += scaled_delta
	while _physics_accumulator >= _physics_interval:
		_physics_accumulator -= _physics_interval
		_update_pheromone_fields(_physics_interval)
	
	# Update visualization
	if _show_pheromones:
		_update_pheromone_visualization()


func _rebuild_spatial_hash() -> void:
	spatial_hash.clear()
	
	# Add all ants
	for colony in colonies:
		for ant in colony.ants:
			if ant != null and is_instance_valid(ant):
				spatial_hash.insert(ant)
	
	# Add all food sources
	for food in food_sources:
		if food != null and is_instance_valid(food):
			spatial_hash.insert(food)


func _update_pheromone_fields(delta: float) -> void:
	for field_name in pheromone_fields:
		pheromone_fields[field_name].update(delta)


## Create a new pheromone field
func create_pheromone_field(field_name: String, diffusion: float = 0.1, evaporation: float = 0.02):
	if pheromone_fields.has(field_name):
		return pheromone_fields[field_name]
	
	var PheromoneFieldScript = load("res://scripts/world/pheromone_field.gd")
	var field = PheromoneFieldScript.new(field_name, world_width, world_height, pheromone_cell_size)
	field.diffusion_rate = diffusion
	field.evaporation_rate = evaporation
	
	# Set default colors
	match field_name:
		"food_trail":
			field.color = Color(0.2, 0.8, 0.2, 0.6)  # Green
		"home_trail":
			field.color = Color(0.2, 0.4, 0.9, 0.6)  # Blue
		"alarm":
			field.color = Color(0.9, 0.2, 0.2, 0.6)  # Red
			field.evaporation_rate = 0.1  # Alarm fades faster
			field.diffusion_rate = 0.3   # Alarm spreads faster
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
func spawn_food_source(pos: Vector2, amount: float = 100.0):
	var FoodSourceScript = load("res://scripts/entities/food_source.gd")
	var food = FoodSourceScript.new()
	food.global_position = pos
	food.food_amount = amount
	add_food_source(food)
	return food


## Spawn multiple food sources in a cluster
func spawn_food_cluster(center: Vector2, count: int, radius: float, total_food: float) -> void:
	var food_per_source = total_food / count
	for i in range(count):
		var angle = randf() * TAU
		var dist = randf() * radius
		var pos = center + Vector2(cos(angle), sin(angle)) * dist
		spawn_food_source(pos, food_per_source)


## Setup pheromone visualization
func _setup_visualization() -> void:
	_pheromone_visualizer = Node2D.new()
	_pheromone_visualizer.name = "PheromoneVisualizer"
	add_child(_pheromone_visualizer)
	_pheromone_visualizer.z_index = -1


func _update_pheromone_visualization() -> void:
	_pheromone_visualizer.queue_redraw()


func _draw() -> void:
	# Draw world bounds
	draw_rect(Rect2(0, 0, world_width, world_height), Color(0.1, 0.1, 0.1), false, 2.0)


## Toggle pheromone visualization
func toggle_pheromone_display(show: bool) -> void:
	_show_pheromones = show
	_pheromone_visualizer.visible = show


## Get world statistics
func get_stats() -> Dictionary:
	var total_pheromone: float = 0.0
	for field_name in pheromone_fields:
		total_pheromone += pheromone_fields[field_name].current_total
	
	return {
		"world_size": Vector2(world_width, world_height),
		"pheromone_field_count": pheromone_fields.size(),
		"total_pheromone": total_pheromone,
		"colony_count": colonies.size(),
		"food_source_count": food_sources.size(),
	}
