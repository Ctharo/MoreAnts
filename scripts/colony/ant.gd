class_name Ant
extends Node2D
## Individual ant agent with continuous movement and event-driven triggers
## Movement happens every frame; strategic decisions at ticks; key moments trigger immediately
## Now includes social navigation - observing other ants' directions

#region Signals - Event-driven triggers
signal food_delivered(amount: float)
signal died(cause: String)

## Spatial events
signal entered_nest
signal exited_nest
signal food_contact(food: Node)

## State events
signal energy_critical
signal energy_restored
signal picked_up_item(item: Node)
signal dropped_item(was_delivery: bool)
#endregion

#region References
var colony: Node = null
var world: Node = null
#endregion

#region Identity
var ant_index: int = 0
var colony_id: int = 0  ## For multi-colony support
#endregion

#region Physical Properties
@export var base_speed: float = 80.0
@export var max_turn_rate: float = PI * 3.0
## Pheromone/scent sensing range - ants have excellent chemical sensing (50% further than sight)
@export var sensor_distance: float = 90.0
@export var sensor_angle: float = PI / 6
@export var pickup_range: float = 20.0
## Visual/sight range for detecting food and ants - ants have poor eyesight
@export var sight_sense_range: float = 60.0
@export var obstacle_sense_range: float = 35.0
## Range for observing other ants' directions (social navigation)
@export var ant_direction_sense_range: float = 80.0
#endregion

#region Movement - Updated every frame
var heading: float = 0.0
var desired_heading: float = 0.0
var speed: float = 80.0
#endregion

#region Obstacle Circumnavigation State
## The heading the ant was trying to achieve before obstacle avoidance
var _goal_heading: float = 0.0
## Whether we're currently in obstacle avoidance mode
var _avoiding_obstacle: bool = false
## Which direction we're circling the obstacle (1 = clockwise, -1 = counter-clockwise)
var _avoidance_direction: int = 1
## Timer for how long we've been avoiding (to prevent infinite loops)
var _avoidance_timer: float = 0.0
## Maximum time to spend in avoidance before giving up on original heading
const AVOIDANCE_TIMEOUT: float = 3.0
## How quickly to blend back to goal heading after clearing obstacle
const HEADING_RESTORE_RATE: float = 2.0
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

#region Debug Visualization (static flags shared by all ants)
static var debug_show_sensors: bool = false  ## Show sensing ranges
static var debug_show_pheromone_samples: bool = false  ## Show pheromone antenna sampling
static var debug_show_state: bool = false  ## Color ants by state
#endregion

#region Per-Ant Debug (for individual selection)
var debug_selected: bool = false  ## This specific ant is selected for debug
var debug_hovered: bool = false  ## This specific ant is being hovered
#endregion

#region Debug Data (per-ant data for visualization)
var _debug_pheromone_left: float = 0.0
var _debug_pheromone_center: float = 0.0
var _debug_pheromone_right: float = 0.0
var _debug_antenna_positions: Array[Vector2] = []  ## [left, center, right]
#endregion

#region Event State Tracking
var _was_at_nest: bool = false
var _was_energy_critical: bool = false
var _energy_critical_threshold: float = 0.2
var _energy_restored_threshold: float = 0.5
#endregion

#region World Bounds
var _world_min: Vector2 = Vector2(10, 10)
var _world_max: Vector2 = Vector2(1990, 1990)
#endregion


func _ready() -> void:
	add_to_group("ants")
	efficiency_tracker = AntEfficiencyTracker.new()

	# Load all sensing and movement settings
	_load_settings()

	heading = randf() * TAU
	desired_heading = heading
	_goal_heading = heading
	speed = base_speed

	_connect_event_handlers()


## Load sensing and movement parameters from SettingsManager
func _load_settings() -> void:
	sensor_distance = SettingsManager.get_setting("sensor_distance")
	sight_sense_range = SettingsManager.get_setting("sight_sense_range")
	obstacle_sense_range = SettingsManager.get_setting("obstacle_sense_range")
	ant_direction_sense_range = SettingsManager.get_setting("ant_direction_sense_range")
	pickup_range = SettingsManager.get_setting("pickup_range")
	base_speed = SettingsManager.get_setting("ant_base_speed")
	max_turn_rate = SettingsManager.get_setting("ant_max_turn_rate")


