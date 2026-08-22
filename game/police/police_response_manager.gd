extends Node

## The pursuit state machine, and the one place that says what stage a chase is
## at.
##
## §21 asks for explicit states rather than scattered booleans, and this is the
## file that owns them. Everything else reads `state` and does its own job:
## SearchManager runs the clock, PursuitCoordinator hands out roles,
## RoadblockManager decides whether it may block a road, the HUD picks a word.
##
## WantedManager still owns the meter, the arrest and the bust — that is its
## job and Phases J to P are built on it. What moved here is the question of
## what is *happening*, because "wanted level 3" and "the police have lost you
## and are searching Dock Road" are two different facts and the game needs both.
##
## The transitions are deliberately few:
##
##   CLEAR      nothing is going on.
##   REPORTED   a crime has been called in; nobody is on scene yet.
##   RESPONDING units are on their way to where it happened.
##   PURSUIT    somebody has eyes on the player.
##   ESCAPING   line of sight just broke; the police have not accepted it yet.
##   SEARCHING  they have, and are looking around the last known position.
##   COOLDOWN   the search ran out; heat is coming off.
##   CLEARED    it is over. Collapses to CLEAR on the next tick.
##   BUSTED     the player was caught.

signal state_changed(state: State)

enum State {
	CLEAR, REPORTED, RESPONDING, PURSUIT, ESCAPING, SEARCHING,
	COOLDOWN, CLEARED, BUSTED,
}

const STATE_NAMES := {
	State.CLEAR: "CLEAR",
	State.REPORTED: "REPORTED",
	State.RESPONDING: "RESPONDING",
	State.PURSUIT: "PURSUIT",
	State.ESCAPING: "ESCAPING",
	State.SEARCHING: "SEARCHING",
	State.COOLDOWN: "COOLDOWN",
	State.CLEARED: "CLEARED",
	State.BUSTED: "BUSTED",
}

## Seconds of nobody seeing the player before the police accept it and start
## searching. Short: this is the gap between "where did they go" and "right,
## spread out", not a grace period.
const ESCAPING_SECONDS := 2.2
## And how long heat takes to come off once the search has run out.
const COOLDOWN_SECONDS := 4.0

var save_id: StringName = &"police_response"
var reset_on_missing_save: bool = true

var state: State = State.CLEAR

## The response shape the current incident is being answered with.
var profile_id: StringName = &"routine"

var _escaping_time: float = 0.0
var _cooldown_time: float = 0.0
## Longest single pursuit this session, for the statistics. §144.
var longest_pursuit: float = 0.0
var _pursuit_time: float = 0.0
var searches_escaped: int = 0


func _ready() -> void:
	add_to_group(&"saveable")
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if GameManager.is_paused():
		return
	match state:
		State.REPORTED, State.RESPONDING:
			_tick_responding()
		State.PURSUIT:
			_pursuit_time += delta
			longest_pursuit = maxf(longest_pursuit, _pursuit_time)
			_tick_pursuit(delta)
		State.ESCAPING:
			_tick_escaping(delta)
		State.SEARCHING:
			_tick_searching()
		State.COOLDOWN:
			_cooldown_time -= delta
			if _cooldown_time <= 0.0:
				_set_state(State.CLEARED)
		State.CLEARED:
			_set_state(State.CLEAR)


func state_name() -> String:
	return String(STATE_NAMES.get(state, "CLEAR"))


func is_active() -> bool:
	return state != State.CLEAR and state != State.CLEARED


func is_pursuing() -> bool:
	return state == State.PURSUIT


func is_searching() -> bool:
	return state == State.SEARCHING or state == State.ESCAPING


func profile() -> CrimeProfile:
	return CrimeProfile.by_id(profile_id)


# --- Entry points --------------------------------------------------------

