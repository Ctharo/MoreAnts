class_name SpatialHash
extends RefCounted
## Spatial hash grid for O(1) neighbor queries
## Divides the world into cells and tracks which entities are in each cell

var cell_size: float
var _grid: Dictionary = {}  # Vector2i -> Array of entities


func _init(p_cell_size: float = 50.0) -> void:
	cell_size = p_cell_size


## Get the cell coordinates for a world position
func _get_cell(pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(pos.x / cell_size),
		floori(pos.y / cell_size)
	)


## Clear all entries from the hash
func clear() -> void:
	_grid.clear()


## Insert an entity into the hash (entity must have global_position)
func insert(entity: Node) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	
	var cell = _get_cell(entity.global_position)
	
	if not _grid.has(cell):
		_grid[cell] = []
	
	_grid[cell].append(entity)


## Remove an entity from the hash
func remove(entity: Node) -> void:
	if entity == null:
		return
	
	var cell = _get_cell(entity.global_position)
	
	if _grid.has(cell):
		_grid[cell].erase(entity)


## Query all entities within a radius of a position
func query_radius(pos: Vector2, radius: float, exclude: Node = null) -> Array:
	var results: Array = []
	var radius_sq = radius * radius
	
	# Calculate cell range to check
	var min_cell = _get_cell(pos - Vector2(radius, radius))
	var max_cell = _get_cell(pos + Vector2(radius, radius))
	
	# Check all cells in range
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell = Vector2i(x, y)
			if not _grid.has(cell):
				continue
			
			for entity in _grid[cell]:
				if entity == exclude:
					continue
				if not is_instance_valid(entity):
					continue
				
				var dist_sq = pos.distance_squared_to(entity.global_position)
				if dist_sq <= radius_sq:
					results.append(entity)
	
	return results


## Query entities within radius that belong to a specific group
func query_radius_group(pos: Vector2, radius: float, group_name: String, exclude: Node = null) -> Array:
	var all_nearby = query_radius(pos, radius, exclude)
	var results: Array = []
	
	for entity in all_nearby:
		if entity.is_in_group(group_name):
			results.append(entity)
	
	return results


## Query the nearest entity within radius
func query_nearest(pos: Vector2, radius: float, exclude: Node = null) -> Node:
	var nearby = query_radius(pos, radius, exclude)
	
	if nearby.is_empty():
		return null
	
	var nearest: Node = null
	var nearest_dist_sq = INF
	
	for entity in nearby:
		var dist_sq = pos.distance_squared_to(entity.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = entity
	
	return nearest


## Query nearest entity in a specific group
func query_nearest_group(pos: Vector2, radius: float, group_name: String, exclude: Node = null) -> Node:
	var nearby = query_radius_group(pos, radius, group_name, exclude)
	
	if nearby.is_empty():
		return null
	
	var nearest: Node = null
	var nearest_dist_sq = INF
	
	for entity in nearby:
		var dist_sq = pos.distance_squared_to(entity.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = entity
	
	return nearest


## Get count of entities in a cell
func get_cell_count(cell: Vector2i) -> int:
	if not _grid.has(cell):
		return 0
	return _grid[cell].size()


## Get all entities in a cell
func get_cell_contents(cell: Vector2i) -> Array:
	if not _grid.has(cell):
		return []
	return _grid[cell].duplicate()


## Get statistics about the hash
func get_stats() -> Dictionary:
	var total_entities = 0
	var max_per_cell = 0
	var non_empty_cells = 0
	
	for cell in _grid:
		var count = _grid[cell].size()
		if count > 0:
			non_empty_cells += 1
			total_entities += count
			max_per_cell = maxi(max_per_cell, count)
	
	return {
		"total_entities": total_entities,
		"non_empty_cells": non_empty_cells,
		"max_per_cell": max_per_cell,
		"avg_per_cell": float(total_entities) / maxf(non_empty_cells, 1),
	}