func _connect_event_handlers() -> void:
	entered_nest.connect(_on_entered_nest)
	food_contact.connect(_on_food_contact)
	energy_critical.connect(_on_energy_critical)


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return

	var dt: float = delta * GameManager.time_scale

	# 1. Check for obstacles ahead and handle circumnavigation
	_handle_obstacle_navigation(dt)

	# 2. Smoothly turn toward desired heading
	var angle_diff: float = angle_difference(heading, desired_heading)
	if absf(angle_diff) > 0.01:
		var max_turn: float = max_turn_rate * dt
		heading += clampf(angle_diff, -max_turn, max_turn)
		heading = fmod(heading + TAU, TAU)

	# 3. Move forward
	if speed > 0.1:
		var move_dist: float = speed * dt
		var dir: Vector2 = Vector2.from_angle(heading)
		var new_pos: Vector2 = global_position + dir * move_dist

		new_pos = _resolve_obstacle_collision(global_position, new_pos)

		# Handle world boundary - wrap heading smoothly instead of bouncing
		var hit_wall: bool = false
		if new_pos.x < _world_min.x:
			new_pos.x = _world_min.x
			hit_wall = true
			# Deflect heading away from wall, but try to maintain general direction
			_deflect_from_wall(Vector2.RIGHT)
		elif new_pos.x > _world_max.x:
			new_pos.x = _world_max.x
			hit_wall = true
			_deflect_from_wall(Vector2.LEFT)

		if new_pos.y < _world_min.y:
			new_pos.y = _world_min.y
			hit_wall = true
			_deflect_from_wall(Vector2.DOWN)
		elif new_pos.y > _world_max.y:
			new_pos.y = _world_max.y
			hit_wall = true
			_deflect_from_wall(Vector2.UP)

		heading = fmod(heading + TAU, TAU)

		var actual_dist: float = global_position.distance_to(new_pos)
		if actual_dist > 0.01:
			efficiency_tracker.record_distance(actual_dist)
			var move_cost: float = actual_dist * GameManager.get_action_cost("move_base")
			if carried_item != null:
				move_cost *= 1.5
			_apply_energy_cost(move_cost)

		global_position = new_pos

		if colony != null:
			path_integrator = colony.nest_position - global_position

	rotation = heading

	_check_spatial_events()
	_check_energy_events()
	_check_food_proximity()


## Deflect heading away from a wall while trying to maintain general direction
func _deflect_from_wall(wall_normal: Vector2) -> void:
	var current_dir: Vector2 = Vector2.from_angle(heading)

	# Reflect the direction off the wall
	var reflected: Vector2 = current_dir - 2.0 * current_dir.dot(wall_normal) * wall_normal

	# Blend between reflection and goal heading to avoid pure bouncing
	var goal_dir: Vector2 = Vector2.from_angle(_goal_heading)

	# If goal direction would take us back into the wall, use reflection
	if goal_dir.dot(wall_normal) < 0:
		# Blend: 70% reflection, 30% sliding along wall
		var slide_dir: Vector2 = current_dir - wall_normal * current_dir.dot(wall_normal)
		if slide_dir.length() > 0.1:
			slide_dir = slide_dir.normalized()
			reflected = (reflected * 0.7 + slide_dir * 0.3).normalized()

		heading = reflected.angle()
		desired_heading = heading
	else:
		# Goal is away from wall, blend toward it
		var blended: Vector2 = (reflected * 0.3 + goal_dir * 0.7).normalized()
		heading = blended.angle()
		desired_heading = _goal_heading


