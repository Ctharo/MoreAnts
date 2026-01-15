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
@export var base_speed: float = 80.0
@export var max_turn_rate: float = PI * 3.0  # Radians per second
@export var sensor_distance: float = 40.0
@export var sensor_angle: float = PI / 6  # 30 degrees
@export var pickup_range: float = 20.0
@export var neighbor_sense_range: float = 60.0

# State
var heading: float = 0.0
var desired_heading: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var current_speed: float = 0.0
var target_speed: float = 0.0  # For smooth speed transitions
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

# World bounds (set during initialize)
var _world_min: Vector2 = Vector2.ZERO
var _world_max: Vector2 = Vector2(2000, 2000)


func _ready() -> void:
	add_to_group("ants")
	_EfficiencyTrackerScript = load("res://scripts/stats/efficiency_tracker.gd")
	efficiency_tracker = _EfficiencyTrackerScript.new()
	heading = randf() * TAU
	desired_heading = heading


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return
	
	var scaled_delta: float = delta * GameManager.time_scale
	
	# Smooth heading interpolation
	_interpolate_heading(scaled_delta)
	
	# Smooth speed interpolation
	_interpolate_speed(scaled_delta)
	
	# Movement with boundary enforcement
	_integrate_movement(scaled_delta)
	
	# Update visuals
	rotation = heading


func initialize(p_colony: Node, p_world: Node, p_index: int, p_behavior) -> void:
	colony = p_colony
	world = p_world
	ant_index = p_index
	behavior_program = p_behavior
	
	# Set world bounds
	if world != null:
		_world_min = Vector2(10, 10)
		_world_max = Vector2(world.world_width - 10, world.world_height - 10)
	
	# Start at colony position
	if colony != null:
		global_position = colony.nest_position
		# Small random offset
		var offset: Vector2 = Vector2(randf_range(-20, 20), randf_range(-20, 20))
		global_position += offset
	
	if behavior_program != null:
		var init_result: Dictionary = behavior_program.enter_initial_state(self, _build_context())
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
	var context: Dictionary = _build_context()
	
	# Execute behavior program
	if behavior_program != null:
		var result: Dictionary = behavior_program.process_tick(self, context, current_state_name)
		
		# Apply state change
		if not result.new_state.is_empty():
			current_state_name = result.new_state
		
		# Apply energy cost
		_apply_energy_cost(result.energy_cost)
		
		# Process action results
		_process_action_results(result.action_results)
	
	# Update path integrator
	_update_path_integrator()
	
	# Check death from starvation
	if energy <= 0:
		_die("starvation")


func _interpolate_heading(delta: float) -> void:
	## Smoothly interpolate current heading toward desired heading
	var angle_diff: float = angle_difference(heading, desired_heading)
	var max_turn: float = max_turn_rate * delta
	
	if absf(angle_diff) > 0.01:
		heading += clampf(angle_diff, -max_turn, max_turn)
		heading = fmod(heading + TAU, TAU)


func _interpolate_speed(delta: float) -> void:
	## Smoothly interpolate current speed toward target speed
	var speed_diff: float = target_speed - current_speed
	var max_accel: float = 200.0 * delta  # Acceleration rate
	
	if absf(speed_diff) > 1.0:
		current_speed += clampf(speed_diff, -max_accel, max_accel)
	else:
		current_speed = target_speed


