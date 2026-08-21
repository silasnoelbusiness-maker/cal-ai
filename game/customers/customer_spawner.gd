class_name CustomerSpawner
extends Node3D
## Brings customers into one shop, and runs the till they queue at.
##
## Lives inside the unit it serves. It only produces visible customers while the
## player is in the shop — the rest of the time BusinessManager trades the same
## number of customers as numbers, at the same rate, from the same rules. See
## `_on_minute_passed`, which is deliberately the mirror of the far simulation.

signal customer_spawned(customer: CustomerAI)
signal sale_completed(customer: CustomerAI, revenue: int)

## Hard ceiling on how many are on the floor at once, whatever the property
## allows, so a busy shop stays cheap to run.
@export var max_active_customers: int = 10
## Metres between people in the queue.
@export var queue_spacing: float = 1.5
## Seconds the player takes to ring one customer through. Slower than a good
## employee and faster than a bad one, so hiring is a real decision.
@export var player_checkout_seconds: float = 2.0
## How close the player has to stand to the till to be working it.
@export var register_range: float = 3.0

var _unit: RetailUnit = null
var _business: BusinessInstance = null
var _customers: Array[CustomerAI] = []
var _queue: Array[CustomerAI] = []
var _pending: float = 0.0
var _serve_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _player_register: BusinessEquipment = null
## The rope outside a venue. Same structure as the till queue, different door.
var _door_queue := ServiceQueue.new()
var _door_timer: float = 0.0
## Seconds until the kitchen and the floor are looked at again.
var _kitchen_timer: float = 0.0
var _arrival: Marker3D = null
var _threshold: Marker3D = null
var _spawn_count: int = 0


func _ready() -> void:
	_rng.randomize()
	_unit = get_parent() as RetailUnit
	if _unit == null:
		push_error("CustomerSpawner must be a child of a RetailUnit.")
		set_process(false)
		return
	_arrival = _unit.get_node_or_null("CustomerArrival")
	_threshold = _unit.get_node_or_null("Threshold")
	TimeManager.minute_passed.connect(_on_minute_passed)


## Everybody still on the floor, dropping anybody who has been freed.
##
## Rebuilt with a loop rather than `filter`: a freed object cannot be passed to a
## typed lambda parameter, so filtering a list that may contain one fails at
## exactly the moment it is most needed.
func active_customers() -> Array[CustomerAI]:
	var live: Array[CustomerAI] = []
	for customer in _customers:
		if is_instance_valid(customer):
			live.append(customer)
	_customers = live
	return live.duplicate()


func queue_length() -> int:
	var waiting: Array[CustomerAI] = []
	for customer in _queue:
		if is_instance_valid(customer):
			waiting.append(customer)
	_queue = waiting
	return _queue.size()


func is_player_working_register() -> bool:
	return _player_register != null and is_instance_valid(_player_register)


## Toggled by interacting with a checkout counter. Standing at the till is a
## state rather than a screen: the player walks away and it ends.
func toggle_player_at_register(equipment: BusinessEquipment) -> void:
	if _player_register == equipment:
		_player_register = null
		GameManager.notify("LEFT THE REGISTER", GameManager.Tone.INFO)
		return
	_player_register = equipment
	GameManager.notify("WORKING THE REGISTER", GameManager.Tone.GOOD)


func stop_player_working() -> void:
	_player_register = null


# --- Spawning ------------------------------------------------------------

## The near half of the simulation. Same arrival rate as the far half — both are
## CustomerDemand.customers_per_hour spread across the hour — so which one is
## running never changes what a shop earns.
func _on_minute_passed(hour: int, _minute: int) -> void:
	_business = _unit.get_business()
	if _business == null or not _unit.is_player_inside():
		return
	# Whether or not anybody comes in, this minute is now accounted for, so the
	# far simulation does not bill it again when the player walks out.
	BusinessManager.note_visible_trade(_business)
	if not _business.is_open():
		return
	_pending += CustomerDemand.customers_per_hour(_business, hour) / 60.0
	while _pending >= 1.0:
		_pending -= 1.0
		_spawn_one()


## Puts one customer on the pavement outside, now. The rate-driven path and the
## debug key both go through here, and so do the tests.
func spawn_customer_now() -> CustomerAI:
	_business = _unit.get_business()
	if _business == null:
		return null
	return _spawn_one()


## How many will fit inside. The operating model decides — seats in a
## restaurant, machines in a gym, floor in a venue, and the room itself in a
## shop — and the hard ceiling above is only there to protect the frame rate.
func capacity() -> int:
	# Resolved rather than assumed: the business is normally set by the minute
	# tick, and anything asking before the player has walked in — a screen, a
	# test — would otherwise be told the hard ceiling instead of the truth.
	var business := _business if _business != null else _unit.get_business()
	if business == null:
		return max_active_customers
	return mini(business.model().customer_capacity(business), max_active_customers)


