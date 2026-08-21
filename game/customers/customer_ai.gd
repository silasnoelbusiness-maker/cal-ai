class_name CustomerAI
extends Pedestrian
## Somebody who came in to buy something.
##
## A Pedestrian first and a customer second: they can be knocked down, they can
## witness a crime, and they run from a wanted player like anyone else. When any
## of that happens the shopping is abandoned and the ordinary civilian behaviour
## takes over — which is why this overrides `_process` rather than replacing the
## state machine underneath it.
##
## What they want and whether they will pay for it is CustomerDemand's business,
## not this file's. All that happens here is the walking about.

signal finished(customer: CustomerAI)

## Appended to as Phase O added routes through a building. The first seven are
## the shop and the coffee counter and behave exactly as they did.
enum Stage {
	ARRIVING, BROWSING, QUEUEING, PAYING, WAITING, LEAVING, DONE,
	SEEKING_SEAT, SEATED, AWAITING_FOOD, EATING,
	CHECKING_IN, EXERCISING, AT_THE_DOOR, IN_THE_ROOM,
}

## How long they stand at a shelf deciding.
@export var browse_seconds: float = 1.6
## How long they will stand in a queue nobody is serving before giving up.
@export var patience_seconds: float = 22.0
@export var arrive_distance: float = 1.4

var stage: Stage = Stage.ARRIVING
var basket: Array[ItemData] = []

var _business: BusinessInstance = null
var _spawner: CustomerSpawner = null
var _unit: RetailUnit = null
var _shopping_list: Array[ItemData] = []
var _target: Vector3 = Vector3.ZERO
var _timer: float = 0.0
var _waited: float = 0.0
var _exit_point: Vector3 = Vector3.ZERO
var _threshold: Vector3 = Vector3.ZERO
var _queue_slot: int = -1
## How many times the walk to the current target has been restarted. A shop
## floor full of shelves can leave somebody with no clear line to where they are
## going; after a few attempts, near enough is where they stand.
var _repaths: int = 0
## The item they are currently walking to a shelf to pick up.
var _pending_item: ItemData = null
var _own_rng := RandomNumberGenerator.new()
## Whether this business makes what it sells. A coffee shop has nothing to
## browse: the menu is on the wall, so they queue, order, and wait for it.
var _prepared: bool = false
## Seconds left of watching their drink being made.
var _collection_wait: float = 0.0
## Which route through the building this business puts people on, from its
## operating model. The customer walks a restaurant differently from a shop,
## and the type is what knows the difference.
var _route: StringName = &"retail"
## Who they are, which decides how much the price and the wait bother them.
var archetype: StringName = &"worker"
## The table, machine or stretch of floor they are occupying.
var _spot: BusinessEquipment = null
## The ticket they are waiting on, in a restaurant.
var _order: KitchenOrder = null
## Machines used so far, so a gym visit is one or two rather than all night.
var _stations_used: int = 0


func setup(
	business: BusinessInstance, unit: RetailUnit, spawner: CustomerSpawner,
	threshold: Vector3, exit_point: Vector3, rng: RandomNumberGenerator
) -> void:
	# A customer is inside a shop with something to do, so they are never put
	# to sleep for being far from the player: that is exactly when the shop
	# needs its floor running.
	ambient_crowd = false
	_business = business
	_unit = unit
	_spawner = spawner
	_threshold = threshold
	_exit_point = exit_point
	_own_rng.seed = rng.randi()
	wanders = false
	_prepared = business.serves_prepared_goods()
	_route = business.model().customer_route()
	archetype = CustomerArchetype.pick(business, _own_rng)
	patience_seconds *= CustomerArchetype.patience(archetype)

	# Decided on the way in, like a real shopping list: what they came for is
	# not affected by what they find.
	for i in CustomerDemand.basket_size(business, _own_rng):
		var item := CustomerDemand.pick_wanted_item(business, _own_rng)
		if item != null and not _shopping_list.has(item):
			_shopping_list.append(item)
	_go_to(_threshold)


func is_waiting_for_order() -> bool:
	return stage == Stage.WAITING


func wanted_items() -> Array[ItemData]:
	return _shopping_list.duplicate()


func is_queueing() -> bool:
	return stage == Stage.QUEUEING


func set_queue_slot(slot: int, position: Vector3) -> void:
	_queue_slot = slot
	if stage == Stage.QUEUEING:
		_go_to(position)


