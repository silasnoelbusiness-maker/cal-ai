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
signal knocked_down(impact_speed: float)
signal recovered()

enum State { IDLE, WALKING, WITNESSING, FLEEING, DODGING, KNOCKED_DOWN }

@export_group("Wandering")
@export var idle_time_range: Vector2 = Vector2(1.5, 5.0)
## Destinations closer than this are rejected, so nobody shuffles on the spot.
@export var min_wander_distance: float = 14.0
@export_group("Reactions")
## How long a witness stares before hurrying off.
@export var witness_seconds: float = 2.6
@export var flee_seconds: float = 9.0
@export var min_flee_distance: float = 35.0

@export_group("Traffic safety")
@export var max_health: float = 100.0
## Seconds between traffic scans. Coarse deliberately: a crowd of sixteen doing
## this every frame is the most expensive thing on the street, and a quarter of
## a second is still four chances to jump before a car covers ten metres.
@export var danger_check_interval: float = 0.25
## Only cars this close are considered.
@export var danger_radius: float = 15.0
## Half-width of the corridor in front of a car that counts as its path.
@export var danger_half_width: float = 2.4
## Below this speed a car is not worth jumping out of the way of.
@export var danger_min_speed: float = 3.5
## How far sideways a dodge aims for.
@export var dodge_distance: float = 4.5
@export var dodge_seconds: float = 1.6
## Impacts below this are a shove; above it the pedestrian goes down.
@export var knockdown_speed: float = 4.0
## Damage per m/s of impact above `knockdown_speed`.
@export var damage_per_impact_speed: float = 4.0
## How long they stay down, before a slower scramble back to their feet.
@export var down_seconds: Vector2 = Vector2(2.4, 4.0)

var state: State = State.IDLE
var health: float = 100.0
var _state_timer: float = 0.0
var _rng := RandomNumberGenerator.new()
var _crime_position: Vector3 = Vector3.ZERO
var _danger_timer: float = 0.0
var _threat_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	super()
	_rng.randomize()
	health = max_health
	add_to_group(&"pedestrian")
	add_to_group(&"witness")
	path_finished.connect(_on_path_finished)
	# Stagger the traffic scans too, so the crowd's checks spread across frames
	# instead of all landing on the same one.
	_danger_timer = _rng.randf_range(0.0, danger_check_interval)
	# Stagger the first decision so a freshly spawned crowd does not all move
	# off on the same frame.
	_enter_idle(_rng.randf_range(0.0, 2.5))


func _process(delta: float) -> void:
	_danger_timer -= delta
	if _danger_timer <= 0.0:
		_danger_timer = danger_check_interval
		_check_traffic()

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
		State.KNOCKED_DOWN:
			_stand_up()
		State.DODGING:
			# Out of the road; carry on shaken rather than resuming mid-street.
			_begin_fleeing()
		State.WALKING:
			# Walking ends on arrival, not on a timer.
			_state_timer = 1.0


## Called by the witness system when this civilian sees a crime.
func witness_crime(crime_position: Vector3) -> void:
	if state == State.WITNESSING or state == State.FLEEING or state == State.KNOCKED_DOWN:
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


## Stands still and makes no decisions for `seconds`. Reactions still interrupt
## it — being knocked down or seeing a crime overrides the state outright — so
## this is "nothing to do right now", not a freeze. Waiting at a crossing, or
## queuing at a counter, will want exactly this.
func wait_for(seconds: float) -> void:
	if state == State.KNOCKED_DOWN:
		return
	_enter_idle(seconds)


# --- Traffic safety ------------------------------------------------------

func is_down() -> bool:
	return state == State.KNOCKED_DOWN