## Handle obstacle navigation with circumnavigation behavior
func _handle_obstacle_navigation(dt: float) -> void:
	if world == null:
		return

	var sh: SpatialHash = world.get_spatial_hash()
	if sh == null:
		return

	# Probe ahead in multiple directions
	var probe_result: Dictionary = _probe_for_obstacles(sh)
	var obstacle_ahead: bool = probe_result.get("blocked", false)
	var nearest_dist: float = probe_result.get("nearest_dist", INF)
	var left_blocked: bool = probe_result.get("left_blocked", false)
	var right_blocked: bool = probe_result.get("right_blocked", false)
	var center_blocked: bool = probe_result.get("center_blocked", false)

	if obstacle_ahead:
		if not _avoiding_obstacle:
			# Just started avoiding - save the goal heading
			_goal_heading = desired_heading
			_avoiding_obstacle = true
			_avoidance_timer = 0.0

			# Choose avoidance direction based on which side is more open
			# Prefer the direction that keeps us closer to our goal
			var goal_dir: Vector2 = Vector2.from_angle(_goal_heading)
			var left_dir: Vector2 = Vector2.from_angle(heading - PI / 2)
			var right_dir: Vector2 = Vector2.from_angle(heading + PI / 2)

			var left_alignment: float = left_dir.dot(goal_dir)
			var right_alignment: float = right_dir.dot(goal_dir)

			# Also consider which side is blocked
			if left_blocked and not right_blocked:
				_avoidance_direction = 1  # Go right/clockwise
			elif right_blocked and not left_blocked:
				_avoidance_direction = -1  # Go left/counter-clockwise
			elif left_alignment > right_alignment:
				_avoidance_direction = -1  # Left is closer to goal
			else:
				_avoidance_direction = 1  # Right is closer to goal

		_avoidance_timer += dt

		# Calculate avoidance turn based on proximity
		var urgency: float = 1.0 - clampf(nearest_dist / obstacle_sense_range, 0.0, 1.0)
		var turn_amount: float = (PI / 3) * (0.5 + urgency * 0.5)

		# Apply stronger turn if center is blocked
		if center_blocked:
			turn_amount *= 1.5

		# Turn in the chosen avoidance direction
		desired_heading = heading + turn_amount * _avoidance_direction

		# Check for timeout - if we've been avoiding too long, accept new direction
		if _avoidance_timer > AVOIDANCE_TIMEOUT:
			_goal_heading = desired_heading
			_avoidance_timer = 0.0
	else:
		# No obstacle ahead
		if _avoiding_obstacle:
			# We were avoiding but path is now clear
			# Check if goal heading is now achievable
			var goal_probe: Dictionary = _probe_direction_for_obstacles(sh, _goal_heading)

			if not goal_probe.get("blocked", false):
				# Goal direction is clear - start returning to it
				_avoiding_obstacle = false
				_avoidance_timer = 0.0

				# Smoothly blend back to goal heading
				var current_dir: Vector2 = Vector2.from_angle(heading)
				var goal_dir: Vector2 = Vector2.from_angle(_goal_heading)
				var blended: Vector2 = current_dir.lerp(goal_dir, HEADING_RESTORE_RATE * dt)
				desired_heading = blended.angle()
			else:
				# Goal still blocked, continue circumnavigating
				# But turn slightly toward goal to test if we can start heading that way
				var goal_bias: float = 0.1 * _avoidance_direction * -1  # Bias toward goal
				desired_heading = heading + goal_bias
		else:
			# Not avoiding, gradually ensure desired_heading trends toward goal
			# This handles the case where behavior system sets a new desired heading
			_goal_heading = desired_heading


## Probe for obstacles in multiple directions
func _probe_for_obstacles(sh: SpatialHash) -> Dictionary:
	var probe_angles: Array[float] = [0.0, -0.4, 0.4, -0.8, 0.8]
	var result: Dictionary = {
		"blocked": false,
		"left_blocked": false,
		"right_blocked": false,
		"center_blocked": false,
		"nearest_dist": INF,
	}

	for i: int in range(probe_angles.size()):
		var probe_angle: float = heading + probe_angles[i]
		var probe_end: Vector2 = global_position + Vector2.from_angle(probe_angle) * obstacle_sense_range

		var obstacles: Array = sh.query_radius_group(probe_end, 15.0, "obstacles")

		for obs: Node in obstacles:
			if not is_instance_valid(obs):
				continue

			if obs.has_method("intersects_segment"):
				if obs.intersects_segment(global_position, probe_end):
					result.blocked = true

					if i == 0:
						result.center_blocked = true
					elif i == 1 or i == 3:
						result.left_blocked = true
					elif i == 2 or i == 4:
						result.right_blocked = true

					if obs.has_method("get_distance_to_surface"):
						var dist: float = obs.get_distance_to_surface(global_position)
						result.nearest_dist = minf(result.nearest_dist, dist)

	return result


