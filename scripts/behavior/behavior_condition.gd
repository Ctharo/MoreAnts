@icon("res://icons/condition.svg")
class_name BehaviorCondition
extends Resource
## Base class for all behavior conditions
## Conditions evaluate ant/environment state and return true/false

## Human-readable name for UI display
@export var display_name: String = "Condition"

## Description of what this condition checks
@export_multiline var description: String = ""

## Energy cost to evaluate this condition (sensing cost)
@export var evaluation_cost: float = 0.0

## Whether to invert the result
@export var invert: bool = false


## Evaluate the condition for a given ant
## Returns true if the condition is met
func evaluate(ant: Node, context: Dictionary) -> bool:
	var result = _evaluate_internal(ant, context)
	
	if invert:
		result = not result
	
	return result


## Internal evaluation - override this in subclasses
func _evaluate_internal(_ant: Node, _context: Dictionary) -> bool:
	push_warning("BehaviorCondition._evaluate_internal() not implemented")
	return false


## Get the energy cost of evaluating this condition
func get_evaluation_cost() -> float:
	return evaluation_cost


## Get a string description for debugging
func get_debug_string() -> String:
	var base = display_name
	if invert:
		base = "NOT " + base
	return base
