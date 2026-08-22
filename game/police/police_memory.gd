extends Node

## What the police know, as against what is true.
##
## The single most important idea in Phase Q's police work. Before this, a
## patrol car asked the game where the player was; now it asks what the police
## were last told. Those are different numbers, and the gap between them is the
## whole of escaping.
##
## §22 is explicit that police must not have perfect knowledge, so this holds
## only things somebody could plausibly have observed: where the player was when
## last seen, when that was, roughly which way they were going, and what they
## were driving if anybody got a look at it. It does not hold the player's
## current position, and nothing here reads it.
##
## §27 keeps two kinds of identification apart. Knowing the *player* and knowing
## the *car* are related — a witness who watched somebody get into a car knows
## both — but they come apart the moment the player gets out, and that is what
## makes abandoning a vehicle worth doing.

signal identification_changed()
signal vehicle_marked(instance_id: StringName)
signal vehicle_forgotten(instance_id: StringName)

## How long a sighting stays fresh enough to route on. Older than this and the
## police are searching rather than chasing.
const SIGHTING_FRESH_SECONDS := 4.0
## Heading is only worth recording if the player was actually going somewhere.
const MIN_HEADING_SPEED := 3.0

var save_id: StringName = &"police_memory"
var reset_on_missing_save: bool = true

## Where the player was last seen. Never where they are.
var last_known_position: Vector3 = Vector3.ZERO
## Seconds since that sighting. Grows while nobody can see the player.
var seconds_since_seen: float = 999.0
## Roughly which way they were going, if they were moving. Zero when not known.
var last_known_heading: Vector3 = Vector3.ZERO
## Whether the police currently believe they know who they are looking for, as
## against merely knowing a crime happened somewhere.
var player_identified: bool = false
## Vehicles the police are looking for in this incident. §28.
var _known_vehicles: Dictionary = {}
## The one the player was last seen in, which is the one units route on.
var active_vehicle_id: StringName = &""


func _ready() -> void:
	add_to_group(&"saveable")


## The car the player was in last tick, so a change can be noticed.
var _player_vehicle_id: StringName = &""


func _process(delta: float) -> void:
	if not WantedManager.is_wanted():
		_player_vehicle_id = _vehicle_id(_player_vehicle())
		return
	seconds_since_seen += delta
	_watch_for_vehicle_change()


## §30, §158 and §159 in one place: what happens when the player changes cars.
##
## Seen doing it, the description simply moves to the new car — there is no
## exploit in swapping vehicles in front of the officer watching you. Unseen,
## the police lose what they were looking for, and that is the single most
## useful thing a player being chased can do.
##
## What it explicitly does not do is end the search. §30 is firm: the police
## still know roughly where you were, and they are still looking there. What
## they have lost is the description, not the address.
func _watch_for_vehicle_change() -> void:
	var car := _player_vehicle()
	var id := _vehicle_id(car)
	if id == _player_vehicle_id:
		return
	var previous := _player_vehicle_id
	_player_vehicle_id = id

	if has_fresh_sighting():
		# Watched. Whatever they got into is what the police are looking for.
		if car != null:
			mark_vehicle_known(car)
		else:
			player_identified = true
			clear_active_vehicle()
		return

	# Unseen. If the police were only ever looking for the car, they have
	# nothing now. If a witness described the player themselves, getting out
	# of one car and into another does not change what they look like — but
	# the car they are watching for is no longer the right one.
	if previous != &"" and active_vehicle_id == previous:
		clear_active_vehicle()
	if car != null and is_vehicle_known(car):
		# Straight back into something they are already looking for.
		mark_vehicle_known(car)


func _player_vehicle() -> Node:
	var player := GameManager.player
	if player == null or not player.has_method("get_vehicle"):
		return null
	var car = player.call("get_vehicle")
	return car if car != null and is_instance_valid(car) else null


# --- Sightings -----------------------------------------------------------

## Somebody has eyes on the player. The one call that makes police knowledge
## true again, and the only place last_known_position is allowed to move to the
## player's real position.
func note_sighting(position: Vector3, heading: Vector3 = Vector3.ZERO) -> void:
	last_known_position = position
	seconds_since_seen = 0.0
	if heading.length() >= MIN_HEADING_SPEED:
		last_known_heading = heading.normalized()
	if not player_identified:
		player_identified = true
		identification_changed.emit()


## Nobody saw who did it, but the police know where it happened. This is what a
## report gives them: an address, not a suspect.
func note_report(position: Vector3) -> void:
	last_known_position = position
	seconds_since_seen = maxf(seconds_since_seen, SIGHTING_FRESH_SECONDS)


