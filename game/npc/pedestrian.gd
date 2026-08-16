class_name Pedestrian
extends NpcWalker
## A civilian going about their day.
##
## Four states, no more than Phase E needs. The thinking happens on arrival and
## on a coarse timer rather than every frame, so the crowd stays cheap as it
## grows: a pedestrian with somewhere to go does nothing per frame except walk.
##
## Schedules, shopping, jobs and relationships all hang off `_choose_wander` and
## the state enum later; nothing else here has to change for them.

signal state_changed(state: State)

enum State { IDLE, WALKING, WITNESSING, FLEEING }

@export_group("Wandering")
@export var idle_time_range: Vector2 = Vector2(1.5, 5.0)
## Destinations closer than this are rejected, so nobody shuffles on the spot.
@export var min_wander_distance: float = 14.0
@export_group("Reactions")
## How long a witness stares before hurrying off.
@export var witness_seconds: float = 2.6
@export var flee_seconds: float = 9.0
@export var min_flee_distance: float = 35.0

var state: State = State.IDLE
var _state_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _crime_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	super()
	_rng.randomize()
	add_to_group(&"pedestrian")
	add_to_group(&"witness")
	path_finished.connect(_on_path_finished)
	# Stagger the first decision so a freshly spawned crowd does not all move
	# off on the same frame.
	_enter_idle(_rng.randf_range(0.0, 2.5))


func _process(delta: float) -> void:
	_state_timer -= delta
	if _state_timer > 0.0:
		return

	match state:
		State.IDLE:
			_choose_wander()
		State.WITNESSING:
			_begin_fleeing()
		State.FLEEING:
			_enter_idle(_rng.randf_range(idle_time_range.x, idle_time_range.y))
		State.WALKING:
			# Walking ends on arrival, not on a timer.
			_state_timer = 1.0


## Called by the witness system when this civilian sees a crime.
func witness_crime(crime_position: Vector3) -> void:
	if state == State.WITNESSING or state == State.FLEEING:
		return
	_crime_position = crime_position
	stop()
	set_running(false)
	_set_state(State.WITNESSING)
	_state_timer = witness_seconds
	# Turn to look at what just happened.
	var to_crime := crime_position - global_position
	to_crime.y = 0.0
	if to_crime.length_squared() > 0.01:
		body_pivot.rotation.y = atan2(to_crime.x, to_crime.z)


func is_available_as_witness() -> bool:
	return state == State.IDLE or state == State.WALKING


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)


func _enter_idle(seconds: float) -> void:
	stop()
	set_running(false)
	_set_state(State.IDLE)
	_state_timer = seconds


func _choose_wander() -> void:
	if nav == null:
		_state_timer = 2.0
		return
	var destination := nav.random_point_away_from(
		NavGraph.Layer.WALK, global_position, min_wander_distance, _rng
	)
	if walk_to(destination):
		_set_state(State.WALKING)
		_state_timer = 1.0
	else:
		# Nowhere to go from here; wait and try again rather than spin.
		_state_timer = 1.5


func _begin_fleeing() -> void:
	set_running(true)
	_set_state(State.FLEEING)
	_state_timer = flee_seconds
	if nav == null:
		return
	var away := nav.random_point_away_from(
		NavGraph.Layer.WALK, _crime_position, min_flee_distance, _rng
	)
	walk_to(away)


func _on_path_finished() -> void:
	match state:
		State.FLEEING:
			# Keep running until the flee timer is up.
			_begin_fleeing()
		State.WITNESSING:
			pass
		_:
			_enter_idle(_rng.randf_range(idle_time_range.x, idle_time_range.y))
