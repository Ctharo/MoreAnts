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
@export var min_ant_count: int = 10  # Minimum ants to maintain
@export var spawn_rate: float = 0.5  # Ants per second when food available
@export var ant_spawn_cost: float = 10.0  # Food required to spawn an ant
@export var energy_refill_rate: float = 15.0  # Energy per second when at nest

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
	
	var scaled_delta: float = delta * GameManager.time_scale
	
	# Clean up dead ants from the array
	_cleanup_dead_ants()
	
	# Maintain minimum ant count - priority spawning
	if ants.size() < min_ant_count and food_stored >= ant_spawn_cost * 0.5:
		# Reduced cost for maintaining minimum population
		food_stored -= ant_spawn_cost * 0.5
		spawn_ant()
	
	# Try to spawn new ants up to max
	_spawn_accumulator += scaled_delta
	var spawn_interval: float = 1.0 / spawn_rate
	
	while _spawn_accumulator >= spawn_interval:
		_spawn_accumulator -= spawn_interval
		_try_spawn_ant()
	
	# Refill ant energy ONLY when at nest
	_refill_ants_at_nest(scaled_delta)
	
	# Update stats periodically
	if Engine.get_process_frames() % 30 == 0:
		colony_stats_updated.emit()
	
	# Redraw to update ant positions
	queue_redraw()


func _cleanup_dead_ants() -> void:
	## Remove any freed ant references from the array
	var i: int = ants.size() - 1
	while i >= 0:
		if ants[i] == null or not is_instance_valid(ants[i]):
			ants.remove_at(i)
		i -= 1


func initialize(p_world: Node) -> void:
	world = p_world
	global_position = nest_position
	
	# Register with GameManager
	GameManager.register_colony(self)
	
	# Spawn initial ants
	for i: int in range(initial_ant_count):
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
	
	var ant: Node2D = Node2D.new()
	ant.set_script(_AntScript)
	
	# Add to scene first
	add_child(ant)
	
	# Initialize (this sets position to nest_position)
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


func _refill_ants_at_nest(delta: float) -> void:
	## Only refill energy for ants that are physically at the nest
	for ant: Node in ants:
		if ant == null or not is_instance_valid(ant):
			continue
		
		var dist: float = ant.global_position.distance_to(nest_position)
		if dist < nest_radius:
			# Ant is at nest - refill energy over time
			var energy_needed: float = ant.max_energy - ant.energy
			if energy_needed > 0.1:
				# Refill energy at a rate, costs food
				var refill_amount: float = minf(energy_refill_rate * delta, energy_needed)
				var food_cost: float = refill_amount * 0.3  # Food to energy ratio
				
				if food_stored >= food_cost:
					food_stored -= food_cost
					ant.refill_energy(refill_amount)


func get_stats() -> Dictionary:
	var total_energy: float = 0.0
	var total_food_carried: float = 0.0
	var ants_carrying: int = 0
	var valid_ant_count: int = 0
	
	for ant: Node in ants:
		if ant == null or not is_instance_valid(ant):
			continue
		valid_ant_count += 1
		total_energy += ant.energy
		if ant.carried_item != null:
			ants_carrying += 1
			total_food_carried += ant.carried_weight
	
	var colony_efficiency: float = total_food_collected / maxf(GameManager.simulation_time, 0.001)
	
	return {
		"colony_name": colony_name,
		"ant_count": valid_ant_count,
		"max_ants": max_ants,
		"food_stored": food_stored,
		"total_food_collected": total_food_collected,
		"avg_ant_energy": total_energy / maxf(valid_ant_count, 1),
		"ants_carrying": ants_carrying,
		"total_food_carried": total_food_carried,
		"colony_efficiency": colony_efficiency,
	}


func _draw() -> void:
	# Draw nest
	draw_circle(Vector2.ZERO, nest_radius, Color(colony_color, 0.3))
	draw_arc(Vector2.ZERO, nest_radius, 0, TAU, 32, colony_color, 2.0)
	
	# Draw ants
	for ant: Node in ants:
		if ant == null or not is_instance_valid(ant):
			continue
		
		var ant_pos: Vector2 = ant.global_position - global_position
		var ant_color: Color = colony_color
		
		# Color based on energy state
		if ant.energy < ant.max_energy * 0.3:
			ant_color = Color.ORANGE_RED  # Low energy warning
		
		# Draw ant body
		draw_circle(ant_pos, 3.0, ant_color)
		
		# Draw heading indicator
		var heading_end: Vector2 = ant_pos + Vector2(cos(ant.heading), sin(ant.heading)) * 6.0
		draw_line(ant_pos, heading_end, ant_color, 1.0)
		
		# Draw carried food on top of ant at proper food size
		if ant.carried_item != null:
			var food_radius: float = 6.0  # Same as FoodSource.base_radius
			if "base_radius" in ant.carried_item:
				food_radius = ant.carried_item.base_radius
			draw_circle(ant_pos, food_radius, Color.YELLOW_GREEN)
			draw_arc(ant_pos, food_radius, 0, TAU, 12, Color.YELLOW_GREEN.darkened(0.3), 1.0)
