class_name Ant
extends Node2D
## Individual ant agent with sensors, steering, and behavior execution

signal food_delivered(amount: float)
signal died(cause: String)

# References
var colony: Node = null
var world: Node = null

# Identity
var ant_index: int = 0  # For cohort assignment

# Physical properties
@export var base_speed: float = 100.0
@export var max_turn_rate: float = PI  # Radians per second
@export var sensor_distance: float = 40.0
@export var sensor_angle: float = PI / 6  # 30 degrees
@export var pickup_range: float = 20.0
@export var neighbor_sense_range: float = 60.0

# State
var heading: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var energy: float = 100.0
var max_energy: float = 100.0
var carried_item: Node = null
var carried_weight: float = 0.0

# Path integration (dead reckoning toward nest)
var path_integrator: Vector2 = Vector2.ZERO

# Memory (user-programmable storage)
var memory: Dictionary = {}

# Behavior
var behavior_program  # BehaviorProgram
var current_state_name: String = ""

# Efficiency tracking
var efficiency_tracker  # AntEfficiencyTracker

# Cached sensor data (updated each decision tick)
var _sensor_cache: Dictionary = {}

# Script references
var _EfficiencyTrackerScript = null


func _ready() -> void:
	add_to_group("ants")
	_EfficiencyTrackerScript = load("res://scripts/stats/efficiency_tracker.gd")
	efficiency_tracker = _EfficiencyTrackerScript.new()
	heading = randf() * TAU


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return
	
	# Smooth movement (runs every frame)
	_integrate_movement(delta * GameManager.time_scale)
	
	# Update visuals
	rotation = heading


func initialize(p_colony: Node, p_world: Node, p_index: int, p_behavior) -> void:
	colony = p_colony
	world = p_world
	ant_index = p_index
	behavior_program = p_behavior
	
	if behavior_program != null:
		var init_result = behavior_program.enter_initial_state(self, _build_context())
		current_state_name = init_result.get("state", "")
		_apply_energy_cost(init_result.get("energy_cost", 0.0))


## Called by GameManager on decision tick (staggered across cohorts)
func decision_tick() -> void:
	if not GameManager.is_ant_cohort(ant_index):
		return
	
	# Base metabolism cost
	_apply_energy_cost(GameManager.get_action_cost("idle"))
	
	# Update sensors
	_update_sensors()
	
	# Build context for behavior evaluation
	var context = _build_context()
	
	# Execute behavior program
	if behavior_program != null:
		var result = behavior_program.process_tick(self, context, current_state_name)
		
		# Apply state change
		if not result.new_state.is_empty():
			current_state_name = result.new_state
		
		# Apply energy cost
		_apply_energy_cost(result.energy_cost)
		
		# Process action results
		_process_action_results(result.action_results)
	
	# Update path integrator
	_update_path_integrator()
	
	# Check death
	if energy <= 0:
		_die("starvation")


func _update_sensors() -> void:
	_sensor_cache.clear()
	
	# Sample all pheromone fields
	if world != null and world.has_method("get_pheromone_fields"):
		var fields = world.get_pheromone_fields()
		for field_name in fields:
			var field = fields[field_name]
			var samples = field.sample_antenna(global_position, heading, sensor_distance, sensor_angle)
			_sensor_cache["pheromone_" + field_name] = samples
	
	# Nest direction and distance
	if colony != null:
		var to_nest = colony.nest_position - global_position
		_sensor_cache["nest_direction"] = to_nest.angle()
		_sensor_cache["nest_distance"] = to_nest.length()
		_sensor_cache["at_nest"] = to_nest.length() < 30.0
	
	# Nearby entities (using spatial hash)
	if world != null and world.has_method("get_spatial_hash"):
		var spatial_hash = world.get_spatial_hash()
		
		# Nearby food
		var nearby_food = spatial_hash.query_radius_group(global_position, neighbor_sense_range, "food", self)
		_sensor_cache["nearby_food_count"] = nearby_food.size()
		if nearby_food.size() > 0:
			var nearest = _find_nearest(nearby_food)
			_sensor_cache["nearest_food"] = nearest
			_sensor_cache["nearest_food_distance"] = global_position.distance_to(nearest.global_position)
			_sensor_cache["nearest_food_direction"] = (nearest.global_position - global_position).angle()
			_sensor_cache["nearest_food_position"] = nearest.global_position
		else:
			_sensor_cache["nearest_food_distance"] = INF
		
		# Nearby ants
		var nearby_ants = spatial_hash.query_radius_group(global_position, neighbor_sense_range, "ants", self)
		_sensor_cache["nearby_ants_count"] = nearby_ants.size()
		
		# Count allies vs enemies
		var allies = 0
		var enemies = 0
		var ants_with_food = 0
		for ant in nearby_ants:
			if ant.colony == colony:
				allies += 1
			else:
				enemies += 1
			if ant.carried_item != null:
				ants_with_food += 1
		
		_sensor_cache["nearby_allies_count"] = allies
		_sensor_cache["nearby_enemies_count"] = enemies
		_sensor_cache["nearby_ants_with_food_count"] = ants_with_food
		
		if nearby_ants.size() > 0:
			var nearest = _find_nearest(nearby_ants)
			_sensor_cache["nearest_ant_distance"] = global_position.distance_to(nearest.global_position)
			_sensor_cache["nearest_ant_direction"] = (nearest.global_position - global_position).angle()


