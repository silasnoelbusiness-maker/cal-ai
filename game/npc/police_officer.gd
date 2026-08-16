class_name PoliceOfficer
extends NpcWalker
## An officer on foot.
##
## Six states, each with its own small handler — no single function decides
## everything. Perception runs on a timer rather than per frame, and only the
## officers close enough to matter do the raycast.
##
## The officer never reads the player's position to navigate. It navigates to
## `WantedManager.last_known_position`, and only updates that by *seeing* the
## player. That is what stops police following the player through buildings.

signal state_changed(state: State)

enum State { PATROL, RESPONDING, PURSUING, SEARCHING, BUSTING, RETURNING }

@export_group("Post")
## Where this officer stands when nothing is happening. Set at spawn.
@export var post_position: Vector3 = Vector3.ZERO
@export var patrol_radius: float = 26.0

@export_group("Perception")
## Seconds between sight checks. Coarse on purpose.
@export var perception_interval: float = 0.25
@export var sight_radius: float = 32.0
## Full circle on purpose. This is the *pursuit* check — an officer hunting a
## known suspect is actively scanning, not staring down their nose, and gating
## it on walking direction made an officer who turned around permanently blind.
## Noticing a crime in the first place is a different, narrower test: see
## WitnessSystem.police_view_angle.
@export var view_angle: float = 360.0

@export_group("Behaviour")
@export var repath_interval: float = 0.6
@export var search_point_radius: float = 26.0
@export var idle_time_range: Vector2 = Vector2(2.0, 5.0)

var state: State = State.PATROL

var _perception_timer: float = 0.0
var _repath_timer: float = 0.0
var _state_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super()
	_rng.randomize()
	add_to_group(&"police")
	add_to_group(&"witness")
	if post_position == Vector3.ZERO:
		post_position = global_position
	path_finished.connect(_on_path_finished)

	WantedManager.level_changed.connect(_on_wanted_level_changed)
	WantedManager.wanted_cleared.connect(_on_wanted_cleared)
	_state_timer = _rng.randf_range(0.0, 2.0)


## Off-duty officers are ignored by the witness system. Nothing sets this yet;
## shift rosters are a later phase.
func is_on_duty() -> bool:
	return true


func _process(delta: float) -> void:
	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = perception_interval
		_perceive()

	_state_timer -= delta
	_repath_timer -= delta

	match state:
		State.PATROL:
			_tick_patrol()
		State.RESPONDING:
			_tick_heading_to(WantedManager.last_known_position)
		State.PURSUING:
			_tick_pursuit()
		State.SEARCHING:
			_tick_search()
		State.RETURNING:
			_tick_heading_to(post_position)
		State.BUSTING:
			pass


# --- Perception ----------------------------------------------------------

func _perceive() -> void:
	if not WantedManager.is_wanted() or WantedManager.is_busting():
		return
	var player := GameManager.player
	if player == null:
		return

	if not WitnessSystem.can_see(self, player.global_position, sight_radius, view_angle):
		# Losing sight during a chase drops the officer into a search of wherever
		# the player was last actually seen.
		if state == State.PURSUING:
			_set_state(State.SEARCHING)
			_repath_timer = 0.0
		return

	WantedManager.notify_player_seen(player.global_position)

	var distance := global_position.distance_to(player.global_position)
	if WantedManager.can_arrest(distance, false):
		_set_state(State.BUSTING)
		stop()
		WantedManager.request_bust()
		return

	if state != State.PURSUING:
		_set_state(State.PURSUING)
		_repath_timer = 0.0


# --- State handlers ------------------------------------------------------

func _tick_patrol() -> void:
	set_running(false)
	if has_path() or _state_timer > 0.0:
		return
	var destination := _random_point_near(post_position, patrol_radius)
	if not walk_to(destination):
		_state_timer = 1.5


func _tick_heading_to(destination: Vector3) -> void:
	set_running(state != State.RETURNING)
	if _repath_timer > 0.0 and has_path():
		return
	_repath_timer = repath_interval
	if not walk_to(destination):
		_state_timer = 1.0


func _tick_pursuit() -> void:
	set_running(true)
	if _repath_timer > 0.0:
		return
	_repath_timer = repath_interval
	var player := GameManager.player
	if player != null:
		walk_to(player.global_position)


## Searching means combing the area around the last sighting, not walking to a
## single point and giving up.
func _tick_search() -> void:
	set_running(true)
	if has_path() and _state_timer > 0.0:
		return
	_state_timer = _rng.randf_range(2.5, 4.5)
	var target := _random_point_near(WantedManager.last_known_position, search_point_radius)
	if not walk_to(target):
		_state_timer = 1.0


# --- Reactions -----------------------------------------------------------

func _on_wanted_level_changed(level: int) -> void:
	if level <= 0:
		return
	if state == State.PURSUING or state == State.BUSTING:
		return
	# Only officers near enough answer the call, so a level 1 theft does not
	# summon the whole district.
	var distance := global_position.distance_to(WantedManager.last_known_position)
	if distance <= WantedManager.get_response_radius():
		_set_state(State.RESPONDING)
		_repath_timer = 0.0


func _on_wanted_cleared() -> void:
	if state == State.PATROL:
		return
	_set_state(State.RETURNING)
	_repath_timer = 0.0
	stop()


func _on_path_finished() -> void:
	match state:
		State.RETURNING:
			if global_position.distance_to(post_position) < 6.0:
				_set_state(State.PATROL)
			_state_timer = _rng.randf_range(idle_time_range.x, idle_time_range.y)
		State.RESPONDING:
			# Arrived at the call with nothing in sight: start looking around.
			_set_state(State.SEARCHING)
			_state_timer = 0.0
		State.PATROL:
			_state_timer = _rng.randf_range(idle_time_range.x, idle_time_range.y)
		_:
			_state_timer = 0.0


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)


func _random_point_near(origin: Vector3, radius: float) -> Vector3:
	if nav == null:
		return origin
	# Sample a few graph nodes and keep the first inside the radius, so patrols
	# and searches stay local instead of crossing the district.
	var fallback := nav.snap(NavGraph.Layer.WALK, origin)
	for i in 8:
		var candidate := nav.random_point(NavGraph.Layer.WALK, _rng)
		if candidate.distance_to(origin) <= radius:
			return candidate
	return fallback
