class_name DropAction
extends BehaviorAction
## Action that drops carried items

enum DropMode {
	DROP_HERE = 0,      ## Drop at current position
	DROP_AT_NEST = 1,   ## Only drop when at nest (delivers food)
	DROP_AT_TARGET = 2, ## Drop at specific location
}

## How/where to drop items
@export var drop_mode: DropMode = DropMode.DROP_HERE

## Distance threshold for nest delivery
@export var nest_threshold: float = 50.0


func _init() -> void:
	display_name = "Drop"
	base_energy_cost = 0.0


func _get_cost_category() -> String:
	return "interaction"


func _execute_internal(ant: Node, context: Dictionary) -> Dictionary:
	# Can't drop if not carrying
	if context.get("carried_item", null) == null:
		return {"success": false, "energy_cost": 0.0}
	
	var should_drop: bool = false
	var is_delivery: bool = false
	
	match drop_mode:
		DropMode.DROP_HERE:
			should_drop = true
		DropMode.DROP_AT_NEST:
			var nest_dist: float = context.get("nest_distance", INF)
			if nest_dist <= nest_threshold:
				should_drop = true
				is_delivery = true
				# Stop the ant when dropping at nest
				if ant.has_method("stop_movement"):
					ant.stop_movement()
		DropMode.DROP_AT_TARGET:
			# Would need target position tracking
			should_drop = true
	
	if not should_drop:
		return {"success": false, "energy_cost": 0.0}
	
	return {
		"success": true,
		"energy_cost": base_energy_cost,
		"drop_item": true,
		"is_delivery": is_delivery,
	}


func get_debug_string(_ant: Node, _context: Dictionary) -> String:
	return "Drop: %s" % DropMode.keys()[drop_mode]