## A crime has been called in. The police know where, and may or may not know
## who — that is PoliceMemory's business, not this file's.
func report(at: Vector3, crime_type: int) -> void:
	profile_id = CrimeData.for_type(crime_type).police_response_profile
	PoliceMemory.note_report(at)
	if state == State.CLEAR or state == State.CLEARED:
		_set_state(State.REPORTED)
	elif state == State.SEARCHING or state == State.ESCAPING:
		# §106 — another reported crime while they are looking moves the search
		# to where it happened and puts the clock back up.
		SearchManager.relocate(at, WantedManager.level)
		_set_state(State.SEARCHING)


## Somebody has eyes on the player. The one call that starts or restores a
## pursuit, wherever it came from — a patrol car, an officer on foot, a police
## driver's perception tick.
func note_seen(position: Vector3, heading: Vector3 = Vector3.ZERO) -> void:
	PoliceMemory.note_sighting(position, heading)
	if state == State.BUSTED:
		return
	if state == State.SEARCHING or state == State.ESCAPING:
		# §55 — reacquired.
		SearchManager.end(false)
		_set_state(State.PURSUIT)
		return
	if state != State.PURSUIT:
		_set_state(State.PURSUIT)


func note_busted() -> void:
	SearchManager.end(false)
	_set_state(State.BUSTED)


## Everything over: cleared, busted and resolved, or a fresh game.
func clear() -> void:
	SearchManager.clear()
	PoliceMemory.clear()
	profile_id = &"routine"
	_escaping_time = 0.0
	_cooldown_time = 0.0
	_pursuit_time = 0.0
	_set_state(State.CLEAR)


# --- Ticks ---------------------------------------------------------------

func _tick_responding() -> void:
	if PoliceMemory.has_fresh_sighting():
		_set_state(State.PURSUIT)
		return
	if state == State.REPORTED and PursuitCoordinator.active_units() > 0:
		_set_state(State.RESPONDING)


func _tick_pursuit(_delta: float) -> void:
	if PoliceMemory.has_fresh_sighting():
		return
	_escaping_time = 0.0
	_set_state(State.ESCAPING)


func _tick_escaping(delta: float) -> void:
	if PoliceMemory.has_fresh_sighting():
		_set_state(State.PURSUIT)
		return
	_escaping_time += delta
	if _escaping_time < ESCAPING_SECONDS:
		return
	SearchManager.begin(PoliceMemory.search_origin(), WantedManager.level)
	_set_state(State.SEARCHING)


func _tick_searching() -> void:
	if PoliceMemory.has_fresh_sighting():
		SearchManager.end(false)
		_set_state(State.PURSUIT)
		return
	if SearchManager.active:
		return
	# The search ran out without finding them.
	searches_escaped += 1
	_cooldown_time = COOLDOWN_SECONDS
	_set_state(State.COOLDOWN)


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	if next == State.PURSUIT:
		pass
	else:
		_pursuit_time = 0.0
	state_changed.emit(next)


func save_state() -> Dictionary:
	return {
		"state": int(state),
		"profile": String(profile_id),
		"longest_pursuit": longest_pursuit,
		"searches_escaped": searches_escaped,
	}


func load_state(state_in: Dictionary) -> void:
	profile_id = StringName(state_in.get("profile", "routine"))
	longest_pursuit = float(state_in.get("longest_pursuit", 0.0))
	searches_escaped = int(state_in.get("searches_escaped", 0))
	# §121 — a chase is reconstructed from the wanted state rather than
	# restored unit by unit. Anything mid-pursuit comes back as a search around
	# the last known position, which is a state the police can act on without a
	# fleet of cars that no longer exist.
	var loaded: State = State.CLEAR
	match int(state_in.get("state", 0)):
		State.PURSUIT, State.ESCAPING, State.SEARCHING, State.RESPONDING:
			loaded = State.SEARCHING
		State.REPORTED:
			loaded = State.REPORTED
		State.COOLDOWN:
			loaded = State.COOLDOWN
		_:
			loaded = State.CLEAR
	state = loaded
	_escaping_time = 0.0
	_cooldown_time = COOLDOWN_SECONDS if loaded == State.COOLDOWN else 0.0
	_pursuit_time = 0.0
	state_changed.emit(state)
