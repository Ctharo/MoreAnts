class_name AntEfficiencyTracker
extends RefCounted
## Tracks efficiency statistics for an individual ant

# Cumulative stats
var total_energy_spent: float = 0.0
var total_distance_traveled: float = 0.0
var total_food_delivered: float = 0.0
var total_pheromone_deposited: float = 0.0
var total_ticks: int = 0

# Time tracking
var lifetime: float = 0.0


## Record energy expenditure
func record_energy(amount: float) -> void:
	total_energy_spent += amount


## Record distance traveled
func record_distance(distance: float) -> void:
	total_distance_traveled += distance
	GameManager.global_stats.total_distance_traveled += distance


## Record food delivered to colony
func record_food_delivered(amount: float) -> void:
	total_food_delivered += amount


## Record pheromone deposited
func record_pheromone(amount: float) -> void:
	total_pheromone_deposited += amount


## Record a tick
func record_tick() -> void:
	total_ticks += 1


## Get efficiency score (food delivered per energy spent)
func get_efficiency() -> float:
	if total_energy_spent < 0.001:
		return 0.0
	return total_food_delivered / total_energy_spent


## Get all statistics
func get_stats() -> Dictionary:
	return {
		"total_energy_spent": total_energy_spent,
		"total_distance_traveled": total_distance_traveled,
		"total_food_delivered": total_food_delivered,
		"total_pheromone_deposited": total_pheromone_deposited,
		"total_ticks": total_ticks,
		"efficiency": get_efficiency(),
		"food_per_distance": total_food_delivered / maxf(total_distance_traveled, 0.001),
		"energy_per_distance": total_energy_spent / maxf(total_distance_traveled, 0.001),
	}


## Reset all statistics
func reset() -> void:
	total_energy_spent = 0.0
	total_distance_traveled = 0.0
	total_food_delivered = 0.0
	total_pheromone_deposited = 0.0
	total_ticks = 0
	lifetime = 0.0
