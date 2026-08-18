class_name EmployeeAI
extends Pedestrian
## The member of staff standing behind the counter.
##
## Only exists while the player is in the shop — when they are not, the same
## employee works as a line in the far simulation. Their job here is to walk in,
## stand in the right place and be visibly present; the actual serving is
## CustomerSpawner's, because a queue has to be served the same way whether an
## employee or the player is on the till.

enum Stage { ARRIVING, TAKING_POST, WORKING, LEAVING }

## How close to the station counts as being at it.
@export var station_tolerance: float = 1.3

var employee: EmployeeData = null
var stage: Stage = Stage.ARRIVING

var _unit: RetailUnit = null
var _station: Vector3 = Vector3.ZERO
## The end of the counter they walk round to get behind it. Going straight at
## the staff side means walking into the counter and stopping there.
var _approach: Vector3 = Vector3.ZERO
var _exit_point: Vector3 = Vector3.ZERO
var _facing: Vector3 = Vector3.FORWARD
var _repaths: int = 0


func setup(worker: EmployeeData, unit: RetailUnit, entry: Vector3, exit_point: Vector3) -> void:
	employee = worker
	_unit = unit
	_exit_point = exit_point
	wanders = false
	body_color = Color(0.318, 0.396, 0.502)
	accent_color = Color(0.204, 0.259, 0.337)
	global_position = entry
	_refresh_station()
	_go_to(_approach)


func is_at_station() -> bool:
	return stage == Stage.WORKING


## Told to go home. They walk out rather than blinking away.
func end_shift() -> void:
	if stage == Stage.LEAVING:
		return
	stage = Stage.LEAVING
	set_running(false)
	_go_to(_exit_point)


func _process(delta: float) -> void:
	# Knocked down or frightened: an ordinary civilian again until it passes.
	if state != State.IDLE and state != State.WALKING:
		super._process(delta)
		return

	match stage:
		Stage.ARRIVING:
			_refresh_station()
			if _reached(_approach):
				stage = Stage.TAKING_POST
				_go_to(_station)
		Stage.TAKING_POST:
			if _reached(_station):
				stage = Stage.WORKING
				stop()
				_face_the_shop()
		Stage.WORKING:
			_refresh_station()
			if global_position.distance_to(_station) > station_tolerance * 1.6:
				# The counter moved, or they were shoved off it.
				stage = Stage.ARRIVING
				_go_to(_approach)
			else:
				_face_the_shop()
		Stage.LEAVING:
			if _reached(_exit_point):
				queue_free()


## Behind the till, on the staff side, looking out at the queue.
func _refresh_station() -> void:
	if _unit == null:
		return
	var till := _unit.first_checkout()
	if till == null:
		return
	_station = till.staff_point()
	_approach = till.staff_approach_from(global_position)
	_facing = (till.service_point() - _station).normalized()


func _face_the_shop() -> void:
	if _facing.length_squared() < 0.01 or body_pivot == null:
		return
	body_pivot.rotation.y = atan2(_facing.x, _facing.z)


func _go_to(point: Vector3) -> void:
	_repaths = 0
	if not walk_to(point):
		global_position = global_position.move_toward(point, 0.2)


func _reached(point: Vector3) -> bool:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() <= station_tolerance:
		return true
	if has_path():
		return false
	# Same rule as the customers: a few attempts, then near enough is here.
	_repaths += 1
	if _repaths > 3:
		stop()
		return true
	walk_to(point)
	return false
