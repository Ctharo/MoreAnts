extends Node
## CostTracker - Global singleton for detailed action cost tracking and efficiency analysis
## Allows users to see exactly what behaviors are costing and optimize their ant programs

signal cost_updated(category: String, action: String, cost: float)
signal efficiency_report_generated(report: Dictionary)

## Detailed cost breakdown by category
var costs_by_category: Dictionary = {
	"movement": {},
	"sensing": {},
	"pheromone": {},
	"interaction": {},
	"metabolism": {},
}

## Per-behavior-program tracking
var behavior_costs: Dictionary = {}  # program_name -> CostReport

## Time series data for graphing
var cost_history: Array[Dictionary] = []
var history_interval: float = 1.0  # Seconds between samples
var max_history_size: int = 300    # 5 minutes of data at 1s intervals

## Current tick aggregation
var _current_tick_costs: Dictionary = {}
var _history_timer: float = 0.0


class CostReport:
	var program_name: String
	var total_cost: float = 0.0
	var total_ticks: int = 0
	var food_collected: float = 0.0
	var costs_by_action: Dictionary = {}
	var costs_by_state: Dictionary = {}
	
	func record_cost(action_name: String, state_name: String, cost: float) -> void:
		total_cost += cost
		
		if not costs_by_action.has(action_name):
			costs_by_action[action_name] = {"total": 0.0, "count": 0}
		costs_by_action[action_name].total += cost
		costs_by_action[action_name].count += 1
		
		if not costs_by_state.has(state_name):
			costs_by_state[state_name] = {"total": 0.0, "ticks": 0}
		costs_by_state[state_name].total += cost
		costs_by_state[state_name].ticks += 1
	
	func get_efficiency() -> float:
		if total_cost < 0.001:
			return 0.0
		return (food_collected / total_cost) * 100.0
	
	func get_cost_per_tick() -> float:
		if total_ticks == 0:
			return 0.0
		return total_cost / total_ticks
	
	func get_top_costs(n: int = 5) -> Array:
		var sorted_actions: Array = []
		for action_name in costs_by_action:
			sorted_actions.append({
				"name": action_name,
				"total": costs_by_action[action_name].total,
				"count": costs_by_action[action_name].count,
				"avg": costs_by_action[action_name].total / max(costs_by_action[action_name].count, 1)
			})
		sorted_actions.sort_custom(func(a, b): return a.total > b.total)
		return sorted_actions.slice(0, n)
	
	func to_dict() -> Dictionary:
		return {
			"program_name": program_name,
			"total_cost": total_cost,
			"total_ticks": total_ticks,
			"food_collected": food_collected,
			"efficiency": get_efficiency(),
			"cost_per_tick": get_cost_per_tick(),
			"top_costs": get_top_costs(),
			"costs_by_state": costs_by_state.duplicate(),
		}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return
	
	_history_timer += delta * GameManager.time_scale
	
	# Record history sample
	if _history_timer >= history_interval:
		_history_timer = 0.0
		_record_history_sample()


## Record a cost for tracking
func record_cost(category: String, action_name: String, cost: float, 
				  program_name: String = "", state_name: String = "") -> void:
	# Category tracking
	if not costs_by_category.has(category):
		costs_by_category[category] = {}
	
	if not costs_by_category[category].has(action_name):
		costs_by_category[category][action_name] = {
			"total_cost": 0.0,
			"call_count": 0,
			"min_cost": INF,
			"max_cost": 0.0,
		}
	
	var entry = costs_by_category[category][action_name]
	entry.total_cost += cost
	entry.call_count += 1
	entry.min_cost = minf(entry.min_cost, cost)
	entry.max_cost = maxf(entry.max_cost, cost)
	
	# Per-tick aggregation
	var key = category + "/" + action_name
	if not _current_tick_costs.has(key):
		_current_tick_costs[key] = 0.0
	_current_tick_costs[key] += cost
	
	# Behavior program tracking
	if not program_name.is_empty():
		if not behavior_costs.has(program_name):
			behavior_costs[program_name] = CostReport.new()
			behavior_costs[program_name].program_name = program_name
		behavior_costs[program_name].record_cost(action_name, state_name, cost)
	
	cost_updated.emit(category, action_name, cost)


## Record food collected for a behavior program
func record_food(program_name: String, amount: float) -> void:
	if behavior_costs.has(program_name):
		behavior_costs[program_name].food_collected += amount


