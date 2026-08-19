class_name TrafficManager
extends Node3D
## Keeps a believable number of civilian cars on the roads.
##
## Owns population, not behaviour: it spawns cars at valid lane nodes, watches
## for ones that have wandered too far or given up, and recycles them back into
## circulation. Each car drives itself (TrafficDriver).
##
## Recycling rather than free/instantiate is what lets a much larger city run
## later on a fixed budget of vehicles — the pool never grows.

signal vehicle_spawned(vehicle: Vehicle)
signal vehicle_recycled(vehicle: Vehicle)

enum Density { LOW, MEDIUM, HIGH }

## Target population per density setting.
const POPULATION := {Density.LOW: 6, Density.MEDIUM: 11, Density.HIGH: 16}

@export var density: Density = Density.MEDIUM
## Fraction of the target kept overnight. Rush hours land in a later phase; this
## is enough for the streets to feel quieter at 3am.
@export var night_population_scale: float = 0.55
## Never spawn nearer to the player than this — cars must not pop into view.
@export var min_spawn_distance_from_player: float = 55.0
## Beyond this from the player a car is a candidate for recycling.
@export var recycle_distance: float = 150.0
## Clearance required around a spawn node for it to be usable.
@export var spawn_clearance: float = 7.0
## Nothing spawns this close to a signalled junction: a car appearing in the
## middle of a crossroads has no lane to be in and blocks everything.
@export var junction_clearance: float = 14.0
## Seconds between population checks. This does not need to be per frame.
@export var upkeep_interval: float = 0.75

## Which models turn up where lives in the catalogue, not here — a new car is an
## entry in one table rather than an edit to this file.
const CAR_SCENES := VehicleCatalogue.SCENES

## A small palette beats a material per car; each vehicle gets a tinted copy of
## its model's shared VehicleData.
##
## Weighted towards what actually fills a car park — white, silver, grey, black —
## with the colours further down the list turning up often enough to break the
## monotony. A uniformly random palette gives a street of novelty cars.
const BODY_COLOURS: Array[Color] = [
	Color(0.878, 0.886, 0.898), Color(0.878, 0.886, 0.898),
	Color(0.706, 0.714, 0.729), Color(0.706, 0.714, 0.729),
	Color(0.443, 0.455, 0.478), Color(0.443, 0.455, 0.478),
	Color(0.129, 0.137, 0.157), Color(0.129, 0.137, 0.157),
	Color(0.192, 0.286, 0.451), Color(0.545, 0.176, 0.169),
	Color(0.196, 0.373, 0.318), Color(0.616, 0.541, 0.290),
	Color(0.361, 0.310, 0.400), Color(0.729, 0.478, 0.239),
]

## Clothing colours for the people behind the wheel, kept apart from the body
## palette so a driver never blends into their own car.
const DRIVER_COLOURS: Array[Color] = [
	Color(0.545, 0.400, 0.353), Color(0.396, 0.447, 0.510),
	Color(0.424, 0.471, 0.396), Color(0.592, 0.541, 0.424),
	Color(0.475, 0.400, 0.490), Color(0.349, 0.475, 0.490),
]

var _network: RoadNetwork = null
var _vehicles: Array[Vehicle] = []
var _upkeep_timer: float = 0.0
var _spawn_count: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"traffic_manager")
	_rng.randomize()
	_network = get_tree().get_first_node_in_group(&"road_network") as RoadNetwork


func get_active_count() -> int:
	return _vehicles.size()


func get_vehicles() -> Array[Vehicle]:
	return _vehicles.duplicate()


func get_target_population() -> int:
	var target := float(POPULATION.get(density, 11))
	if TimeManager.get_phase() == TimeManager.Phase.NIGHT:
		target *= night_population_scale
	# Busy districts carry more cars. The pool follows the player rather than
	# filling the whole city, so this is the density where they actually are.
	target *= local_traffic_density()
	return maxi(int(round(target)), 1)


## Traffic density of whatever part of the city the player is in. 1.0 when the
## world has not registered any districts, so this is safe in a bare test scene.
func local_traffic_density() -> float:
	var player := GameManager.player
	if player == null or WorldManager.count() == 0:
		return 1.0
	return WorldManager.traffic_density_at(player.global_position)


## Fills the roads immediately, ignoring the distance-from-player rule. Used at
## load so the district does not start empty and fill in while the player
## watches.
func prime(count: int = -1) -> void:
	var target := count if count >= 0 else get_target_population()
	for i in target:
		_spawn_one(true)


func _process(delta: float) -> void:
	_upkeep_timer -= delta
	if _upkeep_timer > 0.0:
		return
	_upkeep_timer = upkeep_interval
	_upkeep()


## Empties the roads and stops the manager refilling them. Nothing in the game
## calls this; it exists so a test can have a deterministic street.
func set_active(active: bool) -> void:
	set_process(active)


func clear() -> void:
	for vehicle in _vehicles:
		if is_instance_valid(vehicle):
			vehicle.queue_free()
	_vehicles.clear()


func _upkeep() -> void:
	if _network == null or not _network.is_ready():
		return

	_vehicles = _vehicles.filter(func(car: Vehicle) -> bool: return is_instance_valid(car))

	var player := GameManager.player
	for vehicle in _vehicles:
		if player == null:
			continue
		# Far away and out of mind: put it back into circulation elsewhere.
		if vehicle.global_position.distance_to(player.global_position) > recycle_distance:
			_recycle(vehicle)

	var target := get_target_population()
	if _vehicles.size() < target:
		_spawn_one(false)
	elif _vehicles.size() > target:
		_retire_furthest()


