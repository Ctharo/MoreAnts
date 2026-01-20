class_name MoveAction
extends BehaviorAction
## Action that controls ant movement and steering
## Now supports social navigation - following hints from other ants' directions

enum MoveMode {
	FOLLOW_PHEROMONE = 0,      ## Gradient ascent on pheromone field
	AVOID_PHEROMONE = 1,       ## Gradient descent (flee from scent)
	TOWARD_NEST = 2,           ## Follow path integrator home
	AWAY_FROM_NEST = 3,        ## Explore away from nest
	RANDOM_WALK = 4,           ## Correlated random walk
	TOWARD_NEAREST_FOOD = 5,   ## Beeline to detected food
	TOWARD_NEAREST_ANT = 6,    ## Move toward nearest ant
	AWAY_FROM_NEAREST_ANT = 7, ## Flee from nearest ant
	FOLLOW_ANT = 8,            ## Follow an ant with food
	WEIGHTED_BLEND = 9,        ## Combine multiple influences including ant direction
}

## Movement mode
@export var move_mode: MoveMode = MoveMode.RANDOM_WALK

## Speed multiplier (0-1)
@export var speed_multiplier: float = 1.0

## Pheromone field to follow (for FOLLOW/AVOID modes)
@export var pheromone_name: String = "food_trail"

## Blend weights for WEIGHTED_BLEND mode
## Now includes "ant_direction" for social navigation
@export var blend_weights: Dictionary = {
	"pheromone": 0.5,
	"random": 0.3,
	"nest": 0.2,
	"ant_direction": 0.0,  # Weight for following other ants' directional hints
	"food": 0.0,
}

## Random walk parameters
@export var random_turn_rate: float = 0.3
@export var random_bias: float = 0.0

## Whether to use settings-based weights (overrides blend_weights)
@export var use_settings_weights: bool = true


func _init() -> void:
	display_name = "Move"
	base_energy_cost = 0.1


func _get_cost_category() -> String:
	return "movement"


func _execute_internal(ant: Node, context: Dictionary) -> Dictionary:
	var desired_heading: float = context.get("heading", 0.0)
	var base_speed: float = context.get("base_speed", 100.0)
	
	match move_mode:
		MoveMode.FOLLOW_PHEROMONE:
			desired_heading = _calculate_pheromone_heading(context, true)
		MoveMode.AVOID_PHEROMONE:
			desired_heading = _calculate_pheromone_heading(context, false)
		MoveMode.TOWARD_NEST:
			desired_heading = context.get("nest_direction", desired_heading)
		MoveMode.AWAY_FROM_NEST:
			desired_heading = context.get("nest_direction", desired_heading) + PI
		MoveMode.RANDOM_WALK:
			desired_heading = _calculate_random_heading(context)
		MoveMode.TOWARD_NEAREST_FOOD:
			if context.has("nearest_food_direction"):
				desired_heading = context.get("nearest_food_direction")
			else:
				desired_heading = _calculate_random_heading(context)
		MoveMode.TOWARD_NEAREST_ANT:
			if context.has("nearest_ant_direction"):
				desired_heading = context.get("nearest_ant_direction")
		MoveMode.AWAY_FROM_NEAREST_ANT:
			if context.has("nearest_ant_direction"):
				desired_heading = context.get("nearest_ant_direction") + PI
		MoveMode.WEIGHTED_BLEND:
			desired_heading = _calculate_blended_heading(context)
	
	desired_heading = fmod(desired_heading + TAU, TAU)
	
	var energy_cost: float = base_energy_cost * speed_multiplier
	
	return {
		"success": true,
		"energy_cost": energy_cost,
		"desired_heading": desired_heading,
		"desired_speed": base_speed * speed_multiplier,
	}


func _calculate_pheromone_heading(context: Dictionary, follow: bool) -> float:
	var samples: Dictionary = context.get("pheromone_" + pheromone_name, {})
	var current_heading: float = context.get("heading", 0.0)
	
	if samples.is_empty():
		return _calculate_random_heading(context)
	
	var left: float = samples.get("left", 0.0)
	var center: float = samples.get("center", 0.0)
	var right: float = samples.get("right", 0.0)
	
	if left + center + right < 0.1:
		return _calculate_random_heading(context)
	
	var sensor_angle: float = PI / 6
	var turn_amount: float = 0.0
	
	if follow:
		var total: float = left + center + right
		if total > 0.1:
			var left_weight: float = left / total
			var right_weight: float = right / total
			var diff: float = right_weight - left_weight
			
			turn_amount = diff * sensor_angle * 2.0
			turn_amount += randf_range(-0.05, 0.05)
	else:
		if left > right and left > center:
			turn_amount = sensor_angle * 0.7
		elif right > left and right > center:
			turn_amount = -sensor_angle * 0.7
	
	return current_heading + turn_amount


