class_name Obstacle
extends Node2D
## Static obstacle that ants must navigate around
## Uses local sensing (antenna-based) rather than pathfinding for efficiency

enum ShapeType {
	CIRCLE = 0,
	RECTANGLE = 1,
}

#region Configuration
@export var shape_type: ShapeType = ShapeType.CIRCLE
@export var obstacle_radius: float = 30.0  # For CIRCLE
@export var obstacle_size: Vector2 = Vector2(60, 30)  # For RECTANGLE
@export var color: Color = Color(0.4, 0.35, 0.3, 0.9)  # Brown/rock color
@export var outline_color: Color = Color(0.25, 0.2, 0.15, 1.0)
#endregion


func _ready() -> void:
	add_to_group("obstacles")


func _draw() -> void:
	match shape_type:
		ShapeType.CIRCLE:
			draw_circle(Vector2.ZERO, obstacle_radius, color)
			draw_arc(Vector2.ZERO, obstacle_radius, 0, TAU, 32, outline_color, 2.0)
		ShapeType.RECTANGLE:
			var rect: Rect2 = Rect2(-obstacle_size / 2.0, obstacle_size)
			draw_rect(rect, color)
			draw_rect(rect, outline_color, false, 2.0)


## Check if a world point is inside this obstacle
func contains_point(world_pos: Vector2) -> bool:
	var local_pos: Vector2 = to_local(world_pos)
	
	match shape_type:
		ShapeType.CIRCLE:
			return local_pos.length() <= obstacle_radius
		ShapeType.RECTANGLE:
			var half_size: Vector2 = obstacle_size / 2.0
			return absf(local_pos.x) <= half_size.x and absf(local_pos.y) <= half_size.y
	
	return false


## Get the distance from a world point to the surface of this obstacle
## Returns 0 if inside, positive if outside
func get_distance_to_surface(world_pos: Vector2) -> float:
	var local_pos: Vector2 = to_local(world_pos)
	
	match shape_type:
		ShapeType.CIRCLE:
			return maxf(0.0, local_pos.length() - obstacle_radius)
		ShapeType.RECTANGLE:
			var half_size: Vector2 = obstacle_size / 2.0
			# Distance to axis-aligned rectangle
			var dx: float = maxf(absf(local_pos.x) - half_size.x, 0.0)
			var dy: float = maxf(absf(local_pos.y) - half_size.y, 0.0)
			return sqrt(dx * dx + dy * dy)
	
	return INF


## Get the nearest point on the obstacle surface from a world position
func get_nearest_surface_point(world_pos: Vector2) -> Vector2:
	var local_pos: Vector2 = to_local(world_pos)
	var surface_local: Vector2
	
	match shape_type:
		ShapeType.CIRCLE:
			if local_pos.length() < 0.001:
				surface_local = Vector2(obstacle_radius, 0)
			else:
				surface_local = local_pos.normalized() * obstacle_radius
		ShapeType.RECTANGLE:
			var half_size: Vector2 = obstacle_size / 2.0
			# Clamp to rectangle boundary
			surface_local = Vector2(
				clampf(local_pos.x, -half_size.x, half_size.x),
				clampf(local_pos.y, -half_size.y, half_size.y)
			)
			# If inside, push to nearest edge
			if contains_point(world_pos):
				var dist_to_edges: Array[float] = [
					half_size.x - absf(local_pos.x),  # Distance to left/right edge
					half_size.y - absf(local_pos.y),  # Distance to top/bottom edge
				]
				if dist_to_edges[0] < dist_to_edges[1]:
					surface_local.x = half_size.x * signf(local_pos.x)
				else:
					surface_local.y = half_size.y * signf(local_pos.y)
	
	return to_global(surface_local)


## Get the outward normal at a point near the obstacle surface
func get_surface_normal(world_pos: Vector2) -> Vector2:
	var local_pos: Vector2 = to_local(world_pos)
	var normal_local: Vector2
	
	match shape_type:
		ShapeType.CIRCLE:
			if local_pos.length() < 0.001:
				normal_local = Vector2.RIGHT
			else:
				normal_local = local_pos.normalized()
		ShapeType.RECTANGLE:
			var half_size: Vector2 = obstacle_size / 2.0
			# Find which face is closest
			var dist_to_faces: Dictionary = {
				"right": half_size.x - local_pos.x,
				"left": half_size.x + local_pos.x,
				"bottom": half_size.y - local_pos.y,
				"top": half_size.y + local_pos.y,
			}
			var min_dist: float = INF
			var closest_face: String = "right"
			for face: String in dist_to_faces:
				if dist_to_faces[face] < min_dist:
					min_dist = dist_to_faces[face]
					closest_face = face
			
			match closest_face:
				"right": normal_local = Vector2.RIGHT
				"left": normal_local = Vector2.LEFT
				"bottom": normal_local = Vector2.DOWN
				"top": normal_local = Vector2.UP
				_: normal_local = Vector2.RIGHT
	
	# Rotate normal by obstacle's rotation
	return normal_local.rotated(rotation)


## Get the effective radius for spatial hash queries
func get_bounding_radius() -> float:
	match shape_type:
		ShapeType.CIRCLE:
			return obstacle_radius
		ShapeType.RECTANGLE:
			return obstacle_size.length() / 2.0
	return 0.0


## Check if a line segment intersects this obstacle
func intersects_segment(start: Vector2, end: Vector2) -> bool:
	var local_start: Vector2 = to_local(start)
	var local_end: Vector2 = to_local(end)
	
	match shape_type:
		ShapeType.CIRCLE:
			return _segment_intersects_circle(local_start, local_end, obstacle_radius)
		ShapeType.RECTANGLE:
			return _segment_intersects_rect(local_start, local_end, obstacle_size / 2.0)
	
	return false


func _segment_intersects_circle(start: Vector2, end: Vector2, radius: float) -> bool:
	var d: Vector2 = end - start
	var f: Vector2 = start
	
	var a: float = d.dot(d)
	var b: float = 2.0 * f.dot(d)
	var c: float = f.dot(f) - radius * radius
	
	var discriminant: float = b * b - 4.0 * a * c
	if discriminant < 0:
		return false
	
	discriminant = sqrt(discriminant)
	var t1: float = (-b - discriminant) / (2.0 * a)
	var t2: float = (-b + discriminant) / (2.0 * a)
	
	return (t1 >= 0 and t1 <= 1) or (t2 >= 0 and t2 <= 1) or (t1 < 0 and t2 > 1)


func _segment_intersects_rect(start: Vector2, end: Vector2, half_size: Vector2) -> bool:
	# Check if either endpoint is inside
	if absf(start.x) <= half_size.x and absf(start.y) <= half_size.y:
		return true
	if absf(end.x) <= half_size.x and absf(end.y) <= half_size.y:
		return true
	
	# Check intersection with each edge using line-line intersection
	var corners: Array[Vector2] = [
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	]
	
	for i: int in range(4):
		var c1: Vector2 = corners[i]
		var c2: Vector2 = corners[(i + 1) % 4]
		if _segments_intersect(start, end, c1, c2):
			return true
	
	return false


func _segments_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1: Vector2 = p2 - p1
	var d2: Vector2 = p4 - p3
	var d3: Vector2 = p1 - p3
	
	var cross: float = d1.x * d2.y - d1.y * d2.x
	if absf(cross) < 0.0001:
		return false  # Parallel
	
	var t: float = (d3.x * d2.y - d3.y * d2.x) / cross
	var u: float = (d3.x * d1.y - d3.y * d1.x) / cross
	
	return t >= 0 and t <= 1 and u >= 0 and u <= 1
