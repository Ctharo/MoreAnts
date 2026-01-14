class_name MoveAction
extends BehaviorAction
## Action that controls ant movement and steering

enum MoveMode {
	FOLLOW_PHEROMONE = 0,      # Gradient ascent on pheromone field
	AVOID_PHEROMONE = 1,       # Gradient descent (flee from scent)
	TOWARD_NEST = 2,           # Follow path integrator home
	AWAY_FROM_NEST = 3,        # Explore away from nest
	RANDOM_WALK = 4,           # Correlated random walk
	TOWARD_NEAREST_FOOD = 5,   # Beeline to detected food
	TOWARD_NEAREST_ANT = 6,    # Move toward nearest ant
	AWAY_FROM_NEAREST_ANT = 7, # Flee from nearest ant
	FOLLOW_ANT = 8,            # Follow an ant with food
	WEIGHTED_BLEND = 9,        # Combine multiple influences
}

## Movement mode
@export var move_mode: MoveMode = MoveMode.RANDOM_WALK

## Speed multiplier (0-1)
@export var speed_multiplier: float = 1.0

## Pheromone field to follow (for FOLLOW/AVOID modes)
@export var pheromone_name: String = "food_trail"

## Blend weights for WEIGHTED_BLEND mode
@export var blend_weights: Dictionary = {
	"pheromone": 0.5,
	"random": 0.3,
	"nest": 0.2,
}

## Random walk parameters
@export var random_turn_rate: float = 0.5  # Radians max turn per tick
@export var random_bias: float = 0.0       # Bias direction in radians


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
	
	# Normalize heading
	desired_heading = fmod(desired_heading + TAU, TAU)
	
	var energy_cost = base_energy_cost * speed_multiplier
	
	return {
		"success": true,
		"energy_cost": energy_cost,
		"desired_heading": desired_heading,
		"desired_speed": base_speed * speed_multiplier,
	}


func _calculate_pheromone_heading(context: Dictionary, follow: bool) -> float:
	var samples = context.get("pheromone_" + pheromone_name, {})
	var current_heading: float = context.get("heading", 0.0)
	
	if samples.is_empty():
		return current_heading
	
	var left: float = samples.get("left", 0.0)
	var center: float = samples.get("center", 0.0)
	var right: float = samples.get("right", 0.0)
	
	# If no pheromone detected, random walk
	if left + center + right < 0.001:
		return _calculate_random_heading(context)
	
	# Calculate gradient direction
	var turn_amount: float = 0.0
	var sensor_angle = PI / 6  # 30 degrees
	
	if follow:
		# Turn toward higher concentration
		if left > right and left > center:
			turn_amount = -sensor_angle * 0.5
		elif right > left and right > center:
			turn_amount = sensor_angle * 0.5
	else:
		# Turn away from higher concentration
		if left > right and left > center:
			turn_amount = sensor_angle * 0.5
		elif right > left and right > center:
			turn_amount = -sensor_angle * 0.5
	
	return current_heading + turn_amount


func _calculate_random_heading(context: Dictionary) -> float:
	var current_heading: float = context.get("heading", 0.0)
	var turn = randf_range(-random_turn_rate, random_turn_rate)
	return current_heading + turn + random_bias


func _calculate_blended_heading(context: Dictionary) -> float:
	var current_heading: float = context.get("heading", 0.0)
	var total_weight: float = 0.0
	var weighted_x: float = 0.0
	var weighted_y: float = 0.0
	
	# Pheromone influence
	if blend_weights.has("pheromone") and blend_weights.pheromone > 0:
		var pheromone_heading = _calculate_pheromone_heading(context, true)
		var w = blend_weights.pheromone
		weighted_x += cos(pheromone_heading) * w
		weighted_y += sin(pheromone_heading) * w
		total_weight += w
	
	# Random walk influence
	if blend_weights.has("random") and blend_weights.random > 0:
		var random_heading = _calculate_random_heading(context)
		var w = blend_weights.random
		weighted_x += cos(random_heading) * w
		weighted_y += sin(random_heading) * w
		total_weight += w
	
	# Nest influence (toward or away)
	if blend_weights.has("nest") and blend_weights.nest > 0:
		var nest_dir = context.get("nest_direction", current_heading)
		var w = blend_weights.nest
		weighted_x += cos(nest_dir) * w
		weighted_y += sin(nest_dir) * w
		total_weight += w
	
	# Food influence
	if blend_weights.has("food") and blend_weights.food > 0:
		if context.has("nearest_food_direction"):
			var food_dir = context.get("nearest_food_direction")
			var w = blend_weights.food
			weighted_x += cos(food_dir) * w
			weighted_y += sin(food_dir) * w
			total_weight += w
	
	if total_weight < 0.001:
		return current_heading
	
	return atan2(weighted_y, weighted_x)


func get_debug_string(_ant: Node, _context: Dictionary) -> String:
	return "Move: %s (%.1fx)" % [MoveMode.keys()[move_mode], speed_multiplier]