## Struck by a vehicle. Returns true if this actually put them on the floor, so
## the caller can tell a knockdown from a nudge at walking pace.
##
## No ragdoll and no gore: they drop, lie there a moment, get up and hurry off.
## That is enough to make running people over feel like something happened
## without the phase turning into a physics project.
func knock_down(impact_speed: float, from_direction: Vector3 = Vector3.ZERO) -> bool:
	if state == State.KNOCKED_DOWN:
		return false
	if impact_speed < knockdown_speed:
		# A shove at parking speed: step aside, stay upright. `from_direction`
		# points from the car to them, so following it is away from the car.
		_dodge_away(global_position + from_direction * dodge_distance)
		return false

	stop()
	set_running(false)
	# Remember roughly where the car came from, so they run away from it rather
	# than back into the road when they get up.
	_threat_position = global_position - from_direction * dodge_distance
	health = maxf(health - (impact_speed - knockdown_speed) * damage_per_impact_speed, 1.0)
	# Out of the collision world while down, so nothing walks into a body on the
	# floor and no car re-triggers the same impact every frame.
	collision_layer = 0
	_lay_down(from_direction)
	_set_state(State.KNOCKED_DOWN)
	_state_timer = _rng.randf_range(down_seconds.x, down_seconds.y)
	knocked_down.emit(impact_speed)
	return true


func _stand_up() -> void:
	collision_layer = 1 << 4
	body_pivot.rotation.x = 0.0
	body_pivot.position.y = 0.0
	recovered.emit()
	# Someone who has just been run over does not go back to window shopping.
	_crime_position = _threat_position
	_begin_fleeing()


func _lay_down(from_direction: Vector3) -> void:
	var flat := Vector3(from_direction.x, 0.0, from_direction.z)
	if flat.length_squared() > 0.01:
		body_pivot.rotation.y = atan2(flat.x, flat.z)
	# The pivot sits at the feet, so a quarter turn about X lays the figure out
	# in the direction it was hit, and lifting it by a radius rests it on the
	# ground instead of half-buried.
	body_pivot.rotation.x = -PI * 0.5
	body_pivot.position.y = body_radius


## Looks for a car bearing down on this pedestrian. Corridor test rather than a
## physics query: a dot product per nearby vehicle costs nothing, and being
## approximately right about "that car is coming at me" is all the reaction
## needs.
func _check_traffic() -> void:
	if state == State.KNOCKED_DOWN or state == State.DODGING:
		return

	for node in get_tree().get_nodes_in_group(&"vehicle"):
		var car := node as Vehicle
		if car == null or car.get_planar_speed() < danger_min_speed:
			continue

		var offset := global_position - car.global_position
		offset.y = 0.0
		if offset.length() > danger_radius:
			continue

		var forward := -car.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.01:
			continue
		forward = forward.normalized()
		# Reversing cars point their danger the other way.
		if car.get_forward_speed() < 0.0:
			forward = -forward

		var ahead := offset.dot(forward)
		if ahead < 0.0 or ahead > danger_radius:
			continue
		var sideways := offset.dot(forward.cross(Vector3.UP))
		if absf(sideways) > danger_half_width:
			continue

		_threat_position = car.global_position
		_dodge_away(global_position + forward.cross(Vector3.UP) * signf_or_random(sideways) * dodge_distance)
		return


## Sideways is signed; standing exactly in the middle of the lane is not, so
## pick a side rather than freezing.
func signf_or_random(value: float) -> float:
	if absf(value) < 0.05:
		return 1.0 if _rng.randf() < 0.5 else -1.0
	return signf(value)


func _dodge_away(destination: Vector3) -> void:
	if state == State.KNOCKED_DOWN:
		return
	set_running(true)
	_set_state(State.DODGING)
	_state_timer = dodge_seconds
	if not walk_to(destination):
		# Nowhere to route to; still get off the spot.
		walk_to(global_position + (destination - global_position).normalized() * 2.0)


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
		State.WITNESSING, State.KNOCKED_DOWN:
			pass
		State.DODGING:
			# Off the road already; wait out the timer rather than wandering back.
			pass
		_:
			_enter_idle(_rng.randf_range(idle_time_range.x, idle_time_range.y))
