class_name CarryingCondition
extends BehaviorCondition
## Condition that checks what the ant is carrying

enum CarryMode { CARRYING_ANYTHING, CARRYING_NOTHING, CARRYING_FOOD, CARRYING_SPECIFIC }

## What carrying state to check for
@export var carry_mode: CarryMode = CarryMode.CARRYING_ANYTHING

## Specific item type to check (for CARRYING_SPECIFIC mode)
@export var specific_type: String = ""


func _init() -> void:
	display_name = "Carrying Check"
	evaluation_cost = 0.0


func _evaluate_internal(_ant: Node, context: Dictionary) -> bool:
	var carried: Variant = context.get("carried_item", null)
	var carried_type: String = context.get("carried_type", "")
	
	match carry_mode:
		CarryMode.CARRYING_ANYTHING:
			return carried != null
		CarryMode.CARRYING_NOTHING:
			return carried == null
		CarryMode.CARRYING_FOOD:
			return carried != null and (carried_type == "food" or carried_type == "")
		CarryMode.CARRYING_SPECIFIC:
			return carried != null and carried_type == specific_type
	
	return false


func get_debug_string() -> String:
	return "Carrying: %s" % CarryMode.keys()[carry_mode]