## Called by whoever is on the till. Rings the basket through and sends them out.
func serve(server: EmployeeData = null) -> int:
	if stage != Stage.QUEUEING and stage != Stage.PAYING:
		return 0
	stage = Stage.PAYING
	var revenue := 0
	var wait := 0.0
	for item in basket:
		if _business.record_sale(item, 1) <= 0:
			continue
		revenue += _business.price_of(item)
		wait += _business.preparation_seconds(item, server)
	if revenue > 0:
		_business.add_satisfaction(0.15 if _waited < patience_seconds * 0.4 else 0.05)
	else:
		# Somebody else got the last one while they queued.
		_business.record_lost_sale()
		_business.add_satisfaction(-0.3)
	basket.clear()

	if _spawner != null:
		_spawner.leave_queue(self)
	# A drink has to be made. They stand aside and wait for it rather than
	# holding up the queue, which is what a coffee shop actually looks like.
	if wait > 0.0:
		stage = Stage.WAITING
		_collection_wait = wait
		stop()
		return revenue
	_leave()
	return revenue


func _process(delta: float) -> void:
	# Frightened, knocked down or fleeing: they are a civilian again, and the
	# shopping is over.
	if state != State.IDLE and state != State.WALKING:
		super._process(delta)
		if stage != Stage.DONE and stage != Stage.LEAVING:
			_abandon("scared")
		return

	if _business == null:
		return

	_timer -= delta
	match stage:
		Stage.ARRIVING:
			if _arrived():
				_begin_shopping()
		Stage.BROWSING:
			_tick_browsing()
		Stage.QUEUEING:
			_tick_queueing(delta)
		Stage.WAITING:
			_collection_wait -= delta
			if _collection_wait <= 0.0:
				_leave()
		Stage.SEEKING_SEAT:
			_tick_seeking_seat(delta)
		Stage.SEATED:
			_tick_seated()
		Stage.AWAITING_FOOD:
			_tick_awaiting_food(delta)
		Stage.EATING:
			if _timer <= 0.0:
				_finish_meal()
		Stage.CHECKING_IN:
			_tick_checking_in(delta)
		Stage.EXERCISING:
			_tick_exercising()
		Stage.AT_THE_DOOR:
			_tick_at_the_door(delta)
		Stage.IN_THE_ROOM:
			_tick_in_the_room()
		Stage.LEAVING:
			if _arrived():
				_finish()
		_:
			pass


# --- Stages --------------------------------------------------------------

## Where the two kinds of business part company. In a shop the customer walks
## the aisles and picks things up; at a counter they read the board and order.
func _begin_shopping() -> void:
	match _route:
		&"table":
			_seek_a_table()
		&"membership":
			_go_to_reception()
		&"venue":
			_join_the_door()
		&"counter":
			_order_from_the_counter()
		_:
			stage = Stage.BROWSING
			_timer = 0.0
			_next_shelf()


## Everything they want that the shop can actually make and they will pay for,
## decided at the counter rather than at a shelf.
func _order_from_the_counter() -> void:
	for item in _shopping_list:
		if _business.available_units(item) <= 0:
			_business.record_lost_sale()
			_business.add_satisfaction(-0.2)
			continue
		if not CustomerDemand.will_buy(_business, item, _own_rng):
			_business.add_satisfaction(-0.15)
			continue
		basket.append(item)
	_shopping_list.clear()

	if basket.is_empty():
		_abandon("nothing they wanted")
		return
	_join_queue()


## Walks to a shelf holding the next thing on the list. Nothing on the list left
## in stock ends the trip — with a lost sale if they came for something specific.
func _next_shelf() -> void:
	while not _shopping_list.is_empty():
		var item: ItemData = _shopping_list.pop_front()
		var shelf := _find_shelf_with(item)
		if shelf == null:
			# Came in for it, shop has not got it.
			_business.record_lost_sale()
			_business.add_satisfaction(-0.2)
			continue
		if not CustomerDemand.will_buy(_business, item, _own_rng):
			# Seen the price and thought better of it.
			_business.add_satisfaction(-0.15)
			continue
		_pending_item = item
		_go_to(shelf.approach_point_from(global_position))
		_timer = browse_seconds + _own_rng.randf_range(0.0, 0.8)
		return

	if basket.is_empty():
		_abandon("empty handed")
		return
	_join_queue()


func _tick_browsing() -> void:
	if not _arrived():
		return
	# Standing at the shelf, deciding, then reaching for it.
	if _timer > 0.0:
		stop()
		return
	if _pending_item != null:
		# Only take what is really there — the shelf may have emptied while they
		# walked over, which is a lost sale rather than a phantom one.
		if _business.shelf_stock_of(_pending_item.id) > 0:
			basket.append(_pending_item)
		else:
			_business.record_lost_sale()
			_business.add_satisfaction(-0.25)
		_pending_item = null
	_next_shelf()


func _join_queue() -> void:
	stage = Stage.QUEUEING
	_waited = 0.0
	if _spawner == null or not _spawner.join_queue(self):
		# No till, or the queue is out of the door.
		_abandon("no till")


