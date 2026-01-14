class_name Colony
extends Node2D
## Colony - Manages a group of ants with shared resources and behavior

signal colony_stats_updated
signal ant_spawned(ant: Node)
signal ant_died(ant: Node, cause: String)
signal food_received(amount: float)

# Colony configuration
@export var colony_name: String = "Colony"
@export var colony_color: Color = Color.RED
@export var max_ants: int = 100
@export var initial_ant_count: int = 20
@export var spawn_rate: float = 0.5  # Ants per second when food available
@export var ant_spawn_cost: float = 10.0  # Food required to spawn an ant

# Nest position (center of colony)
@export var nest_position: Vector2 = Vector2(1000, 1000)
@export var nest_radius: float = 50.0

# Resources
var food_stored: float = 100.0
var total_food_collected: float = 0.0

# Ants
var ants: Array = []
var _ant_index_counter: int = 0

# Behavior program for this colony's ants
var behavior_program  # BehaviorProgram

# References
var world: Node = null

# Spawn timer
var _spawn_accumulator: float = 0.0

# Ant scene/script
var _AntScript = null


func _ready() -> void:
	_AntScript = load("res://scripts/colony/ant.gd")
	add_to_group("colonies")


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return
	
	var scaled_delta = delta * GameManager.time_scale
	
	# Try to spawn new ants
	_spawn_accumulator += scaled_delta
	var spawn_interval = 1.0 / spawn_rate
	
	while _spawn_accumulator >= spawn_interval:
		_spawn_accumulator -= spawn_interval
		_try_spawn_ant()
	
	# Refill ant energy at nest
	_refill_ants_at_nest()
	
	# Update stats periodically
	if Engine.get_process_frames() % 30 == 0:
		colony_stats_updated.emit()


func initialize(p_world: Node) -> void:
	world = p_world
	global_position = nest_position
	
	# Register with GameManager
	GameManager.register_colony(self)
	
	# Spawn initial ants
	for i in range(initial_ant_count):
		spawn_ant()


func _try_spawn_ant() -> void:
	if ants.size() >= max_ants:
		return
	
	if food_stored < ant_spawn_cost:
		return
	
	food_stored -= ant_spawn_cost
	spawn_ant()


func spawn_ant() -> Node:
	if ants.size() >= max_ants:
		return null
	
	var ant = Node2D.new()
	ant.set_script(_AntScript)
	
	# Position near nest
	var angle = randf() * TAU
	var dist = randf() * nest_radius * 0.5
	ant.global_position = nest_position + Vector2(cos(angle), sin(angle)) * dist
	
	# Initialize
	add_child(ant)
	ant.initialize(self, world, _ant_index_counter, behavior_program)
	_ant_index_counter += 1
	
	# Connect signals
	ant.died.connect(_on_ant_died.bind(ant))
	ant.food_delivered.connect(_on_ant_delivered_food)
	
	ants.append(ant)
	GameManager.global_stats.ants_spawned += 1
	ant_spawned.emit(ant)
	
	return ant


func _on_ant_died(cause: String, ant: Node) -> void:
	ants.erase(ant)
	ant_died.emit(ant, cause)


func _on_ant_delivered_food(amount: float) -> void:
	# Food is received via receive_food()
	pass


func receive_food(amount: float) -> void:
	food_stored += amount
	total_food_collected += amount
	GameManager.global_stats.total_food_collected += amount
	food_received.emit(amount)


func _refill_ants_at_nest() -> void:
	for ant in ants:
		if ant == null or not is_instance_valid(ant):
			continue
		
		var dist = ant.global_position.distance_to(nest_position)
		if dist < nest_radius:
			# Refill energy from food storage
			var energy_needed = ant.max_energy - ant.energy
			var food_to_use = minf(energy_needed * 0.5, food_stored)  # 2:1 food to energy
			
			if food_to_use > 0:
				food_stored -= food_to_use
				ant.refill_energy(food_to_use * 2.0)


func get_stats() -> Dictionary:
	var total_energy: float = 0.0
	var total_food_carried: float = 0.0
	var ants_carrying: int = 0
	
	for ant in ants:
		if ant == null or not is_instance_valid(ant):
			continue
		total_energy += ant.energy
		if ant.carried_item != null:
			ants_carrying += 1
			total_food_carried += ant.carried_weight
	
	var colony_efficiency = total_food_collected / maxf(GameManager.simulation_time, 0.001)
	
	return {
		"colony_name": colony_name,
		"ant_count": ants.size(),
		"max_ants": max_ants,
		"food_stored": food_stored,
		"total_food_collected": total_food_collected,
		"avg_ant_energy": total_energy / maxf(ants.size(), 1),
		"ants_carrying": ants_carrying,
		"total_food_carried": total_food_carried,
		"colony_efficiency": colony_efficiency,
	}


func _draw() -> void:
	# Draw nest
	draw_circle(Vector2.ZERO, nest_radius, Color(colony_color, 0.3))
	draw_arc(Vector2.ZERO, nest_radius, 0, TAU, 32, colony_color, 2.0)
	
	# Draw ants
	for ant in ants:
		if ant == null or not is_instance_valid(ant):
			continue
		
		var ant_pos = ant.global_position - global_position
		var ant_color = colony_color
		
		# Color based on state
		if ant.carried_item != null:
			ant_color = Color.YELLOW
		
		# Draw ant body
		draw_circle(ant_pos, 3.0, ant_color)
		
		# Draw heading indicator
		var heading_end = ant_pos + Vector2(cos(ant.heading), sin(ant.heading)) * 6.0
		draw_line(ant_pos, heading_end, ant_color, 1.0)
