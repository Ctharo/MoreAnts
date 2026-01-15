class_name PheromoneAction
extends BehaviorAction
## Action that deposits pheromones into the environment

enum DepositMode {
	CONSTANT = 0,              ## Always deposit same amount
	PROPORTIONAL_TO_FOOD = 1,  ## More if carrying more food
	INVERSELY_TO_DISTANCE = 3, ## More when closer to target
	PULSE = 4,                 ## Deposit in bursts
}

## Name of the pheromone field to deposit into
@export var pheromone_name: String = "food_trail"

## How to determine deposit amount
@export var deposit_mode: DepositMode = DepositMode.CONSTANT

## Base deposit amount
@export var base_amount: float = 1.0

## Maximum deposit amount (for scaled modes)
@export var max_amount: float = 5.0

## Reference distance for INVERSELY_TO_DISTANCE mode
@export var reference_distance: float = 300.0

## Whether to spread deposit across multiple cells
@export var use_spread: bool = false

## Spread radius in cells
@export var spread_radius: int = 1

## Pulse interval in ticks (for PULSE mode)
@export var pulse_interval: int = 5

# Pulse tracking
var _pulse_counter: int = 0


func _init() -> void:
	display_name = "Deposit Pheromone"
	base_energy_cost = 0.5


func _get_cost_category() -> String:
	return "pheromone"


func _execute_internal(_ant: Node, context: Dictionary) -> Dictionary:
	var amount: float = base_amount
	
	match deposit_mode:
		DepositMode.CONSTANT:
			amount = base_amount
		DepositMode.PROPORTIONAL_TO_FOOD:
			var carried: float = context.get("carried_weight", 0.0)
			if carried > 0:
				amount = base_amount + (carried * 0.5)
			else:
				amount = base_amount * 0.5
		DepositMode.INVERSELY_TO_DISTANCE:
			var nest_dist: float = context.get("nest_distance", reference_distance)
			# More pheromone FURTHER from nest (where food was found)
			var factor: float = clampf(nest_dist / reference_distance, 0.0, 1.0)
			amount = base_amount + (max_amount - base_amount) * factor
		DepositMode.PULSE:
			_pulse_counter += 1
			if _pulse_counter < pulse_interval:
				return {"success": true, "energy_cost": 0.0}
			_pulse_counter = 0
			amount = max_amount
	
	amount = clampf(amount, 0.0, max_amount)
	
	# Energy cost scales with amount
	var energy_cost: float = base_energy_cost * (amount / base_amount)
	
	return {
		"success": true,
		"energy_cost": energy_cost,
		"deposit_pheromone": pheromone_name,
		"deposit_amount": amount,
		"use_spread": use_spread,
		"spread_radius": spread_radius,
	}


func get_debug_string(_ant: Node, _context: Dictionary) -> String:
	return "Deposit %s: %.1f" % [pheromone_name, base_amount]