## Record a tick for a behavior program
func record_tick(program_name: String) -> void:
	if behavior_costs.has(program_name):
		behavior_costs[program_name].total_ticks += 1


## Get summary statistics for a category
func get_category_stats(category: String) -> Dictionary:
	if not costs_by_category.has(category):
		return {}
	
	var stats = costs_by_category[category]
	var total_cost: float = 0.0
	var total_calls: int = 0
	
	for action_name in stats:
		total_cost += stats[action_name].total_cost
		total_calls += stats[action_name].call_count
	
	return {
		"total_cost": total_cost,
		"total_calls": total_calls,
		"avg_cost_per_call": total_cost / maxf(total_calls, 1),
		"actions": stats.duplicate(),
	}


## Get overall efficiency report
func get_efficiency_report() -> Dictionary:
	var report: Dictionary = {
		"timestamp": GameManager.simulation_time,
		"categories": {},
		"behaviors": {},
		"total_energy": GameManager.global_stats.total_energy_spent,
		"total_food": GameManager.global_stats.total_food_collected,
		"global_efficiency": GameManager.get_efficiency_ratio() * 100.0,
	}
	
	# Category breakdown
	var category_totals: Array[Dictionary] = []
	for category in costs_by_category:
		var stats = get_category_stats(category)
		report.categories[category] = stats
		category_totals.append({
			"name": category,
			"cost": stats.get("total_cost", 0.0),
		})
	
	# Sort categories by cost
	category_totals.sort_custom(func(a, b): return a.cost > b.cost)
	report["category_ranking"] = category_totals
	
	# Behavior breakdown
	for program_name in behavior_costs:
		report.behaviors[program_name] = behavior_costs[program_name].to_dict()
	
	efficiency_report_generated.emit(report)
	return report


## Get cost breakdown for display
func get_cost_breakdown() -> Array[Dictionary]:
	var breakdown: Array[Dictionary] = []
	
	for category in costs_by_category:
		var cat_stats = costs_by_category[category]
		for action_name in cat_stats:
			var stats = cat_stats[action_name]
			breakdown.append({
				"category": category,
				"action": action_name,
				"total_cost": stats.total_cost,
				"call_count": stats.call_count,
				"avg_cost": stats.total_cost / maxf(stats.call_count, 1),
				"min_cost": stats.min_cost if stats.min_cost != INF else 0.0,
				"max_cost": stats.max_cost,
			})
	
	# Sort by total cost descending
	breakdown.sort_custom(func(a, b): return a.total_cost > b.total_cost)
	return breakdown


## Get time series data for graphing
func get_history() -> Array[Dictionary]:
	return cost_history


func _record_history_sample() -> void:
	var sample: Dictionary = {
		"time": GameManager.simulation_time,
		"total_energy": GameManager.global_stats.total_energy_spent,
		"total_food": GameManager.global_stats.total_food_collected,
		"efficiency": GameManager.get_efficiency_ratio(),
		"ant_count": 0,
		"tick_costs": _current_tick_costs.duplicate(),
	}
	
	# Count ants
	for colony in GameManager.colonies:
		if colony != null:
			sample.ant_count += colony.ants.size()
	
	cost_history.append(sample)
	
	# Trim history if too large
	while cost_history.size() > max_history_size:
		cost_history.pop_front()
	
	# Reset tick costs
	_current_tick_costs.clear()


## Reset all tracking data
func reset() -> void:
	for category in costs_by_category:
		costs_by_category[category].clear()
	behavior_costs.clear()
	cost_history.clear()
	_current_tick_costs.clear()
	_history_timer = 0.0


## Get action cost comparison (shows which actions are most expensive)
func get_action_cost_comparison() -> Array[Dictionary]:
	var all_actions: Array[Dictionary] = []
	
	for category in costs_by_category:
		for action_name in costs_by_category[category]:
			var stats = costs_by_category[category][action_name]
			all_actions.append({
				"category": category,
				"action": action_name,
				"total": stats.total_cost,
				"count": stats.call_count,
				"avg": stats.total_cost / maxf(stats.call_count, 1),
				"percent": 0.0,  # Filled in below
			})
	
	# Calculate percentages
	var grand_total = GameManager.global_stats.total_energy_spent
	if grand_total > 0:
		for item in all_actions:
			item.percent = (item.total / grand_total) * 100.0
	
	all_actions.sort_custom(func(a, b): return a.total > b.total)
	return all_actions