## The police are looking for the player and have a description, without any
## particular witness having handed one over.
##
## Being wanted at all implies this: a level was raised, so somebody told them
## something. It matters because the alternative — a wanted player nobody can
## recognise — is a chase with no chase in it. The interesting case is the
## reverse, and that is `lose_player_identity()`: a description the police had
## and no longer do.
func assume_description(position: Vector3 = Vector3.INF) -> void:
	if position != Vector3.INF:
		last_known_position = position
	if player_identified:
		return
	player_identified = true
	identification_changed.emit()


func has_fresh_sighting() -> bool:
	return seconds_since_seen <= SIGHTING_FRESH_SECONDS


## Where units should be heading. Fresh sightings are worth following; a stale
## one is a place to start looking, and §22 forbids extrapolating a stale
## heading across the city on the strength of one glimpse.
func search_origin() -> Vector3:
	return last_known_position


## A point a little along the player's last heading, for units told to cut
## ahead rather than follow. Only offered while the sighting is fresh.
func predicted_position(seconds_ahead: float, speed: float = 12.0) -> Vector3:
	if not has_fresh_sighting() or last_known_heading == Vector3.ZERO:
		return last_known_position
	return last_known_position + last_known_heading * speed * seconds_ahead


# --- Vehicles ------------------------------------------------------------

## The police are looking for this car. Ownership has nothing to do with it —
## §29 is explicit that a legally owned car can become known, and it is the
## player's problem either way.
func mark_vehicle_known(vehicle: Node) -> void:
	var id := _vehicle_id(vehicle)
	if id == &"":
		return
	active_vehicle_id = id
	if _known_vehicles.has(id):
		return
	_known_vehicles[id] = TimeManager.total_minutes
	vehicle_marked.emit(id)
	identification_changed.emit()


func is_vehicle_known(vehicle: Node) -> bool:
	return _known_vehicles.has(_vehicle_id(vehicle))


func known_vehicle_ids() -> Array:
	return _known_vehicles.keys()


func known_vehicle_count() -> int:
	return _known_vehicles.size()


## The player got out, or into something else. The car the police are looking
## for is still known — it is simply no longer the one they are following.
func clear_active_vehicle() -> void:
	if active_vehicle_id == &"":
		return
	active_vehicle_id = &""
	identification_changed.emit()


## Stops looking for one car. Used when it is destroyed or sold on.
func forget_vehicle(instance_id: StringName) -> void:
	if not _known_vehicles.erase(instance_id):
		return
	if active_vehicle_id == instance_id:
		active_vehicle_id = &""
	vehicle_forgotten.emit(instance_id)
	identification_changed.emit()


## The player is in a car the police are not looking for, and nobody watched
## them get into it. §30: this loses the police their description, and it does
## not clear the search around where they were last seen.
func lose_player_identity() -> void:
	if not player_identified and active_vehicle_id == &"":
		return
	player_identified = false
	active_vehicle_id = &""
	identification_changed.emit()


## Whether the police can currently say what they are looking for at all.
func has_description() -> bool:
	return player_identified or active_vehicle_id != &""


# --- Lifecycle -----------------------------------------------------------

## §57 — incident-level only. The heat on a car goes with the incident that
## created it; Phase Q deliberately builds no permanent record.
func clear() -> void:
	last_known_position = Vector3.ZERO
	seconds_since_seen = 999.0
	last_known_heading = Vector3.ZERO
	player_identified = false
	_known_vehicles.clear()
	active_vehicle_id = &""
	identification_changed.emit()


func _vehicle_id(vehicle: Node) -> StringName:
	if vehicle == null:
		return &""
	var id: Variant = vehicle.get("instance_id")
	if id != null and StringName(id) != &"":
		return StringName(id)
	# A traffic car has no registry entry; its node path is stable enough to
	# tell one from another for the length of an incident.
	return StringName(vehicle.get_path())


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	var vehicles := {}
	for id: StringName in _known_vehicles:
		vehicles[String(id)] = float(_known_vehicles[id])
	return {
		"last_known": [last_known_position.x, last_known_position.y, last_known_position.z],
		"heading": [last_known_heading.x, last_known_heading.y, last_known_heading.z],
		"seconds_since_seen": seconds_since_seen,
		"identified": player_identified,
		"known_vehicles": vehicles,
		"active_vehicle": String(active_vehicle_id),
	}


func load_state(state: Dictionary) -> void:
	clear()
	var point: Array = state.get("last_known", [])
	if point.size() == 3:
		last_known_position = Vector3(float(point[0]), float(point[1]), float(point[2]))
	var heading: Array = state.get("heading", [])
	if heading.size() == 3:
		last_known_heading = Vector3(float(heading[0]), float(heading[1]), float(heading[2]))
	seconds_since_seen = float(state.get("seconds_since_seen", 999.0))
	player_identified = bool(state.get("identified", false))
	for key in state.get("known_vehicles", {}):
		_known_vehicles[StringName(key)] = float(state["known_vehicles"][key])
	active_vehicle_id = StringName(state.get("active_vehicle", ""))
	identification_changed.emit()
