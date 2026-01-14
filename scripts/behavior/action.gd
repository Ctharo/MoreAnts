@icon("res://icons/action.svg")
class_name BehaviorAction
extends Resource
## Base class for all behavior actions
## Actions modify the ant's state or environment

## Human-readable name for UI display
@export var display_name: String = "Action"

## Description of what this action does
@export_multiline var description: String = ""

## Base energy cost to execute this action
@export var base_energy_cost: float = 0.0

## Priority when multiple actions compete (higher = more important)
@export var priority: int = 0


## Execute the action for a given ant
## Returns Dictionary with results: {success: bool, energy_cost: float, ...}
func execute(ant: Node, context: Dictionary) -> Dictionary:
	var result = _execute_internal(ant, context)
	
	# Ensure required fields exist
	if not result.has("success"):
		result["success"] = false
	if not result.has("energy_cost"):
		result["energy_cost"] = base_energy_cost
	
	# Add cost category for tracking (ant will handle actual tracking)
	result["cost_category"] = _get_cost_category()
	result["action_name"] = display_name
	
	return result


## Get the cost category for this action (override in subclasses)
func _get_cost_category() -> String:
	return "interaction"


## Internal execution - override this in subclasses
func _execute_internal(_ant: Node, _context: Dictionary) -> Dictionary:
	push_warning("BehaviorAction._execute_internal() not implemented")
	return {"success": false, "energy_cost": 0.0}


## Get a preview of what this action would cost without executing
func get_cost_estimate(_ant: Node, _context: Dictionary) -> float:
	return base_energy_cost


## Get a string description of the action for debugging
func get_debug_string(_ant: Node, _context: Dictionary) -> String:
	return display_name
