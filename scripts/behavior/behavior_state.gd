@icon("res://icons/state.svg")
class_name BehaviorState
extends Resource
## A single state in a behavior program
## Contains actions to execute and transitions to other states

## Unique name for this state (used for transitions)
@export var state_name: String = "Unnamed"

## Human-readable description
@export_multiline var description: String = ""

## Color for visualization/debugging
@export var display_color: Color = Color.WHITE

## Actions executed once when entering this state
@export var entry_actions: Array[BehaviorAction] = []

## Actions executed every tick while in this state
@export var tick_actions: Array[BehaviorAction] = []

## Actions executed once when leaving this state
@export var exit_actions: Array[BehaviorAction] = []

## Transitions to other states (checked in priority order)
@export var transitions: Array[BehaviorTransition] = []

# Statistics
var total_ticks: int = 0
var total_energy: float = 0.0
var entry_count: int = 0
var total_time_in_state: float = 0.0

# Transition cooldown tracking
var _transition_cooldowns: Dictionary = {}  # transition index -> remaining ticks


## Called when entering this state
func enter(ant: Node, context: Dictionary) -> Dictionary:
	entry_count += 1
	
	var result: Dictionary = {
		"energy_cost": 0.0,
		"action_results": [],
	}
	
	# Execute entry actions
	for action in entry_actions:
		if action != null:
			var action_result = action.execute(ant, context)
			result.action_results.append(action_result)
			result.energy_cost += action_result.get("energy_cost", 0.0)
	
	# Reset transition cooldowns
	_transition_cooldowns.clear()
	
	total_energy += result.energy_cost
	return result


## Called every decision tick while in this state
func tick(ant: Node, context: Dictionary) -> Dictionary:
	total_ticks += 1
	
	var result: Dictionary = {
		"energy_cost": 0.0,
		"action_results": [],
	}
	
	# Execute tick actions
	for action in tick_actions:
		if action != null:
			var action_result = action.execute(ant, context)
			result.action_results.append(action_result)
			result.energy_cost += action_result.get("energy_cost", 0.0)
	
	# Decrement transition cooldowns
	for key in _transition_cooldowns.keys():
		_transition_cooldowns[key] -= 1
		if _transition_cooldowns[key] <= 0:
			_transition_cooldowns.erase(key)
	
	total_energy += result.energy_cost
	return result


## Called when leaving this state
func exit(ant: Node, context: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"energy_cost": 0.0,
		"action_results": [],
	}
	
	# Execute exit actions
	for action in exit_actions:
		if action != null:
			var action_result = action.execute(ant, context)
			result.action_results.append(action_result)
			result.energy_cost += action_result.get("energy_cost", 0.0)
	
	total_energy += result.energy_cost
	return result


## Check all transitions and return the target state name if one fires
## Returns empty string if no transition fires
func check_transitions(ant: Node, context: Dictionary) -> String:
	# Sort transitions by priority (higher first)
	var sorted_transitions: Array = []
	for i in range(transitions.size()):
		if transitions[i] != null:
			sorted_transitions.append({"index": i, "transition": transitions[i]})
	
	sorted_transitions.sort_custom(func(a, b): 
		return a.transition.priority > b.transition.priority
	)
	
	# Check each transition
	for item in sorted_transitions:
		var idx = item.index
		var transition: BehaviorTransition = item.transition
		
		# Skip if on cooldown
		if _transition_cooldowns.has(idx):
			continue
		
		# Evaluate condition
		if transition.evaluate(ant, context):
			# Apply cooldown if specified
			if transition.cooldown_ticks > 0:
				_transition_cooldowns[idx] = transition.cooldown_ticks
			
			return transition.target_state
	
	return ""


## Get efficiency statistics for this state
func get_efficiency_stats() -> Dictionary:
	var avg_energy_per_tick = total_energy / maxf(total_ticks, 1)
	
	return {
		"state_name": state_name,
		"total_ticks": total_ticks,
		"total_energy": total_energy,
		"entry_count": entry_count,
		"avg_energy_per_tick": avg_energy_per_tick,
		"avg_ticks_per_visit": float(total_ticks) / maxf(entry_count, 1),
	}


## Reset all statistics
func reset_stats() -> void:
	total_ticks = 0
	total_energy = 0.0
	entry_count = 0
	total_time_in_state = 0.0
	_transition_cooldowns.clear()


## Get debug information
func get_debug_info() -> String:
	return "%s: %d ticks, %.2f energy" % [state_name, total_ticks, total_energy]
