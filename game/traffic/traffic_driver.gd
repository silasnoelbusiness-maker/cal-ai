class_name TrafficDriver
extends Node
## AI driver for a civilian car.
##
## Same shape as PoliceDriver — a child Node feeding `Vehicle.set_ai_input()` —
## so civilian traffic, police and the player all share one handling model.
## What differs is the decision making: this one obeys lanes, keeps its distance,
## stops at red lights and tries not to run people over.
##
## Route choice happens one junction at a time from RoadNetwork successors, so
## cars diverge naturally instead of all circling the same block.

signal recycle_requested()

enum State { DRIVING, WAITING, STUCK }

@export_group("Speed")
## Cruising speed in m/s. ~11 m/s is about 40 km/h.
@export var cruise_speed: float = 11.0
## Speed held through a tight corner.
@export var corner_speed: float = 5.5
## Heading error above which the car is considered cornering.
@export var corner_angle: float = 34.0
@export_group("Steering")
@export var full_lock_angle: float = 34.0
@export var waypoint_radius: float = 2.5

@export_group("Awareness")
## Seconds between forward sensor casts. Coarse on purpose.
@export var sense_interval: float = 0.12
## Sensor length at a standstill; speed is added on top.
@export var sense_base_length: float = 5.0
@export var sense_speed_factor: float = 0.9
## Closer than this to whatever is ahead and the car stops rather than crawls.
@export var stop_distance: float = 3.2
## Half-angle of the fan of forward casts. A single centre ray misses a car
## crossing the junction diagonally in front — which is exactly the one that
## needs to be seen, because that is the collision that wedges a junction.
@export var sense_spread: float = 18.0
## How far to one side of a stop line a car may be and still be approaching it.
## A road half-width: enough for either lane, not enough to pick up the signals
## on the cross street.
@export var light_lane_tolerance: float = 5.0
## Inside this distance from a red, the car commits to stopping for it.
@export var light_commit_distance: float = 18.0

@export_group("Recovery")
## Barely moving while trying to drive for this long counts as stuck.
@export var stuck_timeout: float = 3.5
## How long the car backs off for on each recovery attempt.
@export var reverse_seconds: float = 0.8
## Give up and ask to be recycled after this many failed recoveries.
@export var max_recoveries: int = 3
## Absolute backstop, independent of why the car thinks it is stopped: if it has
## not actually got anywhere in this long, recycle it. The ladder above cannot
## break a deadlock, because in a deadlock every car is correctly waiting for
## the one in front and none of them believes it is stuck.
@export var jam_timeout: float = 7.0
## How far the car has to move to count as having got somewhere.
@export var jam_distance: float = 3.0

var state: State = State.DRIVING

var _car: Vehicle = null
var _network: RoadNetwork = null
var _target_node: int = -1
var _sense_timer: float = 0.0
var _blocked_distance: float = INF
var _blocked_by_pedestrian: bool = false
var _stuck_time: float = 0.0
var _recoveries: int = 0
var _reverse_time: float = 0.0
var _reverse_steer: float = 0.0
var _jam_anchor: Vector3 = Vector3.ZERO
var _jam_time: float = 0.0
## The signal this car has committed to stopping for, if any.
var _held_light: TrafficLight = null
var _rng := RandomNumberGenerator.new()
var _light_cache: Array[TrafficLight] = []


func _ready() -> void:
	_rng.randomize()
	_car = get_parent() as Vehicle
	if _car == null:
		push_error("TrafficDriver must be a child of a Vehicle.")
		set_physics_process(false)
		return

	_car.controller = Vehicle.Controller.TRAFFIC_AI
	_car.add_to_group(&"traffic")
	_network = get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	for light in get_tree().get_nodes_in_group(&"traffic_light"):
		_light_cache.append(light)

	_jam_anchor = _car.global_position
	_pick_initial_target()


func get_car() -> Vehicle:
	return _car


func get_target_position() -> Vector3:
	if _network == null or _target_node < 0:
		return _car.global_position
	return _network.node_position(_target_node)


## Points the car at a fresh stretch of road. Used on spawn and on recycle.
func restart_at(node_index: int) -> void:
	_target_node = node_index
	_recoveries = 0
	_stuck_time = 0.0
	_reverse_time = 0.0
	_jam_time = 0.0
	_jam_anchor = _car.global_position
	_held_light = null
	state = State.DRIVING
	_advance_target()


