class_name Colony
extends Node2D
## Colony - Manages a group of ants with shared resources and behavior

signal colony_stats_updated
signal ant_spawned(ant: Node)
signal ant_died(ant: Node, cause: String)
signal food_received(amount: float)

#region Colony Configuration
@export var colony_name: String = "Colony"
@export var colony_color: Color = Color.RED
@export var max_ants: int = 100
@export var initial_ant_count: int = 20
@export var min_ant_count: int = 10  ## Minimum ants to maintain
@export var spawn_rate: float = 0.5  ## Ants per second when food available
@export var ant_spawn_cost: float = 10.0  ## Food required to spawn an ant
@export var energy_refill_rate: float = 50.0  ## Energy per second when at nest (increased!)
#endregion

#region Nest Properties
@export var nest_position: Vector2 = Vector2(1000, 1000)
@export var nest_radius: float = 50.0
#endregion

#region Resources
var food_stored: float = 100.0
var total_food_collected: float = 0.0
#endregion

#region Ants
var ants: Array = []
var _ant_index_counter: int = 0
#endregion

#region Behavior
var behavior_program: BehaviorProgram = null  ## BehaviorProgram for this colony's ants
#endregion

#region References
var world: Node = null
#endregion

#region Spawn Timer
var _spawn_accumulator: float = 0.0
#endregion

#region Ant Script
var _AntScript: Script = null
#endregion

#region State Colors for Debug
var _state_colors: Dictionary = {
	"Search": Color.YELLOW,
	"Harvest": Color.ORANGE,
	"Return": Color.GREEN,
	"GoHome": Color.ORANGE_RED,
	"Rest": Color.LIGHT_BLUE,
	"Deposit": Color.LIME_GREEN,
}
#endregion


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


func _on_ant_delivered_food(_amount: float) -> void:
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
				# Refill energy at a rate, costs food (reduced food cost for faster refill)
				var refill_amount: float = minf(energy_refill_rate * delta, energy_needed)
				var food_cost: float = refill_amount * 0.1  # Reduced food cost
				
				if food_stored >= food_cost:
					food_stored -= food_cost
					ant.refill_energy(refill_amount)


