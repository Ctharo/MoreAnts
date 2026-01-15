class_name DistanceCondition
extends BehaviorCondition
## Condition that checks distance to specific targets

enum TargetType { NEST, NEAREST_FOOD, NEAREST_ANT, NEAREST_ALLY, NEAREST_ENEMY }
enum CompareMode { CLOSER_THAN, FARTHER_THAN, BETWEEN }

## What to measure distance to
@export var target_type: TargetType = TargetType.NEST

## How to compare the distance
@export var compare_mode: CompareMode = CompareMode.CLOSER_THAN

## Distance threshold
@export var threshold: float = 50.0

## Second threshold for BETWEEN mode
@export var threshold_max: float = 100.0


func _init() -> void:
	display_name = "Distance Check"
	evaluation_cost = 0.0


func _evaluate_internal(_ant: Node, context: Dictionary) -> bool:
	var distance: float = INF
	
	match target_type:
		TargetType.NEST:
			distance = context.get("nest_distance", INF)
		TargetType.NEAREST_FOOD:
			distance = context.get("nearest_food_distance", INF)
		TargetType.NEAREST_ANT:
			distance = context.get("nearest_ant_distance", INF)
		TargetType.NEAREST_ALLY:
			# Would need to be tracked separately in ant sensors
			distance = context.get("nearest_ally_distance", INF)
		TargetType.NEAREST_ENEMY:
			distance = context.get("nearest_enemy_distance", INF)
	
	match compare_mode:
		CompareMode.CLOSER_THAN:
			return distance < threshold
		CompareMode.FARTHER_THAN:
			return distance > threshold
		CompareMode.BETWEEN:
			return distance >= threshold and distance <= threshold_max
	
	return false


func get_debug_string() -> String:
	var target_str: String = TargetType.keys()[target_type]
	var mode_str: String = CompareMode.keys()[compare_mode]
	return "Distance to %s: %s %.1f" % [target_str, mode_str, threshold]