func _tick_queueing(delta: float) -> void:
	_waited += delta
	if _waited < patience_seconds:
		return
	# Nobody served them. This is the cost of running a shop with no cashier.
	_business.record_lost_sale()
	_business.add_satisfaction(-0.6)
	_abandon("waited too long")


## Gives up on the visit. The lost sale, if any, has already been recorded by
## whoever decided to give up.
func _abandon(_reason: String) -> void:
	basket.clear()
	_leave()


func _leave() -> void:
	if _spawner != null:
		_spawner.leave_queue(self)
		_spawner.leave_entry_queue(self)
	# Whatever they were sitting on, standing on or using goes back to the
	# floor the moment they head for the door, rather than when they reach it.
	_release_spot()
	if _order != null:
		_order.stage = KitchenOrder.Stage.ABANDONED
		_order = null
	stage = Stage.LEAVING
	set_running(false)
	_go_to(_exit_point)


func _exit_tree() -> void:
	# A customer freed mid-visit must not leave a table booked forever.
	_release_spot()


func _finish() -> void:
	stage = Stage.DONE
	finished.emit(self)
	queue_free()



# --- Table service -------------------------------------------------------

## A restaurant begins with a question a shop never asks: is there anywhere to
## sit? Everything else waits on the answer.
func _seek_a_table() -> void:
	var seat := _free_spot(EquipmentData.Role.SEATING)
	if seat == null:
		# The floor is full. They will hover by the door for a little while,
		# because a full restaurant is worth a short wait and not a long one.
		stage = Stage.SEEKING_SEAT
		_waited = 0.0
		_go_to(_threshold)
		return
	_take_spot(seat)
	stage = Stage.SEEKING_SEAT
	_go_to(seat.approach_point_from(global_position))


func _tick_seeking_seat(delta: float) -> void:
	if _spot != null:
		if _arrived():
			stage = Stage.SEATED
			stop()
		return
	# Waiting for a table to come free.
	_waited += delta
	var seat := _free_spot(EquipmentData.Role.SEATING)
	if seat != null:
		_take_spot(seat)
		_go_to(seat.approach_point_from(global_position))
		return
	if _waited >= patience_seconds * 0.5:
		_business.record_lost_sale(LostReason.NO_SEATING)
		_business.add_satisfaction(-0.35)
		_abandon("no table")


## Sitting down, reading the menu, deciding. The ticket goes in from here.
func _tick_seated() -> void:
	var dish := _pick_dish()
	if dish == null:
		_business.record_lost_sale(LostReason.NO_STOCK)
		_business.add_satisfaction(-0.3)
		_abandon("nothing on")
		return
	_order = _business.place_order(self, dish, TimeManager.total_minutes)
	stage = Stage.AWAITING_FOOD
	_waited = 0.0
	stop()


## Something on the menu the kitchen can make and they will pay for.
func _pick_dish() -> ItemData:
	for item in _shopping_list:
		if _business.available_units(item) > 0 and CustomerDemand.will_buy(
			_business, item, _own_rng, archetype
		):
			return item
	var fallback := CustomerDemand.pick_item(_business, _own_rng)
	if fallback != null and CustomerDemand.will_buy(_business, fallback, _own_rng, archetype):
		return fallback
	return null


func _tick_awaiting_food(delta: float) -> void:
	_waited += delta
	if _order == null:
		_abandon("order lost")
		return
	if _order.stage == KitchenOrder.Stage.DELIVERED:
		# The plate arrived. They pay for it and eat it.
		var paid := _business.record_prepared_sale(_order.recipe, 1)
		var wait_share := clampf(_waited / maxf(patience_seconds, 1.0), 0.0, 1.0)
		_business.add_satisfaction(0.16 if wait_share < 0.5 else 0.04)
		_order = null
		stage = Stage.EATING
		_timer = 6.0 + _own_rng.randf_range(0.0, 4.0)
		if paid <= 0:
			_finish_meal()
		return
	if _waited < patience_seconds:
		return
	# Nobody cooked it, or nobody carried it. Either way they leave hungry, and
	# the kitchen keeps whatever it already spent on them.
	_order.stage = KitchenOrder.Stage.ABANDONED
	_order = null
	_business.record_lost_sale(LostReason.SERVICE_TOO_SLOW)
	_business.add_satisfaction(-0.6)
	_abandon("waited too long for food")


func _finish_meal() -> void:
	_release_spot()
	_leave()


# --- Memberships ---------------------------------------------------------

func _go_to_reception() -> void:
	var desk := _first_of_role(EquipmentData.Role.RECEPTION)
	stage = Stage.CHECKING_IN
	_waited = 0.0
	if desk == null:
		# No desk to check in at, so nothing is sold and nobody is signed up.
		_business.record_lost_sale(LostReason.NO_STAFF)
		_abandon("no reception")
		return
	_go_to(desk.approach_point_from(global_position))