func _calculate_random_heading(context: Dictionary) -> float:
	var current_heading: float = context.get("heading", 0.0)
	var turn: float = randf_range(-random_turn_rate, random_turn_rate)
	return current_heading + turn + random_bias


func _calculate_blended_heading(context: Dictionary) -> float:
	var current_heading: float = context.get("heading", 0.0)
	var total_weight: float = 0.0
	var weighted_x: float = 0.0
	var weighted_y: float = 0.0
	
	# Get weights - either from settings or from blend_weights
	var weights: Dictionary = blend_weights.duplicate()
	if use_settings_weights:
		var state_name: String = context.get("current_state", "Search")
		var settings_weights: Dictionary = SettingsManager.get_behavior_weights(state_name)
		if not settings_weights.is_empty():
			weights = settings_weights
	
	# Pheromone influence
	var pheromone_w: float = weights.get("pheromone", 0.0)
	if pheromone_w > 0.001:
		var pheromone_heading: float = _calculate_pheromone_heading(context, true)
		var w: float = pheromone_w
		
		# Boost pheromone weight if there's strong signal
		var samples: Dictionary = context.get("pheromone_" + pheromone_name, {})
		var pheromone_total: float = samples.get("total", 0.0)
		if pheromone_total > 1.0:
			w *= minf(pheromone_total / 5.0, 2.5)
		
		weighted_x += cos(pheromone_heading) * w
		weighted_y += sin(pheromone_heading) * w
		total_weight += w
	
	# Random walk influence
	var random_w: float = weights.get("random", 0.0)
	if random_w > 0.001:
		var random_heading: float = _calculate_random_heading(context)
		weighted_x += cos(random_heading) * random_w
		weighted_y += sin(random_heading) * random_w
		total_weight += random_w
	
	# Nest influence (toward or away based on sign)
	var nest_w: float = weights.get("nest", 0.0)
	if absf(nest_w) > 0.001:
		var nest_dir: float = context.get("nest_direction", current_heading)
		weighted_x += cos(nest_dir) * nest_w
		weighted_y += sin(nest_dir) * nest_w
		total_weight += absf(nest_w)
	
	# Food influence
	var food_w: float = weights.get("food", 0.0)
	if food_w > 0.001 and context.has("nearest_food_direction"):
		var food_dir: float = context.get("nearest_food_direction")
		weighted_x += cos(food_dir) * food_w
		weighted_y += sin(food_dir) * food_w
		total_weight += food_w
	
	# Ant direction influence (social navigation)
	var ant_dir_w: float = weights.get("ant_direction", 0.0)
	if ant_dir_w > 0.001:
		var ant_hint_strength: float = context.get("ant_direction_strength", 0.0)
		
		if ant_hint_strength > 0.01:
			var ant_hint_dir: float = context.get("ant_direction_hint", current_heading)
			
			# Scale weight by how strong the signal is
			var effective_w: float = ant_dir_w * ant_hint_strength
			
			weighted_x += cos(ant_hint_dir) * effective_w
			weighted_y += sin(ant_hint_dir) * effective_w
			total_weight += effective_w
	
	# Colony proximity consideration for trail evaluation
	# If we're following a trail, prefer directions that make sense given nest location
	var colony_prox_w: float = weights.get("colony_proximity", 0.0)
	if absf(colony_prox_w) > 0.001:
		# When searching (colony_prox_w negative), prefer paths leading away from nest
		# When returning (colony_prox_w positive), prefer paths leading toward nest
		var nest_dir: float = context.get("nest_direction", current_heading)
		var samples: Dictionary = context.get("pheromone_" + pheromone_name, {})
		var has_trail: bool = samples.get("total", 0.0) > 0.5
		
		if has_trail:
			# We're on a trail - evaluate if it leads toward/away from nest
			# The pheromone heading we calculated
			var trail_heading: float = _calculate_pheromone_heading(context, true)
			
			# How aligned is this trail with nest direction?
			var trail_to_nest_alignment: float = cos(trail_heading - nest_dir)
			
			# If colony_prox_w > 0: boost trails toward nest
			# If colony_prox_w < 0: boost trails away from nest
			var alignment_factor: float = trail_to_nest_alignment * colony_prox_w
			
			# Apply as a modifier to our direction
			if alignment_factor > 0.1:
				# This trail is aligned with our goal, boost it slightly
				weighted_x += cos(trail_heading) * absf(colony_prox_w) * 0.5
				weighted_y += sin(trail_heading) * absf(colony_prox_w) * 0.5
				total_weight += absf(colony_prox_w) * 0.5
	
	if total_weight < 0.001:
		return current_heading
	
	return atan2(weighted_y, weighted_x)


func get_debug_string(_ant: Node, _context: Dictionary) -> String:
	return "Move: %s (%.1fx)" % [MoveMode.keys()[move_mode], speed_multiplier]