func _build_context() -> Dictionary:
	var context = _sensor_cache.duplicate()
	
	# Add ant state
	context["position"] = global_position
	context["heading"] = heading
	context["energy"] = energy
	context["max_energy"] = max_energy
	context["base_speed"] = base_speed
	context["carried_item"] = carried_item
	context["carried_weight"] = carried_weight
	context["carried_type"] = carried_item.item_type if carried_item != null and carried_item.has_method("get") else ""
	context["path_integrator"] = path_integrator
	context["memory"] = memory
	
	return context


func _process_action_results(results: Array) -> void:
	for result in results:
		if result is not Dictionary:
			continue
		
		# Track action cost with CostTracker
		if result.has("energy_cost") and result.energy_cost > 0:
			var category = result.get("cost_category", "interaction")
			var action_name = result.get("action_name", "Unknown")
			var program_name = behavior_program.program_name if behavior_program != null else ""
			CostTracker.record_cost(category, action_name, result.energy_cost, program_name, current_state_name)
		
		# Handle movement
		if result.has("desired_heading"):
			var desired = result.desired_heading
			var angle_diff = angle_difference(heading, desired)
			var max_turn = max_turn_rate * (1.0 / GameManager.decision_tick_rate)
			heading += clampf(angle_diff, -max_turn, max_turn)
			heading = fmod(heading + TAU, TAU)
			
			# Turn cost
			_apply_energy_cost(abs(angle_diff) * GameManager.get_action_cost("turn"))
		
		if result.has("desired_speed"):
			velocity = Vector2(cos(heading), sin(heading)) * result.desired_speed
		
		# Handle pheromone deposition
		if result.has("deposit_pheromone") and world != null:
			var field_name = result.deposit_pheromone
			var amount = result.get("deposit_amount", 1.0)
			var use_spread = result.get("use_spread", false)
			var spread_radius = result.get("spread_radius", 1)
			
			if world.has_method("deposit_pheromone"):
				if use_spread:
					world.deposit_pheromone_spread(field_name, global_position, amount, spread_radius)
				else:
					world.deposit_pheromone(field_name, global_position, amount)
			
			efficiency_tracker.record_pheromone(amount)
		
		# Handle pickup
		if result.has("pickup_target") and result.pickup_target != null:
			var target = result.pickup_target
			if target.has_method("pickup"):
				var picked = target.pickup()
				if picked != null:
					carried_item = target
					carried_weight = target.weight if "weight" in target else 1.0
					target.visible = false  # Hide while carried
		
		# Handle drop
		if result.get("drop_item", false) and carried_item != null:
			if result.get("is_delivery", false):
				# Deliver to colony
				var food_value = carried_item.food_value if "food_value" in carried_item else 1.0
				if colony != null and colony.has_method("receive_food"):
					colony.receive_food(food_value)
				food_delivered.emit(food_value)
				efficiency_tracker.record_food_delivered(food_value)
				
				if behavior_program != null:
					behavior_program.record_food_collected(food_value)
				
				# Remove the food item
				carried_item.queue_free()
			else:
				# Just drop on ground
				carried_item.global_position = global_position
				carried_item.visible = true
				if carried_item.has_method("drop"):
					carried_item.drop()
			
			carried_item = null
			carried_weight = 0.0
		
		# Handle memory operations
		if result.has("memory_set"):
			for key in result.memory_set:
				memory[key] = result.memory_set[key]
		
		if result.has("memory_clear"):
			for key in result.memory_clear:
				memory.erase(key)
		
		if result.get("memory_clear_all", false):
			memory.clear()


func _integrate_movement(delta: float) -> void:
	var old_pos = global_position
	global_position += velocity * delta
	
	# Track distance
	var distance = global_position.distance_to(old_pos)
	efficiency_tracker.record_distance(distance)
	
	# Movement energy cost
	var move_cost = distance * GameManager.get_action_cost("move_base")
	if carried_item != null:
		move_cost = distance * GameManager.get_action_cost("move_carrying")
	_apply_energy_cost(move_cost)
	
	# Update path integrator (accumulate vector FROM current position TO nest)
	if colony != null:
		path_integrator = colony.nest_position - global_position


func _update_path_integrator() -> void:
	# Path integration is updated in _integrate_movement
	pass


func _apply_energy_cost(cost: float) -> void:
	energy -= cost
	efficiency_tracker.record_energy(cost)
	GameManager.global_stats.total_energy_spent += cost


func _find_nearest(entities: Array) -> Node:
	var nearest: Node = null
	var nearest_dist = INF
	for entity in entities:
		var dist = global_position.distance_squared_to(entity.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = entity
	return nearest


func _die(cause: String) -> void:
	died.emit(cause)
	GameManager.global_stats.ants_starved += 1
	
	# Drop carried item
	if carried_item != null:
		carried_item.global_position = global_position
		carried_item.visible = true
		carried_item = null
	
	queue_free()


## Refill energy (e.g., when at nest)
func refill_energy(amount: float) -> void:
	energy = minf(energy + amount, max_energy)


## Get current efficiency statistics
func get_efficiency_stats() -> Dictionary:
	return efficiency_tracker.get_stats()
