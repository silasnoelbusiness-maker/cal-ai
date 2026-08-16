class_name PoliceDriver
extends Node
## AI driver for a police car.
##
## Sits as a child of a Vehicle and feeds it the same throttle/steer/handbrake
## the player would — it does not touch the physics. That is the whole point of
## routing AI through `Vehicle.set_ai_input()`: the car police drive handles
## exactly like the car the player drives, and tuning one tunes both.
##
## Routing uses the road layer of the nav graph, so patrol cars stay on the
## carriageway instead of cutting across the park.

signal state_changed(state: State)
## Raised and lowered with the light bar. Nothing listens: the prototype has no
## audio at all, and a placeholder beep would be worse than silence. The state
## behind it is real, though, so a siren later is an AudioStreamPlayer3D on the
## car and one connection to this — no new logic and no new state to keep in
## step with the lights.
signal siren_changed(active: bool)

enum State { PARKED, RESPONDING, PURSUING, SEARCHING, RETURNING }

@export_group("Driving")
## Steering input saturates at this heading error.
@export var full_lock_angle: float = 38.0
## Above this heading error the car lifts off to get the nose round.
@export var slow_for_turn_angle: float = 62.0
@export var throttle_in_turn: float = 0.35
## How close to a waypoint counts as reaching it.
@export var waypoint_radius: float = 6.0
## Distance from the final target at which the car brakes to a stop.
@export var stopping_distance: float = 7.0
@export var repath_interval: float = 1.0
## Seconds of the suspect's motion the car steers ahead of while pursuing. Small
## on purpose: enough to cut a corner rather than trail the player's bumper,
## short enough that it never predicts its way into a wall.
@export var interception_time: float = 0.9
## Ceiling on how far ahead of the suspect the aim point may sit, so a fast car
## is never aimed at through a building.
@export var max_lead_distance: float = 14.0

@export_group("Perception")
@export var perception_interval: float = 0.25
@export var sight_radius: float = 42.0
## Full circle, for the same reason as the officer on foot: a crew already
## chasing someone is looking everywhere, and a heading-based cone made a car
## that had just turned lose its suspect for no good reason.
@export var view_angle: float = 360.0

@export_group("Recovery")
## Barely moving under throttle for this long means wedged.
@export var stuck_timeout: float = 1.6
@export var reverse_seconds: float = 0.9

var state: State = State.PARKED

var _car: Vehicle = null
var _nav: NavGraph = null
var _home: Transform3D
var _path: PackedVector3Array = PackedVector3Array()
var _index: int = 0
var _repath_timer: float = 0.0
var _perception_timer: float = 0.0
var _stuck_time: float = 0.0
var _reverse_time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _red_material: StandardMaterial3D = null
var _blue_material: StandardMaterial3D = null
var _beacon: OmniLight3D = null
var _blink_time: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_car = get_parent() as Vehicle
	if _car == null:
		push_error("PoliceDriver must be a child of a Vehicle.")
		set_physics_process(false)
		return

	_car.controller = Vehicle.Controller.POLICE_AI
	_car.add_to_group(&"police")
	_car.add_to_group(&"police_car")
	_home = _car.global_transform
	_nav = get_tree().get_first_node_in_group(&"nav_graph") as NavGraph

	_build_light_bar.call_deferred()

	WantedManager.level_changed.connect(_on_wanted_level_changed)
	WantedManager.wanted_cleared.connect(_on_wanted_cleared)


## Roof bar: two emissive blocks that alternate while the unit is responding.
## Cheap, and from the top-down camera it is the clearest signal that a car on
## screen is police and is currently after you.
func _build_light_bar() -> void:
	var bar := Node3D.new()
	bar.name = "LightBar"
	bar.position = Vector3(0.0, _car.data.get_total_height() + 0.06, 0.25)
	_car.add_child(bar)

	_red_material = CityKit.make_emissive_material(Color(0.35, 0.06, 0.07), 0.0, Color(1.0, 0.15, 0.15))
	_blue_material = CityKit.make_emissive_material(Color(0.06, 0.10, 0.35), 0.0, Color(0.25, 0.45, 1.0))
	CityKit.add_box(bar, "Red", Vector3(-0.34, 0.0, 0.0), Vector3(0.55, 0.16, 0.3), _red_material, false, false)
	CityKit.add_box(bar, "Blue", Vector3(0.34, 0.0, 0.0), Vector3(0.55, 0.16, 0.3), _blue_material, false, false)

	_beacon = OmniLight3D.new()
	_beacon.name = "Beacon"
	_beacon.position = Vector3(0.0, 0.25, 0.0)
	_beacon.omni_range = 13.0
	_beacon.shadow_enabled = false
	_beacon.light_energy = 0.0
	bar.add_child(_beacon)


func get_car() -> Vehicle:
	return _car


## True while the unit is out on a call — which is exactly when the light bar is
## flashing, so lights and siren can never disagree.
func is_siren_active() -> bool:
	return state != State.PARKED and state != State.RETURNING


func _physics_process(delta: float) -> void:
	_update_light_bar(delta)

	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = perception_interval
		_perceive()

	if state == State.PARKED:
		_car.set_ai_input(0.0, 0.0, true)
		return

	if _reverse_time > 0.0:
		_reverse_time -= delta
		_car.set_ai_input(-1.0, 0.0, false)
		return

	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_repath_timer = repath_interval
		_repath()

	_follow_path(delta)


