class_name RoadNetwork
extends Node3D
## Directed lane graph for civilian traffic.
##
## Separate from NavGraph because roads are not pavements: lanes have a
## direction of travel, a car may only join a lane going roughly the same way,
## and a route is chosen a junction at a time rather than solved end to end.
## Pedestrians want shortest paths; traffic wants plausible ones.
##
## Built from "strands" — directed polylines down the centre of each lane. Turns
## at junctions are not authored: a node links to any node ahead of it, within
## reach, that is not a U-turn. At a crossroads that automatically produces
## straight-on plus a left and a right, and adding a road means adding a strand.

## Distance between sampled lane nodes.
@export var node_spacing: float = 5.0
## Two nodes further apart than this never link.
@export var link_max_distance: float = 11.0
## A successor must lie within this angle of the lane's own heading, which is
## what stops a link cutting back across the junction.
@export var link_forward_angle: float = 62.0
## Successor lanes may differ in heading by at most this much — enough for a
## left or right turn, not enough for a U-turn.
@export var link_turn_angle: float = 100.0

var _positions: Array[Vector3] = []
var _directions: Array[Vector3] = []
var _successors: Array[PackedInt32Array] = []


func _ready() -> void:
	add_to_group(&"road_network")


## `strands` is an array of arrays of Vector2 waypoints, each read in the
## direction traffic travels.
func build(strands: Array) -> void:
	_positions.clear()
	_directions.clear()
	_successors.clear()

	for strand in strands:
		_sample_strand(strand)
	_link_nodes()


func node_count() -> int:
	return _positions.size()


func _valid(index: int) -> bool:
	return index >= 0 and index < _positions.size()


func is_ready() -> bool:
	return _positions.size() > 1


func node_position(index: int) -> Vector3:
	return _positions[index] if _valid(index) else Vector3.ZERO


func node_direction(index: int) -> Vector3:
	return _directions[index] if _valid(index) else Vector3.FORWARD


func successors(index: int) -> PackedInt32Array:
	return _successors[index] if _valid(index) else PackedInt32Array()


## True when this node has nowhere to go — the far end of a strand.
func is_dead_end(index: int) -> bool:
	return successors(index).is_empty()


## Nearest node whose lane runs roughly the same way as `heading`. Passing a
## heading matters: the node closest in space is often the oncoming lane.
func nearest_node(position: Vector3, heading: Vector3 = Vector3.ZERO) -> int:
	var best := -1
	var best_score := INF
	var has_heading := heading.length_squared() > 0.01
	var wanted := heading.normalized() if has_heading else Vector3.ZERO

	for i in _positions.size():
		if has_heading and _directions[i].dot(wanted) < 0.2:
			continue
		var score := _positions[i].distance_squared_to(position)
		if score < best_score:
			best_score = score
			best = i
	# Nothing runs the right way; fall back to plain proximity.
	if best == -1 and has_heading:
		return nearest_node(position)
	return best


func random_node(rng: RandomNumberGenerator) -> int:
	if _positions.is_empty():
		return -1
	return rng.randi_range(0, _positions.size() - 1)


## Picks where to go next. Random among successors, so cars do not all grind
## round the same loop.
func random_successor(index: int, rng: RandomNumberGenerator) -> int:
	var options := successors(index)
	if options.is_empty():
		return -1
	return options[rng.randi_range(0, options.size() - 1)]


# --- Building ------------------------------------------------------------

func _sample_strand(waypoints: Array) -> void:
	for segment in waypoints.size() - 1:
		var start: Vector2 = waypoints[segment]
		var end: Vector2 = waypoints[segment + 1]
		var length := start.distance_to(end)
		var steps := maxi(1, int(round(length / node_spacing)))
		var direction := Vector3(end.x - start.x, 0.0, end.y - start.y).normalized()
		# The final node of a segment is the first of the next one, so it is only
		# emitted for the last segment.
		var last := steps if segment == waypoints.size() - 2 else steps - 1
		for step in last + 1:
			var flat := start.lerp(end, float(step) / float(steps))
			_positions.append(Vector3(flat.x, 0.0, flat.y))
			_directions.append(direction)


func _link_nodes() -> void:
	var forward_limit := cos(deg_to_rad(link_forward_angle))
	var turn_limit := cos(deg_to_rad(link_turn_angle))

	for i in _positions.size():
		var links := PackedInt32Array()
		for j in _positions.size():
			if i == j:
				continue
			var offset := _positions[j] - _positions[i]
			var distance := offset.length()
			if distance < 0.5 or distance > link_max_distance:
				continue
			# Must be ahead of us...
			if _directions[i].dot(offset / distance) < forward_limit:
				continue
			# ...and not require doubling back.
			if _directions[i].dot(_directions[j]) < turn_limit:
				continue
			links.append(j)
		_successors.append(links)