func _physics_process(delta: float) -> void:
	if _network == null or _car.is_disabled():
		_car.set_ai_input(0.0, 0.0, true)
		return

	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = sense_interval
		_sense_ahead()

	_watch_for_jam(delta)

	if _reverse_time > 0.0:
		_reverse_time -= delta
		_car.set_ai_input(-1.0, _reverse_steer, false)
		if _reverse_time <= 0.0:
			# Re-join the network from wherever backing off left us.
			_pick_initial_target()
		return

	if _target_node < 0:
		_pick_initial_target()
		return

	_follow_lane(delta)
	_check_stuck(delta)


# --- Driving -------------------------------------------------------------

func _follow_lane(delta: float) -> void:
	var target := _network.node_position(_target_node)
	if _car.global_position.distance_to(target) < waypoint_radius:
		_advance_target()
		target = _network.node_position(_target_node)

	var to_target := target - _car.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		_car.set_ai_input(0.0, 0.0, true)
		return

	var forward := -_car.global_transform.basis.z
	forward.y = 0.0
	var heading_error := forward.signed_angle_to(to_target.normalized(), Vector3.UP)
	var steer := clampf(heading_error / deg_to_rad(full_lock_angle), -1.0, 1.0)

	var wanted := _wanted_speed(heading_error)
	var speed := _car.get_forward_speed()
	var throttle := 0.0
	if wanted <= 0.05:
		# Stop: brake if rolling, hold still if already stopped.
		throttle = -1.0 if speed > 0.4 else 0.0
		state = State.WAITING if state != State.STUCK else state
	else:
		throttle = 1.0 if speed < wanted else -0.25
		if state == State.WAITING:
			state = State.DRIVING

	_car.set_ai_input(throttle, steer, wanted <= 0.05 and speed < 0.4)


## The slowest of every reason to ease off: corners, the car in front, red
## lights and anyone stood in the road.
func _wanted_speed(heading_error: float) -> float:
	var wanted := cruise_speed
	# The lane's own change of direction matters as much as the current heading
	# error: taking the turn into account *before* the nose has swung round is
	# what stops a car carrying junction speed into a corner and swinging wide
	# across the box into oncoming traffic.
	if maxf(absf(heading_error), _lane_turn_angle()) > deg_to_rad(corner_angle):
		wanted = minf(wanted, corner_speed)

	if _blocked_distance < stop_distance:
		return 0.0
	if _blocked_distance < INF:
		# Ease down smoothly across the sensor's range rather than slamming on.
		var room := (_blocked_distance - stop_distance) / maxf(_sensor_length(), 0.01)
		wanted = minf(wanted, cruise_speed * clampf(room, 0.0, 1.0))
		if _blocked_by_pedestrian:
			wanted = minf(wanted, corner_speed * 0.5)

	var light_stop := _distance_to_red_light()
	if light_stop < INF:
		if light_stop < 1.6:
			return 0.0
		wanted = minf(wanted, cruise_speed * clampf(light_stop / 12.0, 0.0, 1.0))
	return wanted


## Angle between where the car is pointed and the direction of the lane it is
## heading into.
func _lane_turn_angle() -> float:
	if _target_node < 0:
		return 0.0
	var forward := -_car.global_transform.basis.z
	forward.y = 0.0
	var lane := _network.node_direction(_target_node)
	if forward.length_squared() < 0.01 or lane.length_squared() < 0.01:
		return 0.0
	return absf(forward.normalized().signed_angle_to(lane.normalized(), Vector3.UP))


func _advance_target() -> void:
	var next := _network.random_successor(_target_node, _rng)
	if next < 0:
		# End of the line — the far edge of the district. Ask for a recycle.
		recycle_requested.emit()
		return
	_target_node = next


func _pick_initial_target() -> void:
	if _network == null or not _network.is_ready():
		return
	var forward := -_car.global_transform.basis.z
	_target_node = _network.nearest_node(_car.global_position, forward)
	if _target_node >= 0:
		_advance_target()


# --- Sensing -------------------------------------------------------------

func _sensor_length() -> float:
	return sense_base_length + absf(_car.get_forward_speed()) * sense_speed_factor


