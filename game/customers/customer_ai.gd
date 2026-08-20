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

enum Stage { ARRIVING, BROWSING, QUEUEING, PAYING, WAITING, LEAVING, DONE }

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
		Stage.LEAVING:
			if _arrived():
				_finish()
		_:
			pass


# --- Stages --------------------------------------------------------------

## Where the two kinds of business part company. In a shop the customer walks
## the aisles and picks things up; at a counter they read the board and order.
func _begin_shopping() -> void:
	if _prepared:
		_order_from_the_counter()
		return
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
	stage = Stage.LEAVING
	set_running(false)
	_go_to(_exit_point)


func _finish() -> void:
	stage = Stage.DONE
	finished.emit(self)
	queue_free()


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