func _tick_checking_in(delta: float) -> void:
	_waited += delta
	if not _arrived() and _waited < patience_seconds:
		return
	# The money is the operating model's business, and it is the same call the
	# far simulation makes — which is what stops a gym earning differently
	# depending on whether anybody is watching it.
	var result := _business.model().serve_one(_business, TimeManager.hour, _own_rng)
	if not result.served:
		_business.record_lost_sale(result.lost_reason)
	_business.add_satisfaction(result.satisfaction)
	_start_exercise()


func _start_exercise() -> void:
	_release_spot()
	var machine := _free_spot(EquipmentData.Role.MACHINE)
	if machine == null:
		_business.record_lost_sale(LostReason.BUSINESS_FULL)
		_abandon("everything busy")
		return
	_take_spot(machine)
	_stations_used += 1
	stage = Stage.EXERCISING
	_timer = 9.0 + _own_rng.randf_range(0.0, 7.0)
	_go_to(machine.approach_point_from(global_position))


func _tick_exercising() -> void:
	if not _arrived():
		return
	stop()
	if _timer > 0.0:
		return
	# One more machine, or a shower and out. Two is a workout; six is a life.
	if _stations_used < 2 and _own_rng.randf() < 0.55:
		_start_exercise()
		return
	_release_spot()
	_leave()


# --- The venue -----------------------------------------------------------

func _join_the_door() -> void:
	stage = Stage.AT_THE_DOOR
	_waited = 0.0
	if _spawner == null or not _spawner.join_entry_queue(self):
		_business.record_lost_sale(LostReason.QUEUE_TOO_LONG)
		_abandon("queue round the block")


func _tick_at_the_door(delta: float) -> void:
	_waited += delta
	if _waited < patience_seconds * 1.6:
		return
	# A queue is part of a night out; an hour of one is not.
	if _spawner != null:
		_spawner.leave_entry_queue(self)
	_business.record_lost_sale(LostReason.QUEUE_TOO_LONG)
	_business.add_satisfaction(-0.3)
	_abandon("gave up at the door")


## Called by the door when they are let in.
func admit() -> void:
	if stage != Stage.AT_THE_DOOR:
		return
	var result := _business.model().serve_one(_business, TimeManager.hour, _own_rng)
	if not result.served:
		_business.record_lost_sale(result.lost_reason)
	_business.add_satisfaction(result.satisfaction)

	var spot := _free_spot(EquipmentData.Role.DANCE_FLOOR)
	if spot == null:
		spot = _free_spot(EquipmentData.Role.SEATING)
	if spot == null:
		_business.record_lost_sale(LostReason.BUSINESS_FULL)
		_abandon("nowhere to stand")
		return
	_take_spot(spot)
	stage = Stage.IN_THE_ROOM
	_timer = 20.0 + _own_rng.randf_range(0.0, 25.0)
	_go_to(spot.approach_point_from(global_position))


func _tick_in_the_room() -> void:
	if not _arrived():
		return
	stop()
	if _timer > 0.0:
		return
	_release_spot()
	_leave()


# --- Places ---------------------------------------------------------------

## The nearest piece of the given kind with room on it.
func _free_spot(role: int) -> BusinessEquipment:
	if _unit == null:
		return null
	var best: BusinessEquipment = null
	var best_distance := INF
	for node in _unit.equipment_nodes():
		if not node.is_role(role) or not node.has_room():
			continue
		var distance := global_position.distance_squared_to(node.global_position)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func _first_of_role(role: int) -> BusinessEquipment:
	if _unit == null:
		return null
	for node in _unit.equipment_nodes():
		if node.is_role(role):
			return node
	return null


func _take_spot(node: BusinessEquipment) -> void:
	_release_spot()
	if node != null and node.take_slot():
		_spot = node


func _release_spot() -> void:
	if _spot != null and is_instance_valid(_spot):
		_spot.release_slot()
	_spot = null


# --- Helpers -------------------------------------------------------------

func _find_shelf_with(item: ItemData) -> BusinessEquipment:
	if _unit == null:
		return null
	for shelf in _unit.shelf_nodes():
		if shelf.placed != null and shelf.placed.stock_item == item.id and shelf.placed.stock_quantity > 0:
			return shelf
	return null


func _go_to(point: Vector3) -> void:
	_target = point
	_repaths = 0
	if not walk_to(point):
		global_position = global_position.move_toward(point, 0.1)


func _arrived() -> bool:
	var offset := _target - global_position
	offset.y = 0.0
	if offset.length() <= arrive_distance:
		stop()
		return true
	if has_path():
		return false

	# The route ran out short of the target — either it finished early or the
	# walker wedged and gave up on it. One more attempt in a straight line, and
	# after a few of those, standing near the thing counts as reaching it.
	_repaths += 1
	if _repaths > 3:
		stop()
		return true
	walk_to(_target)
	return false
