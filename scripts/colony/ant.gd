class_name Ant
extends Node2D
## Individual ant agent with continuous movement
## Movement happens every frame; decisions only change direction

signal food_delivered(amount: float)
signal died(cause: String)

#region References
var colony: Node = null
var world: Node = null
#endregion

#region Identity
var ant_index: int = 0
#endregion

#region Physical Properties
@export var base_speed: float = 80.0
@export var max_turn_rate: float = PI * 3.0
@export var sensor_distance: float = 40.0
@export var sensor_angle: float = PI / 6
@export var pickup_range: float = 20.0
@export var neighbor_sense_range: float = 60.0
#endregion

#region Movement - Updated every frame
var heading: float = 0.0
var desired_heading: float = 0.0
var speed: float = 80.0  # Always moving by default
#endregion

#region Ant State
var energy: float = 100.0
var max_energy: float = 100.0
var carried_item: Node = null
var carried_weight: float = 0.0
#endregion

#region Path Integration
var path_integrator: Vector2 = Vector2.ZERO
#endregion

#region Memory
var memory: Dictionary = {}
#endregion

#region Behavior
var behavior_program: BehaviorProgram = null
var current_state_name: String = ""
#endregion

#region Efficiency Tracking
var efficiency_tracker: AntEfficiencyTracker = null
#endregion

#region Sensor Cache
var _sensor_cache: Dictionary = {}
#endregion

#region World Bounds
var _world_min: Vector2 = Vector2(10, 10)
var _world_max: Vector2 = Vector2(1990, 1990)
#endregion


func _ready() -> void:
	add_to_group("ants")
	efficiency_tracker = AntEfficiencyTracker.new()
	
	# Random initial heading
	heading = randf() * TAU
	desired_heading = heading
	
	# Start moving immediately
	speed = base_speed


func _process(delta: float) -> void:
	# Always process movement, even when paused (for testing)
	# Remove this check if you want ants to freeze when paused
	if not GameManager.is_running:
		return
	
	var dt: float = delta * GameManager.time_scale
	
	# 1. Smoothly turn toward desired heading
	var angle_diff: float = angle_difference(heading, desired_heading)
	if absf(angle_diff) > 0.01:
		var max_turn: float = max_turn_rate * dt
		heading += clampf(angle_diff, -max_turn, max_turn)
		heading = fmod(heading + TAU, TAU)
	
	# 2. Move forward (always, unless speed is explicitly 0)
	if speed > 0.1:
		var move_dist: float = speed * dt
		var dir: Vector2 = Vector2.from_angle(heading)
		var new_pos: Vector2 = global_position + dir * move_dist
		
		# Bounce off walls
		if new_pos.x < _world_min.x or new_pos.x > _world_max.x:
			heading = PI - heading
			desired_heading = heading
			new_pos.x = clampf(new_pos.x, _world_min.x, _world_max.x)
		if new_pos.y < _world_min.y or new_pos.y > _world_max.y:
			heading = -heading
			desired_heading = heading
			new_pos.y = clampf(new_pos.y, _world_min.y, _world_max.y)
		
		heading = fmod(heading + TAU, TAU)
		
		# Track movement
		var actual_dist: float = global_position.distance_to(new_pos)
		if actual_dist > 0.01:
			efficiency_tracker.record_distance(actual_dist)
			var move_cost: float = actual_dist * GameManager.get_action_cost("move_base")
			if carried_item != null:
				move_cost *= 1.5
			_apply_energy_cost(move_cost)
		
		# Update position
		global_position = new_pos
		
		# Update path integrator
		if colony != null:
			path_integrator = colony.nest_position - global_position
	
	# 3. Update visual rotation
	rotation = heading


func initialize(p_colony: Node, p_world: Node, p_index: int, p_behavior: BehaviorProgram) -> void:
	colony = p_colony
	world = p_world
	ant_index = p_index
	behavior_program = p_behavior
	
	# Set world bounds
	if world != null:
		_world_min = Vector2(10, 10)
		_world_max = Vector2(world.world_width - 10, world.world_height - 10)
	
	# Start at colony
	if colony != null:
		global_position = colony.nest_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
	
	# Ensure we're moving
	speed = base_speed
	
	# Initialize behavior
	if behavior_program != null:
		var init_result: Dictionary = behavior_program.enter_initial_state(self, _build_context())
		current_state_name = init_result.get("state", "")
		_apply_energy_cost(init_result.get("energy_cost", 0.0))


## Called by GameManager on decision tick - only changes direction, not position
func decision_tick() -> void:
	if not GameManager.is_ant_cohort(ant_index):
		return
	
	# Metabolism
	_apply_energy_cost(GameManager.get_action_cost("idle"))
	
	# Sense environment
	_update_sensors()
	
	# Run behavior
	var context: Dictionary = _build_context()
	if behavior_program != null:
		var result: Dictionary = behavior_program.process_tick(self, context, current_state_name)
		
		if not result.new_state.is_empty():
			current_state_name = result.new_state
		
		_apply_energy_cost(result.energy_cost)
		_process_action_results(result.action_results)
	
	# Death check
	if energy <= 0:
		_die("starvation")


