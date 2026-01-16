class_name FoodSource
extends Node2D
## A source of food that ants can harvest and carry

signal depleted
signal harvested(amount: float)

#region Properties
@export var food_amount: float = 100.0
@export var max_food: float = 100.0
@export var harvest_rate: float = 5.0  # Food taken per pickup
@export var regeneration_rate: float = 0.0  # Food per second (0 = no regen)
#endregion

#region Visual Properties
@export var base_radius: float = 6.0
@export var color: Color = Color.YELLOW_GREEN
#endregion

#region Item Properties (for when carried)
var item_type: String = "food"
var food_value: float = 5.0  # Amount of food this represents when carried
var weight: float = 1.0
#endregion

#region State
var is_picked_up: bool = false
#endregion


func _ready() -> void:
	add_to_group("food")
	food_value = harvest_rate


func _process(delta: float) -> void:
	if not GameManager.is_running:
		return
	
	# Don't process if picked up
	if is_picked_up:
		return
	
	# Regeneration
	if regeneration_rate > 0 and food_amount < max_food:
		food_amount = minf(food_amount + regeneration_rate * delta * GameManager.time_scale, max_food)
	
	queue_redraw()


func _draw() -> void:
	# Don't draw if picked up
	if is_picked_up:
		return
	
	# Size based on remaining food
	var size_ratio: float = food_amount / maxf(max_food, 1.0)
	var radius: float = base_radius * (0.5 + 0.5 * size_ratio)
	
	# Draw food circle
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 12, color.darkened(0.3), 1.0)


## Attempt to pick up food from this source
## Returns self if successful, null if unavailable
func pickup() -> Node:
	if is_picked_up:
		return null
	
	if food_amount <= 0:
		return null
	
	# Take food from source
	var amount: float = minf(harvest_rate, food_amount)
	food_amount -= amount
	food_value = amount
	
	# Mark as picked up immediately
	is_picked_up = true
	visible = false
	
	harvested.emit(amount)
	
	# Check if source is now depleted
	if food_amount <= 0:
		depleted.emit()
	
	return self


## Drop the food at a position (when ant drops it or dies)
func drop(pos: Vector2) -> void:
	global_position = pos
	is_picked_up = false
	visible = true
	
	# Restore food amount from food_value
	food_amount = food_value
	max_food = food_value
	
	queue_redraw()


## Check if this food source is available for pickup
func is_available() -> bool:
	return not is_picked_up and food_amount > 0