## Probe a specific direction for obstacles
func _probe_direction_for_obstacles(sh: SpatialHash, check_heading: float) -> Dictionary:
	var result: Dictionary = {"blocked": false, "dist": INF}

	var probe_end: Vector2 = global_position + Vector2.from_angle(check_heading) * obstacle_sense_range
	var obstacles: Array = sh.query_radius_group(probe_end, 15.0, "obstacles")

	for obs: Node in obstacles:
		if not is_instance_valid(obs):
			continue

		if obs.has_method("intersects_segment"):
			if obs.intersects_segment(global_position, probe_end):
				result.blocked = true
				if obs.has_method("get_distance_to_surface"):
					result.dist = minf(result.dist, obs.get_distance_to_surface(global_position))

	return result


func _resolve_obstacle_collision(from_pos: Vector2, to_pos: Vector2) -> Vector2:
	if world == null:
		return to_pos

	var sh: SpatialHash = world.get_spatial_hash()
	if sh == null:
		return to_pos

	var mid_point: Vector2 = (from_pos + to_pos) / 2.0
	var move_dist: float = from_pos.distance_to(to_pos)
	var obstacles: Array = sh.query_radius_group(mid_point, move_dist + 20.0, "obstacles")

	var final_pos: Vector2 = to_pos

	for obs: Node in obstacles:
		if not is_instance_valid(obs):
			continue

		if obs.has_method("contains_point") and obs.contains_point(final_pos):
			if obs.has_method("get_nearest_surface_point") and obs.has_method("get_surface_normal"):
				var surface_point: Vector2 = obs.get_nearest_surface_point(final_pos)
				var normal: Vector2 = obs.get_surface_normal(final_pos)

				final_pos = surface_point + normal * 3.0

				# When pushed out of obstacle, continue in a sliding direction
				# Don't completely override desired_heading - let circumnavigation handle it
				var movement_dir: Vector2 = (to_pos - from_pos).normalized()
				var slide_dir: Vector2 = movement_dir - normal * movement_dir.dot(normal)
				if slide_dir.length() > 0.1:
					# Only adjust heading slightly to slide along surface
					var slide_heading: float = slide_dir.angle()
					var blend_factor: float = 0.3
					heading = lerp_angle(heading, slide_heading, blend_factor)

	return final_pos


func _check_spatial_events() -> void:
	if colony == null:
		return

	var dist_to_nest: float = global_position.distance_to(colony.nest_position)
	var is_at_nest: bool = dist_to_nest < colony.nest_radius

	if is_at_nest and not _was_at_nest:
		entered_nest.emit()
	elif not is_at_nest and _was_at_nest:
		exited_nest.emit()

	_was_at_nest = is_at_nest


func _check_energy_events() -> void:
	var energy_percent: float = energy / max_energy

	if energy_percent < _energy_critical_threshold and not _was_energy_critical:
		_was_energy_critical = true
		energy_critical.emit()
	elif energy_percent > _energy_restored_threshold and _was_energy_critical:
		_was_energy_critical = false
		energy_restored.emit()


func _check_food_proximity() -> void:
	if carried_item != null:
		return

	if world == null:
		return

	var sh: SpatialHash = world.get_spatial_hash()
	if sh == null:
		return

	var foods: Array = sh.query_radius_group(global_position, pickup_range, "food", self)
	for food: Node in foods:
		if food == null or not is_instance_valid(food):
			continue
		if food.is_queued_for_deletion():
			continue
		if "is_picked_up" in food and food.is_picked_up:
			continue
		if "is_available" in food and food.has_method("is_available"):
			if not food.is_available():
				continue

		food_contact.emit(food)
		break


#region Event Handlers
func _on_entered_nest() -> void:
	if carried_item != null:
		_deposit_food_at_nest()
		# Only slow down briefly when depositing food, then resume
		speed = base_speed * 0.5  # Slow down but don't stop completely
	# Don't set speed to 0 when just passing through!


func _on_food_contact(food: Node) -> void:
	if current_state_name in ["Search", "Harvest"]:
		_try_pickup_food(food)


