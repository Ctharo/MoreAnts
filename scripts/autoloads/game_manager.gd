extends Node
## GameManager - Global simulation controller autoload
## Manages time, cohorts, and global statistics

signal simulation_started
signal simulation_paused
signal simulation_reset

# Simulation state
var is_running: bool = false
var simulation_time: float = 0.0
var time_scale: float = 1.0

# Decision tick configuration
var decision_tick_rate: float = 10.0  # Hz
var cohort_count: int = 10  # Spread decisions across this many frames
var _current_cohort: int = 0
var _tick_accumulator: float = 0.0

# References
var world: Node = null
var colonies: Array = []

# Action costs (energy per unit)
var action_costs: Dictionary = {
	"idle": 0.01,           # Base metabolism per tick
	"move_base": 0.001,     # Per unit distance
	"move_carrying": 0.002, # Per unit distance while carrying
	"turn": 0.0005,         # Per radian turned
	"sense": 0.01,          # Per sensor query
	"deposit": 0.5,         # Per pheromone unit deposited
	"pickup": 1.0,          # Flat cost to pick up
	"drop": 0.2,            # Flat cost to drop
}

# Global statistics
var global_stats: Dictionary = {
	"total_food_collected": 0.0,
	"total_energy_spent": 0.0,
	"total_distance_traveled": 0.0,
	"total_pheromone_deposited": 0.0,
	"ants_spawned": 0,
	"ants_starved": 0,
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not is_running:
		return
	
	var scaled_delta = delta * time_scale
	simulation_time += scaled_delta
	
	# Decision tick management
	_tick_accumulator += scaled_delta
	var tick_interval = 1.0 / decision_tick_rate
	
	while _tick_accumulator >= tick_interval:
		_tick_accumulator -= tick_interval
		_process_decision_tick()


func _process_decision_tick() -> void:
	_current_cohort = (_current_cohort + 1) % cohort_count
	
	# Trigger decision tick for ants in current cohort
	for colony in colonies:
		if colony == null or not is_instance_valid(colony):
			continue
		for ant in colony.ants:
			if ant != null and is_instance_valid(ant):
				ant.decision_tick()


## Check if an ant index belongs to the current decision cohort
func is_ant_cohort(ant_index: int) -> bool:
	return (ant_index % cohort_count) == _current_cohort


## Start or resume simulation
func start_simulation() -> void:
	is_running = true
	simulation_started.emit()


## Pause simulation
func pause_simulation() -> void:
	is_running = false
	simulation_paused.emit()


## Toggle simulation state
func toggle_simulation() -> void:
	if is_running:
		pause_simulation()
	else:
		start_simulation()


## Set time scale (1.0 = normal, 2.0 = 2x speed, etc)
func set_time_scale(scale: float) -> void:
	time_scale = clampf(scale, 0.01, 100.0)


## Get an action cost
func get_action_cost(action_name: String) -> float:
	return action_costs.get(action_name, 0.0)


## Set an action cost
func set_action_cost(action_name: String, cost: float) -> void:
	action_costs[action_name] = cost


## Register a colony
func register_colony(colony: Node) -> void:
	if colony not in colonies:
		colonies.append(colony)


## Get global efficiency ratio (food per energy)
func get_efficiency_ratio() -> float:
	if global_stats.total_energy_spent < 0.001:
		return 0.0
	return global_stats.total_food_collected / global_stats.total_energy_spent


## Reset simulation
func reset_simulation() -> void:
	is_running = false
	simulation_time = 0.0
	_current_cohort = 0
	_tick_accumulator = 0.0
	
	global_stats = {
		"total_food_collected": 0.0,
		"total_energy_spent": 0.0,
		"total_distance_traveled": 0.0,
		"total_pheromone_deposited": 0.0,
		"ants_spawned": 0,
		"ants_starved": 0,
	}
	
	colonies.clear()
	simulation_reset.emit()


## Get formatted statistics string
func get_stats_string() -> String:
	return """
Simulation Time: %.1fs
Food Collected: %.1f
Energy Spent: %.1f
Efficiency: %.4f food/energy
Ants: %d spawned, %d starved
""" % [
		simulation_time,
		global_stats.total_food_collected,
		global_stats.total_energy_spent,
		get_efficiency_ratio(),
		global_stats.ants_spawned,
		global_stats.ants_starved,
	]
