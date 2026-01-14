class_name PheromoneField
extends RefCounted
## Grid-based pheromone field with diffusion and evaporation

var field_name: String
var width: int
var height: int
var cell_size: float

# Grid data (2D array stored as 1D)
var grid: PackedFloat32Array
var _next_grid: PackedFloat32Array  # Double buffer for diffusion

# Field properties
var diffusion_rate: float = 0.1
var evaporation_rate: float = 0.02
var max_concentration: float = 255.0

# Visualization
var color: Color = Color.GREEN

# Statistics
var current_total: float = 0.0


func _init(p_name: String, world_width: float, world_height: float, p_cell_size: float) -> void:
	field_name = p_name
	cell_size = p_cell_size
	width = ceili(world_width / cell_size)
	height = ceili(world_height / cell_size)
	
	var size = width * height
	grid = PackedFloat32Array()
	grid.resize(size)
	_next_grid = PackedFloat32Array()
	_next_grid.resize(size)


## Convert world position to grid coordinates
func _world_to_grid(pos: Vector2) -> Vector2i:
	return Vector2i(
		clampi(floori(pos.x / cell_size), 0, width - 1),
		clampi(floori(pos.y / cell_size), 0, height - 1)
	)


## Convert grid coordinates to array index
func _grid_to_index(x: int, y: int) -> int:
	return y * width + x


## Get value at grid position
func get_at(x: int, y: int) -> float:
	if x < 0 or x >= width or y < 0 or y >= height:
		return 0.0
	return grid[_grid_to_index(x, y)]


## Set value at grid position
func set_at(x: int, y: int, value: float) -> void:
	if x < 0 or x >= width or y < 0 or y >= height:
		return
	grid[_grid_to_index(x, y)] = clampf(value, 0.0, max_concentration)


## Deposit pheromone at world position
func deposit(pos: Vector2, amount: float) -> void:
	var cell = _world_to_grid(pos)
	var current = get_at(cell.x, cell.y)
	set_at(cell.x, cell.y, current + amount)


## Deposit pheromone with spread across multiple cells
func deposit_spread(pos: Vector2, amount: float, radius: int = 1) -> void:
	var center = _world_to_grid(pos)
	var total_cells = (2 * radius + 1) * (2 * radius + 1)
	var amount_per_cell = amount / total_cells
	
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var x = center.x + dx
			var y = center.y + dy
			var current = get_at(x, y)
			set_at(x, y, current + amount_per_cell)


## Sample pheromone at world position
func sample(pos: Vector2) -> float:
	var cell = _world_to_grid(pos)
	return get_at(cell.x, cell.y)


## Sample pheromone at antenna positions (left, center, right)
func sample_antenna(pos: Vector2, heading: float, distance: float, angle: float) -> Dictionary:
	var left_pos = pos + Vector2(cos(heading - angle), sin(heading - angle)) * distance
	var center_pos = pos + Vector2(cos(heading), sin(heading)) * distance
	var right_pos = pos + Vector2(cos(heading + angle), sin(heading + angle)) * distance
	
	return {
		"left": sample(left_pos),
		"center": sample(center_pos),
		"right": sample(right_pos),
	}


## Get gradient direction at position (for following pheromone trails)
func get_gradient(pos: Vector2) -> Vector2:
	var cell = _world_to_grid(pos)
	
	# Sample neighboring cells
	var left = get_at(cell.x - 1, cell.y)
	var right = get_at(cell.x + 1, cell.y)
	var up = get_at(cell.x, cell.y - 1)
	var down = get_at(cell.x, cell.y + 1)
	
	# Compute gradient
	var dx = right - left
	var dy = down - up
	
	var gradient = Vector2(dx, dy)
	if gradient.length_squared() > 0.001:
		return gradient.normalized()
	return Vector2.ZERO


## Update field (diffusion and evaporation)
func update(delta: float) -> void:
	current_total = 0.0
	
	# Apply diffusion and evaporation
	for y in range(height):
		for x in range(width):
			var idx = _grid_to_index(x, y)
			var current = grid[idx]
			
			if current < 0.001:
				_next_grid[idx] = 0.0
				continue
			
			# Evaporation
			current *= (1.0 - evaporation_rate * delta)
			
			# Diffusion (simple 4-neighbor averaging)
			if diffusion_rate > 0:
				var neighbors_sum = 0.0
				var neighbor_count = 0
				
				if x > 0:
					neighbors_sum += grid[_grid_to_index(x - 1, y)]
					neighbor_count += 1
				if x < width - 1:
					neighbors_sum += grid[_grid_to_index(x + 1, y)]
					neighbor_count += 1
				if y > 0:
					neighbors_sum += grid[_grid_to_index(x, y - 1)]
					neighbor_count += 1
				if y < height - 1:
					neighbors_sum += grid[_grid_to_index(x, y + 1)]
					neighbor_count += 1
				
				if neighbor_count > 0:
					var neighbor_avg = neighbors_sum / neighbor_count
					current = lerpf(current, neighbor_avg, diffusion_rate * delta)
			
			_next_grid[idx] = clampf(current, 0.0, max_concentration)
			current_total += _next_grid[idx]
	
	# Swap buffers
	var temp = grid
	grid = _next_grid
	_next_grid = temp


## Clear all pheromone
func clear() -> void:
	grid.fill(0.0)
	current_total = 0.0


## Get field statistics
func get_stats() -> Dictionary:
	var max_val: float = 0.0
	var non_zero_cells: int = 0
	
	for i in range(grid.size()):
		if grid[i] > 0.001:
			non_zero_cells += 1
			max_val = maxf(max_val, grid[i])
	
	return {
		"field_name": field_name,
		"total": current_total,
		"max_value": max_val,
		"non_zero_cells": non_zero_cells,
		"coverage_percent": float(non_zero_cells) / (width * height) * 100.0,
	}