func _on_energy_critical() -> void:
	if current_state_name not in ["GoHome", "Rest", "Deposit"]:
		_force_state_change("GoHome")
#endregion


#region Immediate Actions
func _deposit_food_at_nest() -> void:
	if carried_item == null:
		return

	var food_val: float = carried_item.food_value if "food_value" in carried_item else 1.0

	if colony != null:
		colony.receive_food(food_val)

	food_delivered.emit(food_val)
	efficiency_tracker.record_food_delivered(food_val)
	if behavior_program != null:
		behavior_program.record_food_collected(food_val)

	if is_instance_valid(carried_item):
		carried_item.queue_free()

	carried_item = null
	carried_weight = 0.0

	dropped_item.emit(true)


func _try_pickup_food(food: Node) -> void:
	if carried_item != null:
		return

	if not is_instance_valid(food):
		return

	if food.has_method("pickup"):
		var picked: Node = food.pickup()
		if picked != null:
			carried_item = picked
			carried_weight = picked.weight if "weight" in picked else 1.0
			picked_up_item.emit(picked)
			_force_state_change("Return")


func _force_state_change(new_state_name: String) -> void:
	if behavior_program == null:
		return

	var new_state: BehaviorState = behavior_program.get_state(new_state_name)
	if new_state == null:
		return

	var current_state: BehaviorState = behavior_program.get_state(current_state_name)
	if current_state != null:
		var exit_result: Dictionary = current_state.exit(self, _build_context())
		_apply_energy_cost(exit_result.get("energy_cost", 0.0))

	var enter_result: Dictionary = new_state.enter(self, _build_context())
	_apply_energy_cost(enter_result.get("energy_cost", 0.0))

	current_state_name = new_state_name
	behavior_program.total_transitions += 1
#endregion


func initialize(p_colony: Node, p_world: Node, p_index: int, p_behavior: BehaviorProgram) -> void:
	colony = p_colony
	world = p_world
	ant_index = p_index
	behavior_program = p_behavior

	if colony != null and "colony_id" in colony:
		colony_id = colony.colony_id

	if world != null:
		_world_min = Vector2(10, 10)
		_world_max = Vector2(world.world_width - 10, world.world_height - 10)

	if colony != null:
		global_position = colony.nest_position + Vector2(randf_range(-20, 20), randf_range(-20, 20))
		_was_at_nest = true

	speed = base_speed

	if behavior_program != null:
		var init_result: Dictionary = behavior_program.enter_initial_state(self, _build_context())
		current_state_name = init_result.get("state", "")
		_apply_energy_cost(init_result.get("energy_cost", 0.0))


## Called by GameManager on decision tick
func decision_tick() -> void:
	if not GameManager.is_ant_cohort(ant_index):
		return
	_apply_energy_cost(GameManager.get_action_cost("idle"))
	_update_sensors()

	var context: Dictionary = _build_context()
	if behavior_program != null:
		var result: Dictionary = behavior_program.process_tick(self, context, current_state_name)

		if not result.new_state.is_empty():
			current_state_name = result.new_state

		_apply_energy_cost(result.energy_cost)
		_process_action_results(result.action_results)

	if energy <= 0:
		_die("starvation")


func _update_sensors() -> void:
	_sensor_cache.clear()

	# Pheromones - uses sensor_distance (scent range, longer than sight)
	if world != null:
		var fields: Dictionary = world.get_pheromone_fields()
		for fname: String in fields:
			var field: PheromoneField = fields[fname]
			var samples: Dictionary = field.sample_antenna(global_position, heading, sensor_distance, sensor_angle)
			_sensor_cache["pheromone_" + fname] = samples

			# Store debug data for primary pheromone (food_trail for Search, home_trail for Return)
			if debug_show_pheromone_samples or debug_selected or debug_hovered:
				if (current_state_name == "Search" and fname == "food_trail") or \
				   (current_state_name == "Return" and fname == "home_trail"):
					_debug_pheromone_left = samples.get("left", 0.0)
					_debug_pheromone_center = samples.get("center", 0.0)
					_debug_pheromone_right = samples.get("right", 0.0)

					# Store antenna positions for debug drawing
					_debug_antenna_positions = [
						global_position + Vector2(cos(heading - sensor_angle), sin(heading - sensor_angle)) * sensor_distance,
						global_position + Vector2(cos(heading), sin(heading)) * sensor_distance,
						global_position + Vector2(cos(heading + sensor_angle), sin(heading + sensor_angle)) * sensor_distance,
					]

	# Nest
	if colony != null:
		var to_nest: Vector2 = colony.nest_position - global_position
		_sensor_cache["nest_direction"] = to_nest.angle()
		_sensor_cache["nest_distance"] = to_nest.length()
		_sensor_cache["at_nest"] = to_nest.length() < colony.nest_radius

	# Nearby entities - uses sight_sense_range (shorter than scent)
	if world != null:
		var sh: SpatialHash = world.get_spatial_hash()
		if sh != null:
			_sense_food(sh)
			_sense_ants(sh)
			_sense_obstacles(sh)
			_sense_ant_directions(sh)  # Social navigation


