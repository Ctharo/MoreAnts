class_name PickupAction
extends BehaviorAction
## Action that picks up items from the environment

enum PickupTarget {
	NEAREST_FOOD = 0,
	NEAREST_ITEM = 1,
	SPECIFIC_TYPE = 2,
}

## What to try to pick up
@export var pickup_target: PickupTarget = PickupTarget.NEAREST_FOOD

## Range within which pickup is possible
@export var pickup_range: float = 20.0

## Specific item type (for SPECIFIC_TYPE mode)
@export var specific_type: String = ""


func _init() -> void:
	display_name = "Pickup"
	base_energy_cost = 1.0


func _get_cost_category() -> String:
	return "interaction"


func _execute_internal(_ant: Node, context: Dictionary) -> Dictionary:
	# Can't pick up if already carrying
	if context.get("carried_item", null) != null:
		return {"success": false, "energy_cost": 0.0}
	
	var target: Node = null
	
	match pickup_target:
		PickupTarget.NEAREST_FOOD:
			var dist: float = context.get("nearest_food_distance", INF)
			if dist <= pickup_range:
				target = context.get("nearest_food", null)
		PickupTarget.NEAREST_ITEM:
			# Would need more general item tracking
			var dist: float = context.get("nearest_food_distance", INF)
			if dist <= pickup_range:
				target = context.get("nearest_food", null)
		PickupTarget.SPECIFIC_TYPE:
			# Would need item type checking
			pass
	
	if target == null:
		return {"success": false, "energy_cost": base_energy_cost * 0.1}
	
	return {
		"success": true,
		"energy_cost": base_energy_cost,
		"pickup_target": target,
	}


func get_debug_string(_ant: Node, _context: Dictionary) -> String:
	return "Pickup: %s (range %.1f)" % [PickupTarget.keys()[pickup_target], pickup_range]