func _update_sensors() -> void:
	_sensor_cache.clear()
	
	# Sample all pheromone fields
	if world != null and world.has_method("get_pheromone_fields"):
		var fields: Dictionary = world.get_pheromone_fields()
		for field_name: String in fields:
			var field = fields[field_name]
			var samples: Dictionary = field.sample_antenna(global_position, heading, sensor_distance, sensor_angle)
			_sensor_cache["pheromone_" + field_name] = samples
	
	# Nest direction and distance
	if colony != null:
		var to_nest: Vector2 = colony.nest_position - global_position
		_sensor_cache["nest_direction"] = to_nest.angle()
		_sensor_cache["nest_distance"] = to_nest.length()
		_sensor_cache["at_nest"] = to_nest.length() < colony.nest_radius
	
	# Nearby entities (using spatial hash)
	if world != null and world.has_method("get_spatial_hash"):
		var spatial_hash = world.get_spatial_hash()
		if spatial_hash != null:
			# Nearby food
			var nearby_food: Array = spatial_hash.query_radius_group(global_position, neighbor_sense_range, "food", self)
			# Filter out picked up food
			var available_food: Array = []
			for food: Node in nearby_food:
				if food != null and is_instance_valid(food) and not food.is_picked_up:
					available_food.append(food)
			
			_sensor_cache["nearby_food_count"] = available_food.size()
			if available_food.size() > 0:
				var nearest: Node = _find_nearest(available_food)
				if nearest != null:
					_sensor_cache["nearest_food"] = nearest
					_sensor_cache["nearest_food_distance"] = global_position.distance_to(nearest.global_position)
					_sensor_cache["nearest_food_direction"] = (nearest.global_position - global_position).angle()
					_sensor_cache["nearest_food_position"] = nearest.global_position
				else:
					_sensor_cache["nearest_food_distance"] = INF
			else:
				_sensor_cache["nearest_food_distance"] = INF
			
			# Nearby ants
			var nearby_ants: Array = spatial_hash.query_radius_group(global_position, neighbor_sense_range, "ants", self)
			_sensor_cache["nearby_ants_count"] = nearby_ants.size()
			
			# Count allies vs enemies
			var allies: int = 0
			var enemies: int = 0
			var ants_with_food: int = 0
			for ant: Node in nearby_ants:
				if not is_instance_valid(ant):
					continue
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
				var nearest: Node = _find_nearest(nearby_ants)
				if nearest != null and is_instance_valid(nearest):
					_sensor_cache["nearest_ant_distance"] = global_position.distance_to(nearest.global_position)
					_sensor_cache["nearest_ant_direction"] = (nearest.global_position - global_position).angle()


func _build_context() -> Dictionary:
	var context: Dictionary = _sensor_cache.duplicate()
	
	# Add ant state
	context["position"] = global_position
	context["heading"] = heading
	context["energy"] = energy
	context["max_energy"] = max_energy
	context["energy_percent"] = (energy / max_energy) * 100.0
	context["base_speed"] = base_speed
	context["carried_item"] = carried_item
	context["carried_weight"] = carried_weight
	context["carried_type"] = carried_item.item_type if carried_item != null and "item_type" in carried_item else ""
	context["path_integrator"] = path_integrator
	context["memory"] = memory
	
	return context


