class_name DeliveryDriver
extends TrafficDriver

## A traffic driver with somewhere to be.
##
## Everything about how the van moves — sensing, traffic lights, getting
## unstuck — is TrafficDriver's, unchanged. The only difference is where it
## goes next: instead of picking a random successor at every junction it walks
## a route planned once from the road network, and says so when it arrives.
##
## §107 asks that a delivery the player can see behaves like a delivery they
## cannot. It does: the van is a view of a TransferOrder that is already in
## transit, and reaching the kerb is what finishes the order rather than a
## second, competing simulation.

## The van reached its stop. The listener completes the transfer; the driver
## itself moves no goods.
signal arrived

## How close counts as arrived. A van cannot park on a shop counter, so this is
## generous enough to cover the pavement between the kerb and the door.
const ARRIVAL_RADIUS := 7.0
## Replanning is cheap but not free, and a van that has been shunted off its
## route only needs a new one every so often.
const REPLAN_INTERVAL := 2.5

var destination: Vector3 = Vector3.ZERO

var _route: PackedInt32Array = PackedInt32Array()
var _leg: int = 0
var _replan_timer: float = 0.0
var _finished: bool = false


func _ready() -> void:
	super()
	cruise_speed = 9.5
	corner_speed = 4.8


## Sends the van somewhere. Safe to call before or after the driver is in the
## tree; a destination set early is planned for on the first frame.
func drive_to(point: Vector3) -> void:
	destination = point
	_finished = false
	_plan()


func has_route() -> bool:
	return not _route.is_empty()


func distance_remaining() -> float:
	var car := get_car()
	if car == null:
		return 0.0
	return car.global_position.distance_to(destination)


func _physics_process(delta: float) -> void:
	super(delta)
	if _finished:
		return
	var car := get_car()
	if car == null:
		return
	if car.global_position.distance_to(destination) <= ARRIVAL_RADIUS:
		_finished = true
		car.set_ai_input(0.0, 0.0, true)
		arrived.emit()
		return
	_replan_timer -= delta
	if _replan_timer <= 0.0 and _leg >= _route.size():
		_plan()


## Walks the planned route. Falling off the end means the van is as close as
## the roads get it, so it aims at the destination itself and the arrival
## radius does the rest.
func _advance_target() -> void:
	if _leg < _route.size():
		_target_node = _route[_leg]
		_leg += 1
		return
	# Out of route. Head for whatever node is nearest the stop rather than
	# wandering off, and try to plan again shortly.
	if _network != null:
		var kerb := _network.nearest_kerb(destination)
		if kerb >= 0 and kerb != _target_node:
			_target_node = kerb
			return
	_replan_timer = minf(_replan_timer, 0.0)


func _pick_initial_target() -> void:
	super()
	if _route.is_empty() and destination != Vector3.ZERO:
		_plan()


func _plan() -> void:
	_replan_timer = REPLAN_INTERVAL
	var car := get_car()
	if _network == null or car == null or not _network.is_ready():
		return
	var from_node := _network.nearest_node(car.global_position, -car.global_transform.basis.z)
	var to_node := _network.nearest_kerb(destination)
	if from_node < 0 or to_node < 0:
		return
	_route = _network.path_between(from_node, to_node)
	_leg = 0
	if not _route.is_empty():
		_advance_target()
