class_name NearbyCondition
extends BehaviorCondition
## Condition that checks for nearby entities

enum EntityType { FOOD, ANT, ALLY, ENEMY, ANY }
enum CountMode { ANY, NONE, AT_LEAST, AT_MOST, EXACTLY }

## Type of entity to look for
@export var entity_type: EntityType = EntityType.FOOD

## How to evaluate the count
@export var count_mode: CountMode = CountMode.ANY

## Search radius
@export var search_radius: float = 50.0

## Count threshold (for AT_LEAST, AT_MOST, EXACTLY modes)
@export var count_threshold: int = 1


func _init() -> void:
	display_name = "Nearby Check"
	evaluation_cost = 0.05


func _evaluate_internal(_ant: Node, context: Dictionary) -> bool:
	var count: int = 0
	
	match entity_type:
		EntityType.FOOD:
			count = context.get("nearby_food_count", 0)
		EntityType.ANT:
			count = context.get("nearby_ants_count", 0)
		EntityType.ALLY:
			count = context.get("nearby_allies_count", 0)
		EntityType.ENEMY:
			count = context.get("nearby_enemies_count", 0)
		EntityType.ANY:
			count = context.get("nearby_food_count", 0) + context.get("nearby_ants_count", 0)
	
	match count_mode:
		CountMode.ANY:
			return count > 0
		CountMode.NONE:
			return count == 0
		CountMode.AT_LEAST:
			return count >= count_threshold
		CountMode.AT_MOST:
			return count <= count_threshold
		CountMode.EXACTLY:
			return count == count_threshold
	
	return false


func get_debug_string() -> String:
	var type_str = EntityType.keys()[entity_type]
	var mode_str = CountMode.keys()[count_mode]
	return "Nearby %s: %s" % [type_str, mode_str]
