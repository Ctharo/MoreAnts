@icon("res://icons/behavior.svg")
class_name BehaviorProgram
extends Resource
## A complete behavior program (state machine) for an ant
## This is the main resource users will create and edit

## Human-readable name of this behavior program
@export var program_name: String = "Unnamed Behavior"

## Description of what this behavior does
@export_multiline var description: String = ""

## Author name (for sharing)
@export var author: String = ""

## Version number
@export var version: String = "1.0"

## All states in this program
@export var states: Array[BehaviorState] = []

## Name of the initial state when ant spawns
@export var initial_state: String = ""

## Global actions that run every tick regardless of state
@export var global_actions: Array[BehaviorAction] = []

# Statistics
var total_transitions: int = 0
var total_energy_spent: float = 0.0
var total_ticks: int = 0
var food_collected: float = 0.0

# State lookup cache
var _state_cache: Dictionary = {}


func _init() -> void:
	_rebuild_cache()


## Rebuild the state lookup cache
func _rebuild_cache() -> void:
	_state_cache.clear()
	for state in states:
		if state != null:
			_state_cache[state.state_name] = state


## Get a state by name
func get_state(state_name: String) -> BehaviorState:
	if _state_cache.is_empty():
		_rebuild_cache()
	return _state_cache.get(state_name, null)


## Get the initial state
func get_initial_state() -> BehaviorState:
	if initial_state.is_empty() and states.size() > 0:
		return states[0]
	return get_state(initial_state)


## Process a single decision tick for an ant
## Returns: Dictionary with results and potential state change
func process_tick(ant: Node, context: Dictionary, current_state_name: String) -> Dictionary:
	total_ticks += 1
	
	var result: Dictionary = {
		"energy_cost": 0.0,
		"new_state": "",
		"action_results": [],
	}
	
	# Execute global actions first
	for action in global_actions:
		if action != null:
			var action_result = action.execute(ant, context)
			result.action_results.append(action_result)
			result.energy_cost += action_result.get("energy_cost", 0.0)
	
	# Get current state
	var current_state = get_state(current_state_name)
	if current_state == null:
		current_state = get_initial_state()
		if current_state == null:
			push_error("BehaviorProgram has no states!")
			return result
		result.new_state = current_state.state_name
	
	# Execute state tick
	var tick_result = current_state.tick(ant, context)
	result.action_results.append_array(tick_result.get("action_results", []))
	result.energy_cost += tick_result.get("energy_cost", 0.0)
	
	# Check transitions
	var next_state_name = current_state.check_transitions(ant, context)
	if not next_state_name.is_empty() and next_state_name != current_state_name:
		var next_state = get_state(next_state_name)
		if next_state != null:
			# Exit current state
			var exit_result = current_state.exit(ant, context)
			result.energy_cost += exit_result.get("energy_cost", 0.0)
			
			# Enter new state
			var enter_result = next_state.enter(ant, context)
			result.energy_cost += enter_result.get("energy_cost", 0.0)
			
			result.new_state = next_state_name
			total_transitions += 1
	
	total_energy_spent += result.energy_cost
	
	return result


## Handle state entry (called when ant first uses this program or respawns)
func enter_initial_state(ant: Node, context: Dictionary) -> Dictionary:
	var initial = get_initial_state()
	if initial == null:
		return {"energy_cost": 0.0, "state": ""}
	
	var result = initial.enter(ant, context)
	return {
		"energy_cost": result.get("energy_cost", 0.0),
		"state": initial.state_name,
	}


## Get overall efficiency statistics
func get_efficiency_report() -> Dictionary:
	var state_stats: Array[Dictionary] = []
	for state in states:
		if state != null:
			state_stats.append(state.get_efficiency_stats())
	
	var avg_energy_per_tick = total_energy_spent / max(total_ticks, 1)
	var food_per_energy = food_collected / max(total_energy_spent, 0.001)
	
	return {
		"program_name": program_name,
		"total_ticks": total_ticks,
		"total_transitions": total_transitions,
		"total_energy_spent": total_energy_spent,
		"food_collected": food_collected,
		"avg_energy_per_tick": avg_energy_per_tick,
		"food_per_energy": food_per_energy,
		"efficiency_score": food_per_energy * 100.0,  # Higher is better
		"state_stats": state_stats,
	}


## Reset all statistics
func reset_stats() -> void:
	total_transitions = 0
	total_energy_spent = 0.0
	total_ticks = 0
	food_collected = 0.0
	
	for state in states:
		if state != null:
			state.reset_stats()


## Add food collected (called by colony when ant delivers)
func record_food_collected(amount: float) -> void:
	food_collected += amount


## Validate the program structure
func validate() -> Array[String]:
	var errors: Array[String] = []
	
	if states.is_empty():
		errors.append("Program has no states")
		return errors
	
	# Check initial state exists
	if not initial_state.is_empty():
		if get_state(initial_state) == null:
			errors.append("Initial state '%s' not found" % initial_state)
	
	# Check all transition targets exist
	for state in states:
		if state == null:
			continue
		for transition in state.transitions:
			if transition == null:
				continue
			if get_state(transition.target_state) == null:
				errors.append("State '%s' has transition to unknown state '%s'" % 
					[state.state_name, transition.target_state])
	
	# Check for unreachable states
	var reachable: Dictionary = {}
	var to_check: Array[String] = []
	
	var init = get_initial_state()
	if init != null:
		to_check.append(init.state_name)
	
	while not to_check.is_empty():
		var current_name = to_check.pop_back()
		if reachable.has(current_name):
			continue
		reachable[current_name] = true
		
		var state = get_state(current_name)
		if state != null:
			for transition in state.transitions:
				if transition != null and not reachable.has(transition.target_state):
					to_check.append(transition.target_state)
	
	for state in states:
		if state != null and not reachable.has(state.state_name):
			errors.append("State '%s' is unreachable" % state.state_name)
	
	return errors
