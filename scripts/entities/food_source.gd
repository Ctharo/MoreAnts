class_name FoodSource
extends Node2D
## A source of food that ants can harvest

signal depleted
signal harvested(amount: float)

# Properties
@export var food_amount: float = 100.0
@export var max_food: float = 100.0
@export var harvest_rate: float = 5.0  # Max food per pickup
@export var regeneration_rate: float = 0.0  # Food per second (0 = no regen)

# Visual properties
@export var base_radius: float = 15.0
@export var color: Color = Color.YELLOW_GREEN

# Item properties (for when picked up)
var item_type: String = "food"
var food_value: float = 5.0
var weight: float = 1.0

# State
var is_picked_up: bool = false


func _ready() -> void:
	add_to_group("food")
	food_value = harvest_rate


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return
	
	if is_picked_up:
		return
	
	# Regeneration
	if regeneration_rate > 0 and food_amount < max_food:
		food_amount = minf(food_amount + regeneration_rate * delta * GameManager.time_scale, max_food)
	
	queue_redraw()


func _draw() -> void:
	if is_picked_up:
		return
	
	# Size based on remaining food
	var size_ratio = food_amount / max_food
	var radius = base_radius * (0.3 + 0.7 * size_ratio)
	
	# Draw food
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 16, color.darkened(0.3), 2.0)


## Attempt to pick up food from this source
## Returns self if successful, null if depleted
func pickup() -> Node:
	if food_amount <= 0:
		return null
	
	var amount = minf(harvest_rate, food_amount)
	food_amount -= amount
	food_value = amount
	
	harvested.emit(amount)
	
	if food_amount <= 0:
		is_picked_up = true
		depleted.emit()
	
	return self


## Drop the food (when ant drops it)
func drop() -> void:
	is_picked_up = false
	# Restore some food value when dropped
	food_amount = food_value


## Check if this food source is available
func is_available() -> bool:
	return food_amount > 0 and not is_picked_up