## Find the nearest ant to a world position within a given radius
## Returns null if no ant is within the radius
func find_nearest_ant(world_pos: Vector2, max_radius: float) -> Node:
	var nearest: Node = null
	var nearest_dist_sq: float = max_radius * max_radius
	
	for ant: Node in ants:
		if ant == null or not is_instance_valid(ant):
			continue
		
		var dist_sq: float = world_pos.distance_squared_to(ant.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = ant
	
	return nearest


func get_stats() -> Dictionary:
	var total_energy: float = 0.0
	var total_food_carried: float = 0.0
	var ants_carrying: int = 0
	var valid_ant_count: int = 0
	var state_counts: Dictionary = {}
	
	for ant: Node in ants:
		if ant == null or not is_instance_valid(ant):
			continue
		valid_ant_count += 1
		total_energy += ant.energy
		if ant.carried_item != null:
			ants_carrying += 1
			total_food_carried += ant.carried_weight
		
		# Count states
		var state_name: String = ant.current_state_name if "current_state_name" in ant else "Unknown"
		state_counts[state_name] = state_counts.get(state_name, 0) + 1
	
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
		"state_counts": state_counts,
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
		
		# Check if this ant should show individual debug
		var show_individual_debug: bool = ant.should_show_debug() if ant.has_method("should_show_debug") else false
		
		# Color based on state if global debug enabled OR individual debug
		if Ant.debug_show_state or show_individual_debug:
			var state_name: String = ant.current_state_name if "current_state_name" in ant else ""
			ant_color = _state_colors.get(state_name, colony_color)
		elif ant.energy < ant.max_energy * 0.3:
			ant_color = Color.ORANGE_RED  # Low energy warning
		
		# Draw selection/hover indicator
		if ant.debug_selected:
			# Draw selection ring
			draw_arc(ant_pos, 8.0, 0, TAU, 16, Color.WHITE, 2.0)
		elif ant.debug_hovered:
			# Draw hover ring (thinner)
			draw_arc(ant_pos, 7.0, 0, TAU, 16, Color(1.0, 1.0, 1.0, 0.5), 1.0)
		
		# Draw ant body
		draw_circle(ant_pos, 3.0, ant_color)
		
		# Draw heading indicator
		var heading_end: Vector2 = ant_pos + Vector2(cos(ant.heading), sin(ant.heading)) * 6.0
		draw_line(ant_pos, heading_end, ant_color, 1.0)
		
		# Draw carried food on top of ant at proper food size
		if ant.carried_item != null:
			var food_radius: float = 6.0
			if "base_radius" in ant.carried_item:
				food_radius = ant.carried_item.base_radius
			draw_circle(ant_pos, food_radius, Color.YELLOW_GREEN)
			draw_arc(ant_pos, food_radius, 0, TAU, 12, Color.YELLOW_GREEN.darkened(0.3), 1.0)
		
		# Debug: Draw sensor range (global OR individual)
		if Ant.debug_show_sensors or show_individual_debug:
			_draw_ant_debug_sensors(ant, ant_pos)
		
		# Debug: Draw pheromone samples (global OR individual)
		if Ant.debug_show_pheromone_samples or show_individual_debug:
			_draw_ant_debug_pheromones(ant, ant_pos)
		
		# Draw ant info panel for selected/hovered ants
		if show_individual_debug:
			_draw_ant_info_panel(ant, ant_pos)


func _draw_ant_debug_sensors(ant: Node, ant_pos: Vector2) -> void:
	## Draw sensing ranges for debugging
	var scent_range: float = ant.sensor_distance if "sensor_distance" in ant else 90.0
	var sight_range: float = ant.sight_sense_range if "sight_sense_range" in ant else 60.0
	var pickup_range: float = ant.pickup_range if "pickup_range" in ant else 20.0
	
	# Scent/pheromone sensing range (outer, green - longest range)
	draw_arc(ant_pos, scent_range, 0, TAU, 16, Color(0.0, 1.0, 0.0, 0.25), 1.0)
	
	# Sight sensing range (middle, blue)
	draw_arc(ant_pos, sight_range, 0, TAU, 16, Color(0.5, 0.5, 1.0, 0.3), 1.0)
	
	# Pheromone sensing cone (with angle)
	var heading_val: float = ant.heading if "heading" in ant else 0.0
	var sensor_angle: float = ant.sensor_angle if "sensor_angle" in ant else PI / 6
	
	# Draw sensing cone for scent
	var left_angle: float = heading_val - sensor_angle
	var right_angle: float = heading_val + sensor_angle
	
	var left_end: Vector2 = ant_pos + Vector2(cos(left_angle), sin(left_angle)) * scent_range
	var center_end: Vector2 = ant_pos + Vector2(cos(heading_val), sin(heading_val)) * scent_range
	var right_end: Vector2 = ant_pos + Vector2(cos(right_angle), sin(right_angle)) * scent_range
	
	draw_line(ant_pos, left_end, Color(0.0, 1.0, 0.0, 0.4), 1.0)
	draw_line(ant_pos, center_end, Color(0.0, 1.0, 0.0, 0.6), 1.0)
	draw_line(ant_pos, right_end, Color(0.0, 1.0, 0.0, 0.4), 1.0)
	
	# Pickup range (inner, yellow)
	draw_arc(ant_pos, pickup_range, 0, TAU, 12, Color(1.0, 1.0, 0.0, 0.4), 1.0)


func _draw_ant_debug_pheromones(ant: Node, ant_pos: Vector2) -> void:
	## Draw pheromone sample values at antenna positions
	if not "_debug_antenna_positions" in ant:
		return
	
	var positions: Array = ant._debug_antenna_positions
	if positions.size() < 3:
		return
	
	var left_val: float = ant._debug_pheromone_left if "_debug_pheromone_left" in ant else 0.0
	var center_val: float = ant._debug_pheromone_center if "_debug_pheromone_center" in ant else 0.0
	var right_val: float = ant._debug_pheromone_right if "_debug_pheromone_right" in ant else 0.0
	
	# Normalize for display
	var max_val: float = maxf(maxf(left_val, center_val), maxf(right_val, 1.0))
	
	# Draw circles at antenna positions sized by pheromone strength
	for i: int in range(3):
		var world_pos: Vector2 = positions[i]
		var local_pos: Vector2 = world_pos - global_position
		var val: float = [left_val, center_val, right_val][i]
		var normalized: float = val / max_val if max_val > 0.01 else 0.0
		
		# Size based on pheromone strength (2-8 pixels)
		var radius: float = 2.0 + normalized * 6.0
		
		# Color intensity based on strength
		var col: Color = Color(0.0, 1.0, 0.0, 0.3 + normalized * 0.7)
		
		draw_circle(local_pos, radius, col)


func _draw_ant_info_panel(ant: Node, ant_pos: Vector2) -> void:
	## Draw a small info panel next to the selected/hovered ant
	var panel_offset: Vector2 = Vector2(15, -50)
	var panel_pos: Vector2 = ant_pos + panel_offset
	var line_height: float = 12.0
	var panel_width: float = 100.0
	var line_count: int = 6
	var panel_height: float = line_height * line_count + 8.0
	
	# Draw panel background
	var panel_rect: Rect2 = Rect2(panel_pos - Vector2(4, 4), Vector2(panel_width + 8, panel_height))
	draw_rect(panel_rect, Color(0.0, 0.0, 0.0, 0.7))
	draw_rect(panel_rect, Color(0.5, 0.5, 0.5, 0.5), false, 1.0)
	
	# Draw info lines using simple shapes (can't draw text in _draw easily)
	# Instead, we'll draw colored bars for energy and state indicators
	
	var y_offset: float = 0.0
	
	# Energy bar
	var energy_percent: float = ant.energy / ant.max_energy if ant.max_energy > 0 else 0.0
	var energy_bar_width: float = panel_width * energy_percent
	var energy_color: Color = Color.GREEN if energy_percent > 0.5 else (Color.YELLOW if energy_percent > 0.2 else Color.RED)
	draw_rect(Rect2(panel_pos + Vector2(0, y_offset), Vector2(energy_bar_width, 8)), energy_color)
	draw_rect(Rect2(panel_pos + Vector2(0, y_offset), Vector2(panel_width, 8)), Color.WHITE, false, 1.0)
	y_offset += line_height
	
	# State color indicator
	var state_name: String = ant.current_state_name if "current_state_name" in ant else ""
	var state_color: Color = _state_colors.get(state_name, Color.GRAY)
	draw_rect(Rect2(panel_pos + Vector2(0, y_offset), Vector2(panel_width, 8)), state_color)
	y_offset += line_height
	
	# Carrying indicator
	var carrying: bool = ant.carried_item != null
	var carry_color: Color = Color.YELLOW_GREEN if carrying else Color.DARK_GRAY
	draw_rect(Rect2(panel_pos + Vector2(0, y_offset), Vector2(20 if carrying else 10, 8)), carry_color)
	y_offset += line_height
	
	# Speed indicator (as bar)
	var speed_percent: float = ant.speed / ant.base_speed if ant.base_speed > 0 else 0.0
	var speed_bar_width: float = panel_width * clampf(speed_percent, 0.0, 1.0)
	draw_rect(Rect2(panel_pos + Vector2(0, y_offset), Vector2(speed_bar_width, 8)), Color.CORNFLOWER_BLUE)
	draw_rect(Rect2(panel_pos + Vector2(0, y_offset), Vector2(panel_width, 8)), Color.WHITE, false, 1.0)
	y_offset += line_height
	
	# Direction indicator (small arrow showing heading)
	var arrow_center: Vector2 = panel_pos + Vector2(panel_width / 2, y_offset + 8)
	var arrow_length: float = 15.0
	var arrow_end: Vector2 = arrow_center + Vector2.from_angle(ant.heading) * arrow_length
	draw_line(arrow_center, arrow_end, Color.WHITE, 2.0)
	# Arrowhead
	var arrow_head_angle: float = 0.5
	var arrow_head_length: float = 5.0
	var head_left: Vector2 = arrow_end - Vector2.from_angle(ant.heading - arrow_head_angle) * arrow_head_length
	var head_right: Vector2 = arrow_end - Vector2.from_angle(ant.heading + arrow_head_angle) * arrow_head_length
	draw_line(arrow_end, head_left, Color.WHITE, 2.0)
	draw_line(arrow_end, head_right, Color.WHITE, 2.0)