func queue_limit() -> int:
	return _business.queue_capacity() if _business != null else 4


func _spawn_one() -> CustomerAI:
	if active_customers().size() >= capacity():
		return null
	if _arrival == null or _threshold == null:
		return null

	var customer := CustomerAI.new()
	_spawn_count += 1
	customer.name = "Customer%d" % _spawn_count
	customer.body_color = _customer_colour()
	customer.accent_color = customer.body_color.darkened(0.3)
	add_child(customer)
	customer.global_position = _arrival.global_position + Vector3(
		_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(-1.0, 1.0)
	)
	customer.setup(
		_business, _unit, self,
		_threshold.global_position, _arrival.global_position, _rng
	)
	customer.finished.connect(_on_customer_finished)
	_customers.append(customer)
	_business.record_customer_visit()
	customer_spawned.emit(customer)
	return customer


func _customer_colour() -> Color:
	const PALETTE: Array[Color] = [
		Color(0.549, 0.396, 0.353), Color(0.400, 0.451, 0.510),
		Color(0.427, 0.475, 0.400), Color(0.596, 0.545, 0.427),
		Color(0.478, 0.404, 0.494), Color(0.353, 0.478, 0.494),
	]
	return PALETTE[_rng.randi_range(0, PALETTE.size() - 1)]


func _on_customer_finished(customer: CustomerAI) -> void:
	_customers.erase(customer)
	_queue.erase(customer)
	_reposition_queue()


# --- The queue -----------------------------------------------------------

func _checkout() -> BusinessEquipment:
	return _unit.first_checkout()


## Joins the back of the line. Refused when there is no till at all, or when the
## line is already out of the door — which is a lost sale the caller records.
func join_queue(customer: CustomerAI) -> bool:
	var till := _checkout()
	if till == null:
		return false
	if queue_length() >= queue_limit():
		_business.record_lost_sale()
		_business.add_satisfaction(-0.4)
		return false
	_queue.append(customer)
	_reposition_queue()
	return true


func leave_queue(customer: CustomerAI) -> void:
	if _queue.has(customer):
		_queue.erase(customer)
		_reposition_queue()


# --- The door ------------------------------------------------------------

## The queue outside a venue. Longer than a shop's, because standing in one is
## part of the evening, and worked by security rather than by a till.
func join_entry_queue(customer: CustomerAI) -> bool:
	if _threshold == null:
		return false
	_door_queue.prune()
	var post := _unit.first_of_role(EquipmentData.Role.SECURITY_POST)
	var head := post.service_point() if post != null else _threshold.global_position
	var back := (head - _unit.global_position).normalized()
	_door_queue.configure(head, back, door_limit(), queue_spacing)
	if not _door_queue.join(customer):
		return false
	_reposition_door()
	return true


func leave_entry_queue(customer: CustomerAI) -> void:
	if _door_queue.leave(customer):
		_reposition_door()


func door_queue_length() -> int:
	_door_queue.prune()
	return _door_queue.size()


## How long a line the venue will let build before people stop joining it.
func door_limit() -> int:
	if _business == null:
		return 6
	var security := _business.rostered_all(EmployeeData.Role.SECURITY, TimeManager.hour).size()
	# Somebody working the door is what makes a long queue orderly rather than
	# a crowd, so it is what lets the line grow.
	return maxi(_business.queue_capacity() + security * 4, 3)


func _reposition_door() -> void:
	for who in _door_queue.members():
		var customer := who as CustomerAI
		if customer != null and is_instance_valid(customer):
			customer.set_queue_slot(
				_door_queue.place_of(customer), _door_queue.position_of(customer)
			)


## Lets people in as fast as the door can work and as the room allows.
func _work_the_door(delta: float) -> void:
	if _business == null or _door_queue.is_empty():
		return
	_door_queue.prune()
	_door_timer -= delta
	if _door_timer > 0.0:
		return
	var model := _business.model()
	var inside := 0
	for customer in active_customers():
		if customer.stage == CustomerAI.Stage.IN_THE_ROOM:
			inside += 1
	if inside >= model.customer_capacity(_business):
		# Full. The rope stays across, which is the queue doing its job.
		_door_timer = 1.5
		return
	var security := _business.rostered_all(EmployeeData.Role.SECURITY, TimeManager.hour)
	# Unworked, the door still moves — slowly, and to a smaller room.
	_door_timer = 1.2 if security.is_empty() else 0.45
	var next := _door_queue.take_front() as CustomerAI
	_reposition_door()
	if next != null and is_instance_valid(next):
		next.admit()


# --- The kitchen ---------------------------------------------------------

