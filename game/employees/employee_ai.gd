class_name EmployeeAI
extends Pedestrian
## A member of staff, on the floor.
##
## Only exists while the player is in the shop — out of sight the same employee
## is a line in the far simulation, which is why walking out does not stop them
## working. What they do here depends on their role: whoever is on the counter
## stands behind it and is served by CustomerSpawner, and a stocker walks the
## floor moving stock out of the back.
##
## The serving itself is deliberately not here. A queue has to be served the same
## way whether an employee or the player is on the till, so that lives in one
## place and this only decides where somebody stands.

enum Stage { ARRIVING, TAKING_POST, WORKING, RESTOCKING, LEAVING }

## How close to the station counts as being at it.
@export var station_tolerance: float = 1.3
## Seconds a stocker spends at each end of the trip.
@export var handling_seconds: float = 1.4
## Units a stocker carries in one trip.
@export var carry_units: int = 6

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
## Stocker: whether they have an armful, and how long they stand still handling
## it at each end of the trip.
var _carrying: bool = false
var _handling: float = 0.0
var _target_shelf: BusinessEquipment = null


func setup(worker: EmployeeData, unit: RetailUnit, entry: Vector3, exit_point: Vector3) -> void:
	employee = worker
	_unit = unit
	_exit_point = exit_point
	wanders = false
	# Restyled rather than tinted: staff are built before they are told which
	# role they are working, and a barista and a stocker are different uniforms
	# rather than the same figure in a different colour.
	restyle(_colour_for_role(), Color(0.918, 0.906, 0.878), CharacterLook.Category.RETAIL)
	global_position = entry
	_refresh_station()
	_go_to(_approach)


## Staff are told apart at a glance: the till, the machine, the floor, the boss.
func _colour_for_role() -> Color:
	if employee == null:
		return Color(0.318, 0.396, 0.502)
	match employee.role:
		EmployeeData.Role.BARISTA:
			return Color(0.400, 0.290, 0.220)
		EmployeeData.Role.STOCKER:
			return Color(0.290, 0.400, 0.310)
		EmployeeData.Role.MANAGER:
			return Color(0.361, 0.290, 0.451)
		_:
			return Color(0.318, 0.396, 0.502)


func is_at_station() -> bool:
	return stage == Stage.WORKING or stage == Stage.RESTOCKING


func is_stocker() -> bool:
	return employee != null and employee.role == EmployeeData.Role.STOCKER


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
				stage = Stage.RESTOCKING if is_stocker() else Stage.WORKING
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
		Stage.RESTOCKING:
			_tick_restocking(delta)
		Stage.LEAVING:
			if _reached(_exit_point):
				queue_free()


# --- Stocking ------------------------------------------------------------

## Back and forth: fetch an armful from the store room, carry it to a shelf that
## needs it, put it out. The stock actually moves when they reach the shelf —
## watching a stocker walk about while the shelves fill themselves elsewhere
## would be a lie, so the hourly simulation stands down while they are visible.
func _tick_restocking(delta: float) -> void:
	if _handling > 0.0:
		_handling -= delta
		stop()
		return

	var business := _unit.get_business() if _unit != null else null
	if business == null:
		return

	if not _carrying:
		if _reached(_store_room_point()):
			_carrying = true
			_handling = handling_seconds
			_target_shelf = _shelf_needing_stock(business)
		return

	if _target_shelf == null or not is_instance_valid(_target_shelf):
		_target_shelf = _shelf_needing_stock(business)
		if _target_shelf == null:
			# Nothing to do: wait by the store room rather than pacing.
			_carrying = false
			_handling = handling_seconds * 2.0
			_go_to(_store_room_point())
			return
		_go_to(_target_shelf.approach_point_from(global_position))
		return

	if not _reached(_target_shelf.approach_point_from(global_position)):
		return

	var wanted := _target_shelf.placed.stock_item
	if wanted == &"" or business.storage_of(wanted) <= 0:
		wanted = _fullest_line(business)
	if wanted != &"":
		business.stock_shelf(_target_shelf.slot_id(), wanted, carry_units)
		if employee != null:
			employee.add_experience(0.05)
	_carrying = false
	_handling = handling_seconds
	_target_shelf = null
	_go_to(_store_room_point())


func _shelf_needing_stock(business: BusinessInstance) -> BusinessEquipment:
	var emptiest: BusinessEquipment = null
	var lowest := INF
	for shelf in _unit.shelf_nodes():
		if shelf.placed == null or shelf.placed.room_left() <= 0:
			continue
		var level := float(shelf.placed.stock_quantity)
		if level < lowest:
			lowest = level
			emptiest = shelf
	return emptiest if business.storage_used() > 0 else null


func _fullest_line(business: BusinessInstance) -> StringName:
	var best: StringName = &""
	var most := 0
	for item in business.catalogue():
		var held := business.storage_of(item.id)
		if held > most:
			most = held
			best = item.id
	return best


## Where the stock is kept: the storage unit if there is one, otherwise the back
## of the room.
func _store_room_point() -> Vector3:
	if _unit == null:
		return global_position
	for node in _unit.equipment_nodes():
		if node.placed != null and node.placed.is_storage():
			return node.approach_point_from(global_position)
	return _unit.to_global(Vector3(0.0, 0.0, _unit.storage_area.get_center().y))


# --- Where they stand ----------------------------------------------------

## Behind whatever they work at, looking out at the customers.
func _refresh_station() -> void:
	if _unit == null:
		return
	var post := _workstation()
	if post == null:
		return
	_station = post.staff_point()
	_approach = post.staff_approach_from(global_position)
	_facing = (post.service_point() - _station).normalized()


## The thing this role stands behind. A barista wants the machine and falls back
## to the counter; everybody else wants the counter.
func _workstation() -> BusinessEquipment:
	if employee != null and employee.role == EmployeeData.Role.BARISTA:
		for node in _unit.equipment_nodes():
			if node.placed != null and node.placed.data() != null and node.placed.data().is_workstation():
				return node
	return _unit.first_checkout()


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


## What a member of staff looks like they are doing. The base walker decides
## from speed alone, which is right while they are crossing the shop and wrong
## the moment they reach the till: somebody stood at a counter should be leaning
## over it with their hands in front of them, not standing to attention.
func animation_state() -> CharacterAnimator.State:
	match stage:
		Stage.WORKING:
			return CharacterAnimator.State.WORK
		Stage.RESTOCKING:
			# Carrying stock to a shelf, or reaching up to fill it.
			return (
				CharacterAnimator.State.CARRY if _handling > 0.0
				else super.animation_state()
			)
		_:
			return super.animation_state()