func _sense_food(sh: SpatialHash) -> void:
	# Food detection uses sight range (visual detection)
	var foods: Array = sh.query_radius_group(global_position, sight_sense_range, "food", self)
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


func _sense_ants(sh: SpatialHash) -> void:
	# Ant detection uses sight range (visual detection)
	var ants_nearby: Array = sh.query_radius_group(global_position, sight_sense_range, "ants", self)
	_sensor_cache["nearby_ants_count"] = ants_nearby.size()


func _sense_obstacles(sh: SpatialHash) -> void:
	var obstacles_nearby: Array = sh.query_radius_group(global_position, obstacle_sense_range, "obstacles")
	_sensor_cache["nearby_obstacles_count"] = obstacles_nearby.size()
	if obstacles_nearby.size() > 0:
		var nearest_obs: Node = _find_nearest(obstacles_nearby)
		if nearest_obs != null and nearest_obs.has_method("get_distance_to_surface"):
			_sensor_cache["nearest_obstacle_distance"] = nearest_obs.get_distance_to_surface(global_position)
		else:
			_sensor_cache["nearest_obstacle_distance"] = INF
	else:
		_sensor_cache["nearest_obstacle_distance"] = INF


## Sense other ants' directions for social navigation
func _sense_ant_directions(sh: SpatialHash) -> void:
	var ants_nearby: Array = sh.query_radius_group(global_position, ant_direction_sense_range, "ants", self)

	var food_direction_hint: Vector2 = Vector2.ZERO
	var search_direction_hint: Vector2 = Vector2.ZERO
	var carrying_boost: float = SettingsManager.get_setting("ant_direction_carrying_boost")
	var decay_factor: float = SettingsManager.get_setting("ant_direction_decay")

	var food_weight_total: float = 0.0
	var search_weight_total: float = 0.0
	var carrying_count: int = 0
	var searching_count: int = 0

	for ant_node: Node in ants_nearby:
		if not is_instance_valid(ant_node):
			continue
		if ant_node == self:
			continue

		var ant_pos: Vector2 = ant_node.global_position
		var ant_heading: float = ant_node.heading if "heading" in ant_node else 0.0
		var ant_carrying: bool = ant_node.carried_item != null if "carried_item" in ant_node else false

		var dist: float = global_position.distance_to(ant_pos)
		var weight: float = pow(decay_factor, dist / ant_direction_sense_range)

		var ant_dir: Vector2 = Vector2.from_angle(ant_heading)

		if ant_carrying:
			var food_hint_dir: Vector2 = -ant_dir
			food_direction_hint += food_hint_dir * weight * carrying_boost
			food_weight_total += weight * carrying_boost
			carrying_count += 1
		else:
			if colony != null:
				var ant_to_nest: Vector2 = colony.nest_position - ant_pos
				var heading_away_from_nest: bool = ant_dir.dot(ant_to_nest.normalized()) < 0.3

				if heading_away_from_nest:
					search_direction_hint += ant_dir * weight
					search_weight_total += weight
					searching_count += 1

	if food_weight_total > 0.01:
		food_direction_hint /= food_weight_total
		_sensor_cache["ant_food_hint_direction"] = food_direction_hint.angle()
		_sensor_cache["ant_food_hint_strength"] = food_direction_hint.length()
	else:
		_sensor_cache["ant_food_hint_direction"] = 0.0
		_sensor_cache["ant_food_hint_strength"] = 0.0

	if search_weight_total > 0.01:
		search_direction_hint /= search_weight_total
		_sensor_cache["ant_search_hint_direction"] = search_direction_hint.angle()
		_sensor_cache["ant_search_hint_strength"] = search_direction_hint.length()
	else:
		_sensor_cache["ant_search_hint_direction"] = 0.0
		_sensor_cache["ant_search_hint_strength"] = 0.0

	var combined_hint: Vector2 = Vector2.ZERO
	if food_weight_total > 0.01:
		combined_hint += Vector2.from_angle(_sensor_cache["ant_food_hint_direction"]) * _sensor_cache["ant_food_hint_strength"] * 1.5
	if search_weight_total > 0.01:
		combined_hint += Vector2.from_angle(_sensor_cache["ant_search_hint_direction"]) * _sensor_cache["ant_search_hint_strength"]

	if combined_hint.length() > 0.01:
		_sensor_cache["ant_direction_hint"] = combined_hint.angle()
		_sensor_cache["ant_direction_strength"] = minf(combined_hint.length(), 1.0)
	else:
		_sensor_cache["ant_direction_hint"] = heading
		_sensor_cache["ant_direction_strength"] = 0.0

	_sensor_cache["nearby_carrying_count"] = carrying_count
	_sensor_cache["nearby_searching_count"] = searching_count


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
	ctx["at_nest"] = _was_at_nest
	ctx["current_state"] = current_state_name
	ctx["avoiding_obstacle"] = _avoiding_obstacle
	return ctx