## Tickets, cooks and the walk to the table.
##
## The one part of the game where three people have to co-operate to make a
## sale: whoever sat down, whoever is on the stove and whoever carries it. Any
## of the three missing and the order sits there, which is exactly what the
## player should be able to see happening.
func _work_the_kitchen(delta: float) -> void:
	if _business == null or _business.kitchen.is_empty():
		return
	_kitchen_timer -= delta
	if _kitchen_timer > 0.0:
		return
	_kitchen_timer = 0.4

	var hour := TimeManager.hour
	var now := TimeManager.total_minutes
	var model := _business.model() as TableServiceModel

	# Anybody who walked out takes their ticket with them.
	for order in _business.kitchen:
		if order.is_open() and order.customer_is_gone():
			order.stage = KitchenOrder.Stage.ABANDONED

	var cook := _cook_at_the_stove(hour)
	if cook != null:
		var ticket := _business.next_unstarted_order()
		if ticket != null:
			# Nothing is charged for yet — this is the food being taken out of
			# the store and put on the heat.
			if _business.reserve_for_order(ticket.recipe, 1) > 0:
				ticket.stage = KitchenOrder.Stage.COOKING
				ticket.assigned_cook = cook
				ticket.quality = (
					model.food_quality(_business, cook) if model != null else 70.0
				)
				ticket.ready_time = now + _business.preparation_seconds(
					ticket.recipe, cook
				) / 60.0
			else:
				# The larder is empty. The customer is told rather than left.
				ticket.stage = KitchenOrder.Stage.ABANDONED
				_business.record_lost_sale(LostReason.NO_STOCK)

	for order in _business.kitchen:
		if order.stage == KitchenOrder.Stage.COOKING and now >= order.ready_time:
			order.stage = KitchenOrder.Stage.READY

	if _server_on_the_floor(hour) != null:
		var plate := _business.next_ready_order()
		if plate != null:
			plate.stage = KitchenOrder.Stage.DELIVERED
	_business.tidy_kitchen()


## Whoever is actually in the kitchen. The visible cook is preferred so the
## player can watch the person doing it; the rota answers when nobody has been
## spawned in, which is what keeps a test honest without a body on the floor.
func _cook_at_the_stove(hour: int) -> EmployeeData:
	var visible := _unit.get_node_or_null("Cook") as EmployeeAI
	if visible != null and visible.is_at_station():
		return visible.employee
	return _business.rostered(EmployeeData.Role.COOK, hour)


func _server_on_the_floor(hour: int) -> EmployeeData:
	var visible := _unit.get_node_or_null("Server") as EmployeeAI
	if visible != null and visible.is_at_station():
		return visible.employee
	return _business.rostered(EmployeeData.Role.SERVER, hour)


## Everybody shuffles up one. Positions run back from the counter rather than
## sideways, so the line reads as a line from above.
func _reposition_queue() -> void:
	var till := _checkout()
	if till == null:
		return
	var head := till.service_point()
	var back := (head - till.global_position).normalized()
	for i in _queue.size():
		var customer := _queue[i]
		if is_instance_valid(customer):
			customer.set_queue_slot(i, head + back * (float(i) * queue_spacing))


# --- Serving -------------------------------------------------------------

func _process(delta: float) -> void:
	_business = _unit.get_business()
	if _business == null:
		return
	_work_the_kitchen(delta)
	_work_the_door(delta)
	if queue_length() == 0:
		return

	# The player has to actually be stood at the till they claimed.
	if is_player_working_register() and not _player_in_range():
		_player_register = null

	var seconds := _service_seconds()
	if seconds <= 0.0:
		return
	_serve_timer -= delta
	if _serve_timer > 0.0:
		return
	_serve_timer = seconds
	_serve_next()


## How long one customer takes to serve, or zero when nobody is on the till.
## An employee is checked first: that is what lets the player walk away.
func _service_seconds() -> float:
	var seconds := 0.0
	var cashier := _on_duty_cashier()
	if cashier != null:
		seconds = cashier.checkout_seconds()
	elif is_player_working_register():
		seconds = player_checkout_seconds
	else:
		return 0.0
	# A better till is quicker whoever is standing at it.
	return seconds * (1.0 - _business.upgrade_magnitude(BusinessUpgrade.Effect.CHECKOUT_SPEED))


## Whoever is behind the counter right now. A barista serves as well as makes,
## so either node answers.
func _on_duty_cashier() -> EmployeeData:
	for name in ["Cashier", "Barista"]:
		var employee := _unit.get_node_or_null(name) as EmployeeAI
		if employee != null and employee.is_at_station():
			return employee.employee
	return null


func _player_in_range() -> bool:
	var player := GameManager.player
	if player == null or _player_register == null or not is_instance_valid(_player_register):
		return false
	return player.global_position.distance_to(_player_register.global_position) <= register_range


func _serve_next() -> void:
	if _queue.is_empty():
		return
	var customer := _queue[0]
	if not is_instance_valid(customer):
		_queue.remove_at(0)
		return
	var cashier := _on_duty_cashier()
	var revenue := customer.serve(cashier)

	if cashier != null:
		cashier.customers_served_today += 1
		if revenue > 0:
			cashier.sales_processed_today += 1
	sale_completed.emit(customer, revenue)