func _update_sensors() -> void:
	_sensor_cache.clear()
	
	# Pheromones
	if world != null:
		var fields: Dictionary = world.get_pheromone_fields()
		for fname: String in fields:
			var field: PheromoneField = fields[fname]
			_sensor_cache["pheromone_" + fname] = field.sample_antenna(global_position, heading, sensor_distance, sensor_angle)
	
	# Nest
	if colony != null:
		var to_nest: Vector2 = colony.nest_position - global_position
		_sensor_cache["nest_direction"] = to_nest.angle()
		_sensor_cache["nest_distance"] = to_nest.length()
		_sensor_cache["at_nest"] = to_nest.length() < colony.nest_radius
	
	# Nearby entities
	if world != null:
		var sh: SpatialHash = world.get_spatial_hash()
		if sh != null:
			# Food
			var foods: Array = sh.query_radius_group(global_position, neighbor_sense_range, "food", self)
			var available: Array = []
			for f: Node in foods:
				if f != null and is_instance_valid(f) and not f.is_queued_for_deletion():
					if "is_picked_up" in f and not f.is_picked_up:
						available.append(f)
			
			_sensor_cache["nearby_food_count"] = available.size()
			if available.size() > 0:
				var nearest: Node = _find_nearest(available)
				if nearest != null:
					_sensor_cache["nearest_food"] = nearest
					_sensor_cache["nearest_food_distance"] = global_position.distance_to(nearest.global_position)
					_sensor_cache["nearest_food_direction"] = (nearest.global_position - global_position).angle()
			else:
				_sensor_cache["nearest_food_distance"] = INF
			
			# Ants
			var ants_nearby: Array = sh.query_radius_group(global_position, neighbor_sense_range, "ants", self)
			_sensor_cache["nearby_ants_count"] = ants_nearby.size()


func _build_context() -> Dictionary:
	var ctx: Dictionary = _sensor_cache.duplicate()
	ctx["position"] = global_position
	ctx["heading"] = heading
	ctx["energy"] = energy
	ctx["max_energy"] = max_energy
	ctx["energy_percent"] = (energy / max_energy) * 100.0
	ctx["base_speed"] = base_speed
	ctx["carried_item"] = carried_item
	ctx["carried_weight"] = carried_weight
	ctx["carried_type"] = carried_item.item_type if carried_item != null and "item_type" in carried_item else ""
	ctx["path_integrator"] = path_integrator
	ctx["memory"] = memory
	return ctx


func _process_action_results(results: Array) -> void:
	for r: Variant in results:
		if r is not Dictionary:
			continue
		
		# Heading change
		if r.has("desired_heading"):
			desired_heading = fmod(r.desired_heading + TAU, TAU)
		
		# Speed change
		if r.has("desired_speed"):
			speed = r.desired_speed
		
		# Pheromone deposit
		if r.has("deposit_pheromone") and world != null:
			var fname: String = r.deposit_pheromone
			var amt: float = r.get("deposit_amount", 1.0)
			if r.get("use_spread", false):
				world.deposit_pheromone_spread(fname, global_position, amt, r.get("spread_radius", 1))
			else:
				world.deposit_pheromone(fname, global_position, amt)
			efficiency_tracker.record_pheromone(amt)
		
		# Pickup
		if r.has("pickup_target") and r.pickup_target != null:
			var target: Node = r.pickup_target
			if is_instance_valid(target) and not target.is_queued_for_deletion():
				if target.has_method("pickup"):
					var picked: Node = target.pickup()
					if picked != null:
						carried_item = picked
						carried_weight = picked.weight if "weight" in picked else 1.0
		
		# Drop
		if r.get("drop_item", false) and carried_item != null:
			if r.get("is_delivery", false):
				var food_val: float = carried_item.food_value if "food_value" in carried_item else 1.0
				if colony != null:
					colony.receive_food(food_val)
				food_delivered.emit(food_val)
				efficiency_tracker.record_food_delivered(food_val)
				if behavior_program != null:
					behavior_program.record_food_collected(food_val)
				if is_instance_valid(carried_item):
					carried_item.queue_free()
			else:
				if is_instance_valid(carried_item) and carried_item.has_method("drop"):
					carried_item.drop(global_position)
			carried_item = null
			carried_weight = 0.0


func _apply_energy_cost(cost: float) -> void:
	energy -= cost
	efficiency_tracker.record_energy(cost)
	GameManager.global_stats.total_energy_spent += cost


func _find_nearest(entities: Array) -> Node:
	var nearest: Node = null
	var nearest_dist: float = INF
	for e: Node in entities:
		if e == null or not is_instance_valid(e):
			continue
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = e
	return nearest


func _die(cause: String) -> void:
	died.emit(cause)
	GameManager.global_stats.ants_starved += 1
	if carried_item != null and is_instance_valid(carried_item):
		if carried_item.has_method("drop"):
			carried_item.drop(global_position)
		carried_item = null
	queue_free()


func refill_energy(amount: float) -> void:
	energy = minf(energy + amount, max_energy)


func get_efficiency_stats() -> Dictionary:
	return efficiency_tracker.get_stats()


func stop_movement() -> void:
	speed = 0.0


func resume_movement() -> void:
	speed = base_speed