func _process_action_results(results: Array) -> void:
	for result: Variant in results:
		if result is not Dictionary:
			continue
		
		# Track action cost with CostTracker
		if result.has("energy_cost") and result.energy_cost > 0:
			var category: String = result.get("cost_category", "interaction")
			var action_name: String = result.get("action_name", "Unknown")
			var program_name: String = behavior_program.program_name if behavior_program != null else ""
			CostTracker.record_cost(category, action_name, result.energy_cost, program_name, current_state_name)
		
		# Handle movement - set desired heading for smooth interpolation
		if result.has("desired_heading"):
			desired_heading = fmod(result.desired_heading + TAU, TAU)
			
			# Turn cost based on angle difference
			var angle_diff: float = absf(angle_difference(heading, desired_heading))
			_apply_energy_cost(angle_diff * GameManager.get_action_cost("turn"))
		
		if result.has("desired_speed"):
			target_speed = result.desired_speed
		
		# Handle pheromone deposition
		if result.has("deposit_pheromone") and world != null:
			var field_name: String = result.deposit_pheromone
			var amount: float = result.get("deposit_amount", 1.0)
			var use_spread: bool = result.get("use_spread", false)
			var spread_radius: int = result.get("spread_radius", 1)
			
			if world.has_method("deposit_pheromone"):
				if use_spread:
					world.deposit_pheromone_spread(field_name, global_position, amount, spread_radius)
				else:
					world.deposit_pheromone(field_name, global_position, amount)
			
			efficiency_tracker.record_pheromone(amount)
		
		# Handle pickup
		if result.has("pickup_target") and result.pickup_target != null:
			var target: Node = result.pickup_target
			if is_instance_valid(target) and target.has_method("pickup"):
				var picked: Node = target.pickup()
				if picked != null:
					carried_item = target
					carried_weight = target.weight if "weight" in target else 1.0
					target.visible = false  # Hide while carried
		
		# Handle drop
		if result.get("drop_item", false) and carried_item != null:
			if result.get("is_delivery", false):
				# Deliver to colony
				var food_value: float = carried_item.food_value if "food_value" in carried_item else 1.0
				if colony != null and colony.has_method("receive_food"):
					colony.receive_food(food_value)
				food_delivered.emit(food_value)
				efficiency_tracker.record_food_delivered(food_value)
				
				if behavior_program != null:
					behavior_program.record_food_collected(food_value)
				
				# Remove the food item
				if is_instance_valid(carried_item):
					carried_item.queue_free()
			else:
				# Just drop on ground
				if is_instance_valid(carried_item):
					carried_item.global_position = global_position
					carried_item.visible = true
					if carried_item.has_method("drop"):
						carried_item.drop()
			
			carried_item = null
			carried_weight = 0.0
		
		# Handle memory operations
		if result.has("memory_set"):
			for key: String in result.memory_set:
				memory[key] = result.memory_set[key]
		
		if result.has("memory_clear"):
			for key: String in result.memory_clear:
				memory.erase(key)
		
		if result.get("memory_clear_all", false):
			memory.clear()


func _integrate_movement(delta: float) -> void:
	var old_pos: Vector2 = global_position
	
	# Update velocity based on current heading and speed
	velocity = Vector2(cos(heading), sin(heading)) * current_speed
	
	# Apply movement
	global_position += velocity * delta
	
	# Enforce world boundaries with bounce
	var bounced: bool = false
	if global_position.x < _world_min.x:
		global_position.x = _world_min.x
		heading = PI - heading  # Reflect horizontally
		bounced = true
	elif global_position.x > _world_max.x:
		global_position.x = _world_max.x
		heading = PI - heading
		bounced = true
	
	if global_position.y < _world_min.y:
		global_position.y = _world_min.y
		heading = -heading  # Reflect vertically
		bounced = true
	elif global_position.y > _world_max.y:
		global_position.y = _world_max.y
		heading = -heading
		bounced = true
	
	if bounced:
		heading = fmod(heading + TAU, TAU)
		desired_heading = heading
	
	# Track distance
	var distance: float = global_position.distance_to(old_pos)
	efficiency_tracker.record_distance(distance)
	
	# Movement energy cost
	var move_cost: float = distance * GameManager.get_action_cost("move_base")
	if carried_item != null:
		move_cost = distance * GameManager.get_action_cost("move_carrying")
	_apply_energy_cost(move_cost)
	
	# Update path integrator
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
	var nearest_dist: float = INF
	for entity: Node in entities:
		if entity == null or not is_instance_valid(entity):
			continue
		var dist: float = global_position.distance_squared_to(entity.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = entity
	return nearest


func _die(cause: String) -> void:
	died.emit(cause)
	GameManager.global_stats.ants_starved += 1
	
	# Drop carried item
	if carried_item != null and is_instance_valid(carried_item):
		carried_item.global_position = global_position
		carried_item.visible = true
		carried_item = null
	
	queue_free()


## Refill energy (only happens at nest via colony)
func refill_energy(amount: float) -> void:
	energy = minf(energy + amount, max_energy)


## Get current efficiency statistics
func get_efficiency_stats() -> Dictionary:
	return efficiency_tracker.get_stats()


## Stop movement
func stop_movement() -> void:
	velocity = Vector2.ZERO
	current_speed = 0.0
	target_speed = 0.0
