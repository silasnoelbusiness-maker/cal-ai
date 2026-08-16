class_name NavGraph
extends Node3D
## The city's walkable and drivable route network.
##
## Built as two AStar3D graphs — one over the pavements, one over the road
## centrelines — sampled from the same polylines the district draws its streets
## from. Godot's NavigationServer would mean baking a navmesh from procedurally
## built geometry at runtime, which is slow, awkward to verify headlessly, and
## far more machinery than a grid of streets needs. A waypoint graph is exact,
## deterministic, testable, and gives pedestrians pavements and police cars
## roads out of the same structure.
##
## Everything here is geometry-agnostic: `build()` takes polylines, so a second
## district supplies its own and nothing in this file changes.

enum Layer { WALK, ROAD }

## Sampling distance along each polyline.
@export var walk_spacing: float = 5.0
@export var road_spacing: float = 8.0
## Two points closer than this become neighbours. Must exceed the sampling
## spacing, but stay under the width of a road so a link never jumps a
## carriageway where there is no crossing.
@export var walk_connect_radius: float = 8.0
@export var road_connect_radius: float = 12.0

var _graphs: Dictionary = {}
var _point_ids: Dictionary = {}


func _ready() -> void:
	add_to_group(&"nav_graph")


## `walk_lines` and `road_lines` are arrays of [Vector2 start, Vector2 end] on
## the ground plane.
func build(walk_lines: Array, road_lines: Array) -> void:
	_build_layer(Layer.WALK, walk_lines, walk_spacing, walk_connect_radius)
	_build_layer(Layer.ROAD, road_lines, road_spacing, road_connect_radius)


func point_count(layer: Layer) -> int:
	return (_point_ids[layer] as Array).size()


func is_ready(layer: Layer) -> bool:
	return _point_ids.has(layer) and point_count(layer) > 1


## Nearest graph node to an arbitrary world position.
func snap(layer: Layer, position: Vector3) -> Vector3:
	var graph: AStar3D = _graphs[layer]
	if graph.get_point_count() == 0:
		return position
	return graph.get_point_position(graph.get_closest_point(position))


## A route from anywhere to anywhere, snapped onto the graph at both ends.
## Returns an empty array when the two ends are not connected.
func find_path(layer: Layer, from: Vector3, to: Vector3) -> PackedVector3Array:
	var graph: AStar3D = _graphs[layer]
	if graph.get_point_count() == 0:
		return PackedVector3Array()
	var start := graph.get_closest_point(from)
	var goal := graph.get_closest_point(to)
	return graph.get_point_path(start, goal)


func random_point(layer: Layer, rng: RandomNumberGenerator = null) -> Vector3:
	var ids: Array = _point_ids[layer]
	if ids.is_empty():
		return global_position
	var index := (
		rng.randi_range(0, ids.size() - 1) if rng != null else randi() % ids.size()
	)
	return (_graphs[layer] as AStar3D).get_point_position(ids[index])


## A point at least `min_distance` away from `origin`, for fleeing and for
## patrol routes that actually go somewhere.
func random_point_away_from(
	layer: Layer, origin: Vector3, min_distance: float, rng: RandomNumberGenerator = null
) -> Vector3:
	var best := random_point(layer, rng)
	var best_distance := best.distance_to(origin)
	# A few samples is plenty; this does not need to find the true maximum.
	for i in 6:
		var candidate := random_point(layer, rng)
		var distance := candidate.distance_to(origin)
		if distance > best_distance:
			best = candidate
			best_distance = distance
		if best_distance >= min_distance:
			break
	return best


# --- Building ------------------------------------------------------------

func _build_layer(layer: Layer, lines: Array, spacing: float, connect_radius: float) -> void:
	var graph := AStar3D.new()
	var ids: Array[int] = []
	var positions: Array[Vector3] = []

	for line in lines:
		var start: Vector2 = line[0]
		var end: Vector2 = line[1]
		var length := start.distance_to(end)
		var steps := maxi(1, int(round(length / spacing)))
		for step in steps + 1:
			var flat := start.lerp(end, float(step) / float(steps))
			var point := Vector3(flat.x, 0.0, flat.y)
			# Lines cross at junctions; one node per crossing, not two.
			if _too_close(positions, point, spacing * 0.45):
				continue
			var id := positions.size()
			graph.add_point(id, point)
			positions.append(point)
			ids.append(id)

	# O(n^2), but it runs once at load over a couple of hundred points.
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			if positions[i].distance_to(positions[j]) <= connect_radius:
				graph.connect_points(i, j)

	_graphs[layer] = graph
	_point_ids[layer] = ids


func _too_close(positions: Array[Vector3], point: Vector3, threshold: float) -> bool:
	for existing in positions:
		if existing.distance_to(point) < threshold:
			return true
	return false
