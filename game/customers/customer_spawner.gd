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

## Ceiling on how many are on the floor at once, so a busy shop stays cheap.
@export var max_active_customers: int = 8
## How many may be waiting before the rest turn round and walk out.
@export var max_queue_length: int = 5
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


func _spawn_one() -> CustomerAI:
	if active_customers().size() >= max_active_customers:
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
	if queue_length() >= max_queue_length:
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
	if _business == null or queue_length() == 0:
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
	var cashier := _on_duty_cashier()
	if cashier != null:
		return cashier.checkout_seconds()
	if is_player_working_register():
		return player_checkout_seconds
	return 0.0


func _on_duty_cashier() -> EmployeeData:
	var employee := _unit.get_node_or_null("Cashier") as EmployeeAI
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
	var revenue := customer.serve()

	var cashier := _on_duty_cashier()
	if cashier != null:
		cashier.customers_served_today += 1
		if revenue > 0:
			cashier.sales_processed_today += 1
	sale_completed.emit(customer, revenue)
