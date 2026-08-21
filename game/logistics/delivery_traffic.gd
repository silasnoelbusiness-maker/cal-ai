class_name DeliveryTraffic
extends Node

## Puts a van on the road for a shipment the player can actually see.
##
## §107 and §108. The rule is that the visible van changes nothing about the
## delivery: the order is already IN_TRANSIT, the goods already left the
## source, and the only thing spawning a van does is decide *which* moment
## counts as arrival — the van reaching the kerb, or the clock running out.
## Whichever happens first calls the same LogisticsManager.complete_transfer().
##
## When the player drives away, the van is despawned and the clock finishes
## the job. Nothing is lost, nothing is delivered twice, and a company running
## six rounds across two districts costs the same whether the player watches
## one of them or none.

## How close the player has to be to either end of a run before it is worth
## putting a vehicle on the road.
const SPAWN_RANGE := 140.0
## And how far they have to get before it is folded back into the clock. The
## gap between the two stops a van blinking in and out on the boundary.
const DESPAWN_RANGE := 190.0
## Vans on screen at once. A cap, because a large company can have a dozen
## shipments running and the road only needs to look busy, not exhaustive.
const MAX_VISIBLE := 3
## How often the spawn decision is made. Deliveries take minutes of game time;
## twice a second is plenty and keeps the distance checks off the frame.
const REVIEW_INTERVAL := 0.5

## transfer id -> Vehicle
var _vans: Dictionary = {}
var _review_timer: float = 0.0


func _process(delta: float) -> void:
	_review_timer -= delta
	if _review_timer > 0.0:
		return
	_review_timer = REVIEW_INTERVAL
	_retire_finished()
	_review()


## Whether a shipment currently has a van on the road.
func is_visible(transfer_id: StringName) -> bool:
	return _vans.has(transfer_id)


func visible_count() -> int:
	return _vans.size()


## Drops every van without touching a single order. Used on load and on a
## district change, where the world under the vans is about to be rebuilt.
func clear() -> void:
	for id: StringName in _vans.keys():
		_despawn(id)


func _retire_finished() -> void:
	for id: StringName in _vans.keys():
		var order := LogisticsManager.transfer_by_id(id)
		var van: Vehicle = _vans[id]
		if order == null or not order.is_moving() or van == null or not is_instance_valid(van):
			_despawn(id)


func _review() -> void:
	var player := GameManager.player
	if player == null:
		return
	var here := player.global_position

	for id: StringName in _vans.keys():
		var order := LogisticsManager.transfer_by_id(id)
		if order == null or _closest_end(order, here) > DESPAWN_RANGE:
			_despawn(id)

	if _vans.size() >= MAX_VISIBLE:
		return
	for order in LogisticsManager.transfers():
		if _vans.size() >= MAX_VISIBLE:
			return
		if not order.is_moving() or order.player_driven:
			continue
		if _vans.has(order.transfer_id):
			continue
		if _closest_end(order, here) <= SPAWN_RANGE:
			_spawn(order)


## Distance from the player to whichever end of the run is nearer. A van is
## worth drawing when it is leaving a depot the player is standing in as much
## as when it is pulling up outside their shop.
func _closest_end(order: TransferOrder, here: Vector3) -> float:
	var from_point := LogisticsManager.place_position(order.source_kind, order.source_id)
	var to_point := LogisticsManager.place_position(
		order.destination_kind, order.destination_id
	)
	return minf(here.distance_to(from_point), here.distance_to(to_point))


func _spawn(order: TransferOrder) -> void:
	var network := get_tree().get_first_node_in_group(&"road_network") as RoadNetwork
	if network == null or not network.is_ready():
		return
	var to_point := LogisticsManager.place_position(
		order.destination_kind, order.destination_id
	)
	# Where the van is *now*: partway along, in proportion to how much of the
	# journey the clock says is done. A van that is nearly there does not
	# appear at the depot it left an hour ago.
	var from_point := LogisticsManager.place_position(order.source_kind, order.source_id)
	var start := from_point.lerp(to_point, _progress(order))
	var start_node := network.nearest_kerb(start)
	if start_node < 0:
		return

	var van: Vehicle = VehicleCatalogue.scene_for(&"van").instantiate()
	van.name = "Delivery_%s" % String(order.transfer_id)
	van.controller = Vehicle.Controller.TRAFFIC_AI
	van.owner_type = Vehicle.OwnerType.NPC
	van.owner_id = &"company_delivery"
	van.driver_type = Vehicle.DriverType.CIVILIAN
	van.driver_state = Vehicle.DriverState.SEATED
	van.driver_id = order.assigned_driver_id
	van.position = network.node_position(start_node)
	var facing := network.node_direction(start_node)
	van.rotation = Vector3(0.0, atan2(-facing.x, -facing.z), 0.0)
	add_child(van)
	van.halt()

	var driver := DeliveryDriver.new()
	driver.name = "Driver"
	van.add_child(driver)
	driver.drive_to(to_point)
	driver.arrived.connect(_on_arrived.bind(order.transfer_id))

	_vans[order.transfer_id] = van


## How far through the journey the order is, by its own clock. The van is a
## view of that, so it starts where the clock says it has got to.
func _progress(order: TransferOrder) -> float:
	var span := order.arrival_minute - order.dispatch_minute
	if span <= 0.0:
		return 0.0
	var done := TimeManager.total_minutes - order.dispatch_minute
	# Never all the way: a van that spawns on top of its destination has no
	# road left to drive and arrives before the player sees it.
	return clampf(done / span, 0.0, 0.85)


func _on_arrived(transfer_id: StringName) -> void:
	var order := LogisticsManager.transfer_by_id(transfer_id)
	_despawn(transfer_id)
	if order != null and order.is_moving():
		LogisticsManager.complete_transfer(order)


func _despawn(transfer_id: StringName) -> void:
	var van: Vehicle = _vans.get(transfer_id)
	_vans.erase(transfer_id)
	if van != null and is_instance_valid(van):
		van.queue_free()
