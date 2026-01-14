@icon("res://icons/transition.svg")
class_name BehaviorTransition
extends Resource
## A conditional transition between behavior states
## Evaluated each tick to determine if state should change

## Target state name to transition to
@export var target_state: String = ""

## Condition that must be true for transition to fire
@export var condition: BehaviorCondition = null

## Higher priority transitions are checked first
@export var priority: int = 0

## Ticks to wait before this transition can fire again
@export var cooldown_ticks: int = 0

## Human-readable description
@export_multiline var description: String = ""


## Evaluate whether this transition should fire
func evaluate(ant: Node, context: Dictionary) -> bool:
	if condition == null:
		# No condition means always true (unconditional transition)
		return true
	
	return condition.evaluate(ant, context)


## Get a debug description of this transition
func get_debug_string() -> String:
	var cond_str = "always" if condition == null else condition.get_debug_string()
	return "-> %s (if %s, priority %d)" % [target_state, cond_str, priority]