## Alternates red and blue about twice a second while the unit is out on a call.
func _update_light_bar(delta: float) -> void:
	if _red_material == null:
		return
	var active := state != State.PARKED and state != State.RETURNING
	if not active:
		if _red_material.emission_energy_multiplier != 0.0:
			_red_material.emission_energy_multiplier = 0.0
			_blue_material.emission_energy_multiplier = 0.0
			_beacon.light_energy = 0.0
		return

	_blink_time += delta
	var on_red := fmod(_blink_time, 0.9) < 0.45
	_red_material.emission_energy_multiplier = 3.0 if on_red else 0.0
	_blue_material.emission_energy_multiplier = 0.0 if on_red else 3.0
	_beacon.light_color = Color(1.0, 0.2, 0.2) if on_red else Color(0.3, 0.5, 1.0)
	_beacon.light_energy = 3.0


# --- Perception ----------------------------------------------------------

func _perceive() -> void:
	if not WantedManager.is_wanted() or WantedManager.is_busting():
		return
	var player := GameManager.player
	if player == null:
		return

	if not WitnessSystem.can_see(_car, player.global_position, sight_radius, view_angle):
		if state == State.PURSUING:
			_set_state(State.SEARCHING)
			_repath_timer = 0.0
		return

	WantedManager.notify_player_seen(player.global_position)

	var distance := _car.global_position.distance_to(player.global_position)
	if WantedManager.can_arrest(distance, true):
		WantedManager.request_bust()
		return

	if state != State.PURSUING:
		_set_state(State.PURSUING)
		_repath_timer = 0.0


# --- Routing -------------------------------------------------------------

func _target_position() -> Vector3:
	match state:
		State.PURSUING:
			var player := GameManager.player
			if player == null:
				return WantedManager.last_known_position
			return predict_intercept(player)
		State.RESPONDING, State.SEARCHING:
			return WantedManager.last_known_position
		State.RETURNING:
			return _home.origin
		_:
			return _car.global_position


## Aims where the suspect is going rather than where they are — the simplest
## interception there is, `position + velocity * t`, clamped so it cannot lead
## the car through a wall. It only changes the aim point; routing still goes
## through the road graph, so a lead across a building is corrected by the path.
func predict_intercept(suspect: Node3D) -> Vector3:
	var lead := _suspect_velocity(suspect) * interception_time
	lead.y = 0.0
	if lead.length() > max_lead_distance:
		lead = lead.normalized() * max_lead_distance
	return suspect.global_position + lead


## A player on foot carries their own velocity; a player driving is a passenger
## of the car, so the car's is the one that means anything.
func _suspect_velocity(suspect: Node3D) -> Vector3:
	if suspect.has_method("get_vehicle"):
		var car := suspect.call("get_vehicle") as Node3D
		if car is Vehicle:
			return (car as Vehicle).velocity
	if suspect is CharacterBody3D:
		return (suspect as CharacterBody3D).velocity
	return Vector3.ZERO


func _repath() -> void:
	if _nav == null:
		return
	var route := _nav.find_path(NavGraph.Layer.ROAD, _car.global_position, _target_position())
	if route.size() < 2:
		_path = PackedVector3Array()
		return
	_path = route
	_index = 1


func _follow_path(delta: float) -> void:
	var target := _target_position()
	var distance_to_target := _car.global_position.distance_to(target)

	# Close enough to drive straight at it; the road graph is too coarse for the
	# last few metres.
	var aim := target
	if _index < _path.size() and distance_to_target > stopping_distance:
		while _index < _path.size() and _car.global_position.distance_to(_path[_index]) < waypoint_radius:
			_index += 1
		if _index < _path.size():
			aim = _path[_index]

	if state == State.RETURNING and distance_to_target < 4.0:
		_set_state(State.PARKED)
		return

	var to_aim := aim - _car.global_position
	to_aim.y = 0.0
	if to_aim.length_squared() < 0.01:
		_car.set_ai_input(0.0, 0.0, true)
		return

	var forward := -_car.global_transform.basis.z
	forward.y = 0.0
	var heading_error := forward.signed_angle_to(to_aim.normalized(), Vector3.UP)
	var steer := clampf(heading_error / deg_to_rad(full_lock_angle), -1.0, 1.0)

	var throttle := 1.0
	if absf(heading_error) > deg_to_rad(slow_for_turn_angle):
		throttle = throttle_in_turn
	# Ease off approaching the target so the car stops beside it rather than
	# shunting it down the street.
	if distance_to_target < stopping_distance:
		throttle = -0.6 if _car.get_forward_speed() > 1.5 else 0.0

	_car.set_ai_input(throttle, steer, false)
	_check_stuck(delta, throttle)


## Wedged cars reverse briefly and try again, which is enough to get off a kerb
## or out from behind a street light.
func _check_stuck(delta: float, throttle: float) -> void:
	if throttle <= 0.05 or absf(_car.get_forward_speed()) > 1.0:
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time < stuck_timeout:
		return
	_stuck_time = 0.0
	_reverse_time = reverse_seconds
	_repath_timer = 0.0


# --- Reactions -----------------------------------------------------------

func _on_wanted_level_changed(level: int) -> void:
	if level <= 0 or state == State.PURSUING:
		return
	var distance := _car.global_position.distance_to(WantedManager.last_known_position)
	if distance <= WantedManager.get_response_radius():
		_set_state(State.RESPONDING)
		_repath_timer = 0.0


func _on_wanted_cleared() -> void:
	if state == State.PARKED:
		return
	_set_state(State.RETURNING)
	_repath_timer = 0.0


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	var siren_was := is_siren_active()
	state = new_state
	if state == State.PARKED:
		_car.halt()
	state_changed.emit(state)
	if is_siren_active() != siren_was:
		siren_changed.emit(is_siren_active())