func _process_action_results(results: Array) -> void:
	for r: Variant in results:
		if r is not Dictionary:
			continue

		if r.has("desired_heading"):
			var new_heading: float = fmod(r.desired_heading + TAU, TAU)
			# Only update goal heading if we're not actively avoiding
			# This lets the behavior system set direction, but obstacle avoidance takes priority
			if not _avoiding_obstacle:
				_goal_heading = new_heading
				desired_heading = new_heading
			else:
				# Update goal for after we clear the obstacle
				_goal_heading = new_heading

		if r.has("desired_speed"):
			speed = r.desired_speed

		if r.has("deposit_pheromone") and world != null:
			var fname: String = r.deposit_pheromone
			var amt: float = r.get("deposit_amount", 1.0)
			if r.get("use_spread", false):
				world.deposit_pheromone_spread(fname, global_position, amt, r.get("spread_radius", 1))
			else:
				world.deposit_pheromone(fname, global_position, amt)
			efficiency_tracker.record_pheromone(amt)

		if r.has("pickup_target") and r.pickup_target != null and carried_item == null:
			var target: Node = r.pickup_target
			if is_instance_valid(target) and not target.is_queued_for_deletion():
				if target.has_method("pickup"):
					var picked: Node = target.pickup()
					if picked != null:
						carried_item = picked
						carried_weight = picked.weight if "weight" in picked else 1.0
						picked_up_item.emit(picked)

		if r.get("drop_item", false) and carried_item != null:
			if r.get("is_delivery", false):
				_deposit_food_at_nest()
			else:
				if is_instance_valid(carried_item) and carried_item.has_method("drop"):
					carried_item.drop(global_position)
				carried_item = null
				carried_weight = 0.0
				dropped_item.emit(false)


func _apply_energy_cost(cost: float) -> void:
	return
	#FIXME Energy is disabled
	#energy -= cost
	#efficiency_tracker.record_energy(cost)
	#GameManager.global_stats.total_energy_spent += cost


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


## Check if this ant should show debug (selected, hovered, or global debug enabled)
func should_show_debug() -> bool:
	return debug_selected or debug_hovered


#region Debug Visualization Static Methods
static func toggle_sensor_debug() -> void:
	debug_show_sensors = not debug_show_sensors


static func toggle_pheromone_debug() -> void:
	debug_show_pheromone_samples = not debug_show_pheromone_samples


static func toggle_state_debug() -> void:
	debug_show_state = not debug_show_state


static func set_all_debug(enabled: bool) -> void:
	debug_show_sensors = enabled
	debug_show_pheromone_samples = enabled
	debug_show_state = enabled
#endregion
