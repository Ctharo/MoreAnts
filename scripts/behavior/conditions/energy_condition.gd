class_name EnergyCondition
extends BehaviorCondition
## Condition that checks the ant's energy level

enum CompareMode { ABOVE_VALUE, BELOW_VALUE, ABOVE_PERCENT, BELOW_PERCENT, BETWEEN_PERCENT }

## How to compare the energy
@export var compare_mode: CompareMode = CompareMode.BELOW_PERCENT

## Threshold value (absolute or percentage depending on mode)
@export var threshold: float = 30.0

## Second threshold for BETWEEN mode
@export var threshold_max: float = 70.0


func _init() -> void:
	display_name = "Energy Check"
	evaluation_cost = 0.0


func _evaluate_internal(_ant: Node, context: Dictionary) -> bool:
	var energy: float = context.get("energy", 0.0)
	var max_energy: float = context.get("max_energy", 100.0)
	var percent: float = (energy / maxf(max_energy, 0.001)) * 100.0
	
	match compare_mode:
		CompareMode.ABOVE_VALUE:
			return energy > threshold
		CompareMode.BELOW_VALUE:
			return energy < threshold
		CompareMode.ABOVE_PERCENT:
			return percent > threshold
		CompareMode.BELOW_PERCENT:
			return percent < threshold
		CompareMode.BETWEEN_PERCENT:
			return percent >= threshold and percent <= threshold_max
	
	return false


func get_debug_string() -> String:
	var mode_str = CompareMode.keys()[compare_mode]
	return "Energy %s %.1f" % [mode_str, threshold]