# --- Spawning ------------------------------------------------------------

func _spawn_one(ignore_player_distance: bool) -> Vehicle:
	var node := find_spawn_node(ignore_player_distance)
	if node < 0:
		return null

	var style := _pick_style_for(_network.node_position(node))
	var vehicle: Vehicle = VehicleCatalogue.scene_for(style).instantiate()
	_spawn_count += 1
	vehicle.name = "Traffic_%s_%d" % [style, _spawn_count]
	vehicle.controller = Vehicle.Controller.TRAFFIC_AI
	vehicle.owner_type = Vehicle.OwnerType.NPC
	vehicle.owner_id = &"traffic"
	# Somebody is driving it. Set before the car enters the tree so the figure in
	# the seat is built with the right colour.
	vehicle.driver_type = Vehicle.DriverType.CIVILIAN
	vehicle.driver_state = Vehicle.DriverState.SEATED
	vehicle.driver_id = StringName("driver_%d" % _spawn_count)
	vehicle.driver_color = DRIVER_COLOURS[_rng.randi_range(0, DRIVER_COLOURS.size() - 1)]

	var tinted: VehicleData = vehicle.data.duplicate()
	tinted.body_color = BODY_COLOURS[_rng.randi_range(0, BODY_COLOURS.size() - 1)]
	vehicle.data = tinted

	_place_at_node(vehicle, node)
	add_child(vehicle)

	var driver := TrafficDriver.new()
	driver.name = "Driver"
	driver.recycle_requested.connect(_on_recycle_requested.bind(vehicle))
	vehicle.add_child(driver)

	vehicle.carjacked.connect(_on_vehicle_carjacked.bind(vehicle))

	_vehicles.append(vehicle)
	vehicle_spawned.emit(vehicle)
	return vehicle


func _place_at_node(vehicle: Vehicle, node: int) -> void:
	var position := _network.node_position(node)
	var direction := _network.node_direction(node)
	vehicle.position = position
	# Vehicles face -Z, so a lane heading of `direction` is that yaw.
	vehicle.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)
	vehicle.halt()


## A node is valid when it is clear of other traffic and, unless priming, far
## enough from the player that nothing appears out of thin air on screen.
func find_spawn_node(ignore_player_distance: bool) -> int:
	var player := GameManager.player
	for attempt in 24:
		var node := _network.random_node(_rng)
		if node < 0:
			continue
		var position := _network.node_position(node)

		if not ignore_player_distance and player != null:
			if position.distance_to(player.global_position) < min_spawn_distance_from_player:
				continue
		if _is_in_a_junction(position):
			continue
		if _is_occupied(position):
			continue
		return node
	return -1


func _is_in_a_junction(position: Vector3) -> bool:
	for light in get_tree().get_nodes_in_group(&"traffic_light"):
		if (light as Node3D).global_position.distance_to(position) < junction_clearance:
			return true
	return false


## Cheap occupancy test against everything on wheels, so a car never lands
## inside another one.
func _is_occupied(position: Vector3) -> bool:
	for other in get_tree().get_nodes_in_group(&"vehicle"):
		if other is Node3D and other.global_position.distance_to(position) < spawn_clearance:
			return true
	var player := GameManager.player
	return player != null and player.global_position.distance_to(position) < spawn_clearance


## What kind of car this part of the city puts on the road. Harbour Row runs
## vans and saloons; Central runs small cars and the odd expensive one.
func _pick_style_for(position: Vector3) -> StringName:
	var district := WorldManager.district_at(position)
	var id: StringName = district.district_id if district != null else &"harbour_row"
	return VehicleCatalogue.pick_id_for_district(id, _rng)


# --- Recycling -----------------------------------------------------------

## Moves an existing car to a fresh spawn point rather than destroying it. The
## pool size stays fixed however big the city gets.
func _recycle(vehicle: Vehicle) -> void:
	var node := find_spawn_node(false)
	if node < 0:
		return
	_place_at_node(vehicle, node)
	vehicle.repair()
	var driver := vehicle.get_node_or_null("Driver") as TrafficDriver
	if driver != null:
		driver.restart_at(node)
	vehicle_recycled.emit(vehicle)


func _retire_furthest() -> void:
	var player := GameManager.player
	if player == null or _vehicles.is_empty():
		return
	var furthest: Vehicle = null
	var best := -1.0
	for vehicle in _vehicles:
		var distance := vehicle.global_position.distance_to(player.global_position)
		if distance > best:
			best = distance
			furthest = vehicle
	# Only ever remove something the player cannot see.
	if furthest != null and best > recycle_distance * 0.6:
		_vehicles.erase(furthest)
		furthest.queue_free()


## A stolen car stops being traffic. It leaves the pool entirely — otherwise the
## upkeep pass would eventually teleport it back onto a lane with the player
## sitting in it — and the population tops itself back up with a fresh one.
func _on_vehicle_carjacked(_thief: Node3D, _victim: Node3D, vehicle: Vehicle) -> void:
	_vehicles.erase(vehicle)


func _on_recycle_requested(vehicle: Vehicle) -> void:
	if is_instance_valid(vehicle):
		_recycle(vehicle)