## A three-ray fan from the nose, catching vehicles and pedestrians in the same
## casts. Three rays every eighth of a second is far cheaper than a shape cast
## per frame, and coarse enough that a car occasionally clips someone — which
## the brief allows, and which keeps the roads moving.
func _sense_ahead() -> void:
	_blocked_distance = INF
	_blocked_by_pedestrian = false

	var forward := -_car.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return
	forward = forward.normalized()

	var nose := _car.global_position + forward * (_car.data.body_length * 0.5) + Vector3.UP * 0.7
	var length := _sensor_length()
	var space := _car.get_world_3d().direct_space_state

	for angle in [0.0, sense_spread, -sense_spread]:
		var direction := forward.rotated(Vector3.UP, deg_to_rad(angle))
		var query := PhysicsRayQueryParameters3D.create(nose, nose + direction * length)
		# Vehicles (4) and NPCs (5).
		query.collision_mask = (1 << 3) | (1 << 4)
		query.exclude = [_car.get_rid()]

		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var distance := nose.distance_to(hit["position"])
		if distance >= _blocked_distance:
			continue
		_blocked_distance = distance
		_blocked_by_pedestrian = hit.get("collider") is NpcWalker


## Distance to the stop line of a red light this car is approaching, or INF.
##
## Once a car is inside braking range of a red it commits, and stays committed
## until that signal is actually green. Without the latch a single frame in which
## the geometry below narrowly rejects the light — the car drifting a little
## across its lane while it brakes is enough — puts the throttle back down, and
## the car ends up stopped in the middle of the junction instead of at the line.
## That failed about one run in three and was miserable to reproduce, which is
## the signature of a missing latch rather than of bad tuning.
func _distance_to_red_light() -> float:
	if _light_cache.is_empty():
		return INF
	var forward := -_car.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		return INF
	forward = forward.normalized()
	var east_west := absf(forward.x) > absf(forward.z)

	if _held_light != null:
		if is_instance_valid(_held_light) and _held_light.should_stop_for(east_west):
			# Never negative: a car that has crept over the line still holds.
			return maxf(_line_distance(_held_light, forward), 0.0)
		_held_light = null

	var best := INF
	var closest: TrafficLight = null
	for light in _light_cache:
		if not light.should_stop_for(east_west):
			continue
		var line := light.stop_line_for(forward)
		var offset := line - _car.global_position
		offset.y = 0.0
		var ahead := offset.dot(forward)
		# Only lights in front of us, and only the one we are about to reach.
		if ahead < 0.0 or ahead > 26.0:
			continue
		# Ignore lights we are not actually heading into. Measured sideways in
		# metres rather than as an angle: an angular test degenerates as the car
		# closes on the line, and a car two metres out in its own lane would
		# suddenly decide the signal was not for it and drive straight through.
		var lateral := absf(offset.dot(Vector3(-forward.z, 0.0, forward.x)))
		if lateral > light_lane_tolerance:
			continue
		if ahead < best:
			best = ahead
			closest = light
	if closest != null and best < light_commit_distance:
		_held_light = closest
	return best


## Signed distance from the car to a light's stop line along its own heading.
func _line_distance(light: TrafficLight, forward: Vector3) -> float:
	var offset := light.stop_line_for(forward) - _car.global_position
	offset.y = 0.0
	return offset.dot(forward)


# --- Recovery ------------------------------------------------------------

## Wedged cars try a different route first, then a nudge backwards, and only
## then ask to be taken away — so a jam clears itself without anything
## disappearing in front of the player.
func _check_stuck(delta: float) -> void:
	var trying := absf(_car.get_forward_speed()) < 0.35
	var should_be_moving := _wanted_speed(0.0) > 0.05 and _blocked_distance >= stop_distance
	if not (trying and should_be_moving):
		_stuck_time = 0.0
		if state == State.STUCK:
			state = State.DRIVING
		return

	_stuck_time += delta
	if _stuck_time < stuck_timeout:
		return

	_stuck_time = 0.0
	state = State.STUCK
	_recoveries += 1

	if _recoveries > max_recoveries:
		recycle_requested.emit()
		return

	# First attempt: try a different way out of this node without moving.
	if _recoveries == 1:
		var alternative := _network.random_successor(_target_node, _rng)
		if alternative >= 0:
			_target_node = alternative
		return

	# After that, back off and re-join the network. The steer is small and the
	# car re-acquires a lane afterwards, because a big random one leaves it
	# parked across the road — which was how one wedged car used to gridlock a
	# whole junction.
	_reverse_time = reverse_seconds
	_reverse_steer = _rng.randf_range(-0.3, 0.3)


## Last resort, and the only recovery that cannot be defeated by a car being
## "correctly" stopped: if nothing has actually moved in a long while, take this
## one out of circulation.
func _watch_for_jam(delta: float) -> void:
	if _car.global_position.distance_to(_jam_anchor) > jam_distance:
		_jam_anchor = _car.global_position
		_jam_time = 0.0
		return
	_jam_time += delta
	if _jam_time < jam_timeout:
		return
	_jam_time = 0.0
	recycle_requested.emit()
