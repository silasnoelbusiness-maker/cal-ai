extends Node
## Delivery work: the job that only makes sense once the city is big.
##
## A run is a real drive. The depot hands over a destination somewhere else in
## the city, the map guides the player to it, and the money lands when they
## arrive. Nothing about it is new machinery — the destination is the map's, the
## navigation is the map's, the payment is the ordinary economy — which is the
## point: a bigger city makes the parts that already existed worth having.

signal run_offered(destination: MapMarker, fee: int)
signal run_completed(fee: int, bonus: int)
signal run_failed()

@export var save_id: StringName = &"courier_job"

## Base fee, plus this much for every hundred metres of the trip.
@export var base_fee: int = 45
@export var fee_per_hundred_metres: int = 12
## Paid on top when the run is finished inside the target time.
@export var time_bonus: int = 20
## In-game minutes allowed per hundred metres before the bonus is lost.
@export var minutes_per_hundred_metres: float = 1.6
## The depot will not offer anywhere nearer than this.
@export var minimum_distance: float = 120.0

var _destination: MapMarker = null
var _fee: int = 0
var _bonus_deadline: float = -1.0
var _runs_completed: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	add_to_group(&"saveable")
	MapManager.destination_reached.connect(_on_destination_reached)


func has_active_run() -> bool:
	return _destination != null


func active_destination_name() -> String:
	return _destination.label if _destination != null else ""


func active_fee() -> int:
	return _fee


func runs_completed() -> int:
	return _runs_completed


## Offers a job. The destination is picked from the city's own venues, so the
## pool grows as the city does rather than being a list somebody has to maintain.
func offer_run() -> bool:
	if has_active_run():
		return false
	var player := GameManager.player
	if player == null:
		return false

	var candidates := _destination_pool(player.global_position)
	if candidates.is_empty():
		GameManager.notify("NOTHING TO DELIVER RIGHT NOW", GameManager.Tone.INFO)
		return false

	_destination = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var distance := player.global_position.distance_to(_destination.position)
	_fee = base_fee + roundi(distance / 100.0 * float(fee_per_hundred_metres))
	_bonus_deadline = (
		TimeManager.total_minutes + distance / 100.0 * minutes_per_hundred_metres + 4.0
	)

	MapManager.set_destination(_destination)
	GameManager.notify(
		"DELIVERY ACCEPTED\n%s  ·  $%d  (+$%d in time)" % [
			_destination.label.to_upper(), _fee, time_bonus
		],
		GameManager.Tone.GOOD
	)
	run_offered.emit(_destination, _fee)
	return true


## Somewhere far enough away to be a drive. Businesses, shops, homes and units
## all count — anything with an address.
func _destination_pool(from: Vector3) -> Array[MapMarker]:
	var pool: Array[MapMarker] = []
	for marker in MapManager.collect_markers():
		if marker.category == MapMarker.Category.JOB:
			continue
		if from.distance_to(marker.position) < minimum_distance:
			continue
		pool.append(marker)
	return pool


func cancel_run() -> void:
	if not has_active_run():
		return
	_destination = null
	_fee = 0
	_bonus_deadline = -1.0
	MapManager.clear_destination()
	GameManager.notify("DELIVERY CANCELLED", GameManager.Tone.BAD)
	run_failed.emit()


func _on_destination_reached(marker: MapMarker) -> void:
	if _destination == null or marker == null or marker.label != _destination.label:
		return
	var bonus := time_bonus if TimeManager.total_minutes <= _bonus_deadline else 0
	var fee := _fee
	_destination = null
	_fee = 0
	_bonus_deadline = -1.0
	_runs_completed += 1

	EconomyManager.deposit(
		fee + bonus, "Courier delivery",
		EconomyManager.Source.LEGAL, EconomyManager.Stream.EMPLOYMENT
	)
	# A run takes a few minutes of the day whatever else happens, so the job
	# cannot be farmed by driving in circles between two neighbouring markers.
	TimeManager.advance_minutes(8)
	GameManager.notify(
		"DELIVERED\n+$%d%s" % [fee + bonus, "  (time bonus)" if bonus > 0 else ""],
		GameManager.Tone.GOOD
	)
	LifeStats.add(&"deliveries_made")
	LifeStats.add(&"shift_income", fee + bonus)
	run_completed.emit(fee, bonus)


func save_state() -> Dictionary:
	return {"runs_completed": _runs_completed}


func load_state(state: Dictionary) -> void:
	_runs_completed = int(state.get("runs_completed", 0))
	# A run in progress is not restored: the destination marker is rebuilt from
	# the live world, and half a delivery is not worth the migration.
	_destination = null
	_fee = 0
