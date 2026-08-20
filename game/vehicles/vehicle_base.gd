class_name Vehicle
extends CharacterBody3D
## Arcade-driving vehicle base.
##
## Deliberately a CharacterBody3D rather than Godot's raycast VehicleBody3D:
## the brief asks for arcade handling that never flips, never spins out and
## never bounces, and a kinematic body gives that by construction instead of by
## tuning a rigid body until it behaves. Speed along the car's own forward axis
## is the single state variable; steering rotates the body, and `move_and_slide`
## handles the world.
##
## Forward is -Z, the Godot convention.
##
## Everything model-specific lives in VehicleData, so a van or a police car is a
## new .tres plus a new scene, not a new script. Ownership is per-instance
## (below) because all sedans share one VehicleData but not one owner.

signal driver_entered(driver: Node3D)
signal driver_exited(driver: Node3D)
signal health_changed(health: float, max_health: float)
signal disabled()
signal collided(impact_speed: float)
signal hit_pedestrian(victim: Node3D, impact_speed: float)
## Somebody has been pulled out of this car and it has changed hands.
signal carjacked(thief: Node3D, ejected_driver: Node3D)

enum OwnerType { PLAYER, NPC, PUBLIC, COMPANY }
## Who is sat in the car when the player finds it. This is about the *person*,
## not about the control scheme: an occupied car has somebody to pull out of it,
## which is the difference between stealing a parked car and carjacking one.
enum DriverType { NONE, CIVILIAN, POLICE }
## EMPTY is a parked car; SEATED is one with somebody in it; FLED is one whose
## driver has been pulled out and is running away.
enum DriverState { EMPTY, SEATED, FLED }
## Who is at the wheel. PLAYER means "nobody, until a person gets in"; the AI
## values mean an AI driver node is feeding set_ai_input() and the player cannot
## take the car. Adding TAXI_AI or DELIVERY_AI later is a new entry here plus a
## new driver node — nothing in this script has to change.
enum Controller { PLAYER, TRAFFIC_AI, POLICE_AI }

## Speeds above this (m/s) are too fast to step out of.
const SAFE_EXIT_SPEED := 6.0
## Beam strength once the headlights are lit.
const HEADLIGHT_ENERGY := 5.0
## Below this speed the car is manoeuvring, and touching somebody is not an
## impact at all.
const PEDESTRIAN_CONTACT_SPEED := 1.2
## Seconds between checks of who is under the bumper. Vehicles do not collide
## with the NPC layer — a crowd that physically blocked traffic would jam the
## roads solid — so contact is resolved by an area poll instead, which is what
## stops cars simply passing through people.
const IMPACT_POLL_INTERVAL := 0.08
## Speed kept after knocking somebody down, and after a nudge. A body does not
## stop a car, but the hit has to read as one.
const KNOCKDOWN_SPEED_RETENTION := 0.75
const NUDGE_SPEED_RETENTION := 0.9
## The person pulled out of a carjacked car carries on as an ordinary civilian,
## so they are the ordinary civilian scene rather than anything bespoke.
##
## Loaded on first use rather than preloaded: the pedestrian scene's script and
## this one refer to each other's types, and a preload here makes that a cycle
## Godot refuses to resolve ("Parse Error: Busy").
const OCCUPANT_SCENE_PATH := "res://npc/pedestrian.tscn"
static var _occupant_scene: PackedScene = null
## Candidate exit spots in local space, tried in order: driver's side first,
## then passenger's, then the corners, then front and back.
const EXIT_OFFSETS: Array[Vector3] = [
	Vector3(-1.75, 0.0, 0.1),
	Vector3(1.75, 0.0, 0.1),
	Vector3(-1.75, 0.0, 2.2),
	Vector3(1.75, 0.0, 2.2),
	Vector3(0.0, 0.0, 3.4),
	Vector3(0.0, 0.0, -3.4),
]

@export var data: VehicleData

## A car on a showroom floor rather than a car in the world. See _ready().
@export var display_only: bool = false

@export_group("Ownership")
@export var owner_type: OwnerType = OwnerType.NPC
## Who owns it. "player" for the player's own car; anything else for NPCs.
@export var owner_id: StringName = &"npc"
## Stable id for the save file. Empty means this vehicle is not persisted.
@export var save_id: StringName = &""

@export_group("Occupant")
@export var driver_type: DriverType = DriverType.NONE
## Identifies the person in the seat, so the pedestrian who gets out of a
## carjacked car is demonstrably the same individual who was driving it.
@export var driver_id: StringName = &""
@export var driver_state: DriverState = DriverState.EMPTY
## Colour the ejected driver wears, matched to the figure sat in the seat.
@export var driver_color: Color = Color(0.478, 0.494, 0.541)
## Fastest a car can be moving and still be dragged out of. Stopped and crawling
## traffic can be taken; anything at speed cannot, which is what makes waiting
## for a red light the way to do it.
@export var carjack_max_speed: float = 4.0

@export_group("Pedestrian impacts")
## How long after hitting somebody the driver has to stop before it counts as
## having left the scene, and how far away counts as gone.
@export var hit_and_run_grace: float = 6.0
@export var hit_and_run_distance: float = 25.0

## Set by an AI driver node when it attaches itself. See Controller above.
var controller: Controller = Controller.PLAYER

@onready var _body_root: Node3D = $Body
@onready var _collision: CollisionShape3D = $Collision
@onready var _seat: Marker3D = $Seat
@onready var _door: VehicleDoor = $Door
@onready var _impact_zone: Area3D = $ImpactZone
@onready var _headlights: SpotLight3D = $Headlights

## The tail lamp material, brightened under braking. Held rather than looked up
## so a brake light is two writes rather than a node search per frame.
var _tail_material: StandardMaterial3D = null
var _braking: bool = false

var health: float = 100.0
var _driver: Node3D = null
## Signed speed along the car's forward axis. Negative is reverse.
var _forward_speed: float = 0.0
var _steer_input: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _front_wheels: Array[Node3D] = []
## Theft is reported once per vehicle, not once per time the player gets in.
var _theft_reported: bool = false
## Where this car was parked at load, so a stolen one can be put back.
var _spawn_transform: Transform3D
var _impact_timer: float = 0.0
## The last inputs actually applied, so the audio can follow the car without
## re-deriving what the driver or the AI asked for.
var _audio: VehicleAudio = null

var _last_throttle: float = 0.0
var _last_steer: float = 0.0
var _last_handbrake: bool = false

var _ai_throttle: float = 0.0
var _ai_steer: float = 0.0
var _ai_handbrake: bool = false


func _ready() -> void:
	if data == null:
		push_error("Vehicle '%s' has no VehicleData." % name)
		set_physics_process(false)
		return

	health = data.max_health
	_spawn_transform = global_transform

	# A showroom car is a picture of a car. It is deliberately not in the
	# vehicle group — a car on a plinth is not traffic, is not somewhere the
	# player can be dragged out of, and must not be stealable — and it has no
	# engine noise, no door and no physics of its own.
	if display_only:
		# The group is set on the scene's root node rather than here, so a
		# showroom car arrives already in it and has to be taken back out.
		# Nothing that sweeps the city for traffic, theft or parking should
		# ever see a car on a plinth.
		remove_from_group(&"vehicle")
		_build_body()
		set_physics_process(false)
		collision_layer = 0
		collision_mask = 0
		_door.queue_free()
		_impact_zone.queue_free()
		return

	add_to_group(&"vehicle")
	if save_id != &"":
		add_to_group(&"saveable")

	_build_body()

	# The car's own noise: engine, tyres, and a siren if it is a patrol car.
	_audio = VehicleAudio.new()
	_audio.name = "Audio"
	add_child(_audio)
	_audio.setup(self)
	_build_collision()
	_build_impact_zone()
	_door.setup(self)
	health_changed.emit(health, data.max_health)


# --- Public API ----------------------------------------------------------

func get_driver() -> Node3D:
	return _driver


func has_driver() -> bool:
	return _driver != null


## True while the car is running: somebody is in it, or an AI is driving it, and
## it is not wrecked. What the engine audio keys off.
func is_engine_running() -> bool:
	return not is_disabled() and (_driver != null or is_ai_controlled())


func get_throttle_input() -> float:
	return _last_throttle


func get_steer_input() -> float:
	return _last_steer


func is_handbrake_down() -> bool:
	return _last_handbrake


func is_disabled() -> bool:
	return health <= 0.0


func is_player_owned() -> bool:
	return owner_type == OwnerType.PLAYER


## Signed speed along the forward axis, in m/s.
func get_forward_speed() -> float:
	return _forward_speed


## Speed the camera reads to widen the view. Same method the player exposes, so
## the camera rig needs no special case for vehicles.
func get_planar_speed() -> float:
	return absf(_forward_speed)


func get_speed_kmh() -> float:
	return absf(_forward_speed) * 3.6


## Direction of travel on the ground plane — the nose, or the tail in reverse.
## The camera's look-ahead reads this; a reversing car should show the player
## where it is backing into.
func get_facing() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if _forward_speed < 0.0:
		forward = -forward
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD


func get_display_name() -> String:
	return data.display_name if data != null else "Vehicle"


func is_ai_controlled() -> bool:
	return controller != Controller.PLAYER


func can_be_entered_by(_who: Node3D) -> bool:
	return _driver == null and not is_disabled() and not is_ai_controlled()


func has_occupant() -> bool:
	return driver_state == DriverState.SEATED


## Whether this car can be taken off the person driving it right now.
##
## Deliberately strict. A car doing 40 cannot be opened, a wreck is not worth
## taking, and only civilians are dragged out — a police car with an officer in
## it is a fight, which is not this phase.
func can_be_carjacked_by(who: Node3D) -> bool:
	if who == null or is_disabled():
		return false
	if driver_type != DriverType.CIVILIAN or driver_state != DriverState.SEATED:
		return false
	if _driver != null:
		return false
	return get_planar_speed() <= carjack_max_speed


## Pulls the driver out and takes their place. Returns false if the car was not
## takeable, so the caller can fall back to the ordinary enter path.
func carjack(thief: Node3D) -> bool:
	if not can_be_carjacked_by(thief):
		return false

	var scene := global_position
	var victim := _eject_occupant(thief)
	_release_ai_driver()

	# Filed as a carjacking rather than a theft, and never as both: getting in is
	# part of the same act.
	_theft_reported = true
	var record := CrimeManager.report_crime(
		CrimeManager.CrimeType.CARJACKING, scene, thief, self
	)
	# The victim was sat in it. There is no perception test to pass.
	WitnessSystem.witness_directly(record, victim)

	carjacked.emit(thief, victim)
	return enter(thief)


## Feeds the same three inputs the player supplies. Keeping AI on this path
## rather than a parallel physics routine means police cars handle exactly like
## the player's car.
func set_ai_input(throttle: float, steer: float, handbrake: bool) -> void:
	_ai_throttle = clampf(throttle, -1.0, 1.0)
	_ai_steer = clampf(steer, -1.0, 1.0)
	_ai_handbrake = handbrake


## Puts the car back where it started, upright and stopped. Used when a stolen
## car is recovered after an arrest.
func return_to_spawn() -> void:
	halt()
	global_transform = _spawn_transform


## Takes the driver's seat. Returns false if the car is occupied or wrecked.
func enter(driver: Node3D) -> bool:
	if not can_be_entered_by(driver) or driver == null:
		return false
	if not driver.has_method("enter_vehicle"):
		return false

	_driver = driver
	driver.call("enter_vehicle", self)
	_door.available = false
	# The day/night cycle owns whether it is dark enough for lights; the driver
	# owns whether this particular car's lights are on at all.
	_headlights.light_energy = HEADLIGHT_ENERGY

	AudioManager.play_at(&"car_door", global_position, AudioBuses.VEHICLES, -10.0)
	_hand_camera_to(self)
	_report_theft_if_needed(driver)
	driver_entered.emit(driver)
	return true


## Steps out. Returns false when it is not safe to — too fast, mainly.
## `force` skips the speed check; the save system uses it to clear the seat
## before restoring a position.
func exit_driver(force: bool = false) -> bool:
	if _driver == null:
		return false
	if not force and get_planar_speed() > SAFE_EXIT_SPEED:
		GameManager.notify("SLOW DOWN TO GET OUT", GameManager.Tone.BAD)
		return false

	var leaving := _driver
	var spot := _find_exit_point()

	_driver = null
	halt()
	_door.available = true
	_headlights.light_energy = 0.0

	AudioManager.play_at(&"car_door", global_position, AudioBuses.VEHICLES, -12.0)
	leaving.call("exit_vehicle", spot)
	_hand_camera_to(leaving)
	driver_exited.emit(leaving)
	return true


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or data == null:
		return
	var was_alive := not is_disabled()
	health = clampf(health - amount, 0.0, data.max_health)
	health_changed.emit(health, data.max_health)
	if was_alive and is_disabled():
		_forward_speed = 0.0
		disabled.emit()
		GameManager.notify("ENGINE DEAD", GameManager.Tone.BAD)


func repair() -> void:
	if data == null:
		return
	health = data.max_health
	health_changed.emit(health, data.max_health)


## Sets the damage outright, without treating the change as a crash. The
## registry uses it when a car it owns comes back into the world carrying the
## dents its record says it has.
func set_health(value: float) -> void:
	if data == null:
		return
	health = clampf(value, 0.0, data.max_health)
	health_changed.emit(health, data.max_health)


## The mechanic's version of repair(): the same result, named for the caller so
## a bill and a debug key do not read as the same thing.
func restore_health() -> void:
	repair()


## Brings the car to a dead stop without touching where it is or which way it
## faces. Used by the reset key and by the save system.
func halt() -> void:
	_forward_speed = 0.0
	_steer_input = 0.0
	velocity = Vector3.ZERO


## Development aid: drops the car upright on the nearest clear ground. A
## kinematic body cannot roll over, but it can still end up wedged in geometry.
## Bound to F8; delete this method and its input action for a release build.
func debug_reset() -> void:
	halt()
	rotation = Vector3(0.0, rotation.y, 0.0)
	global_position += Vector3.UP * 0.6
	GameManager.notify("VEHICLE RESET", GameManager.Tone.INFO)


# --- Driving -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var steer := 0.0
	var handbrake := false

	if not is_disabled():
		if is_ai_controlled():
			throttle = _ai_throttle
			steer = _ai_steer
			handbrake = _ai_handbrake
		elif _driver != null:
			throttle = Input.get_axis("move_back", "move_forward")
			steer = Input.get_axis("move_right", "move_left")
			handbrake = Input.is_action_pressed("handbrake")

	_last_throttle = throttle
	_last_steer = steer
	_last_handbrake = handbrake

	_update_speed(throttle, handbrake, delta)
	_update_steering(steer, handbrake, delta)
	_update_brake_lights(throttle, handbrake)

	var forward := -global_transform.basis.z
	var speed_before := _forward_speed
	velocity = forward * _forward_speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta

	move_and_slide()
	_resolve_collisions(speed_before, delta)
	_check_pedestrian_impacts(delta)
	_update_wheels(delta)

	# The driver rides along, so their world position stays meaningful for the
	# HUD, for saves, and for working out where to put them when they get out.
	if _driver != null:
		_driver.global_position = _seat.global_position


func _update_speed(throttle: float, handbrake: bool, delta: float) -> void:
	if handbrake:
		_forward_speed = move_toward(
			_forward_speed, 0.0, data.handbrake_deceleration * delta
		)
		return

	if throttle > 0.01:
		# Throttle while rolling backwards is a brake, not an accelerator.
		var rate := data.brake_deceleration if _forward_speed < 0.0 else data.acceleration
		_forward_speed = move_toward(_forward_speed, data.max_speed, rate * delta)
	elif throttle < -0.01:
		var rate := data.brake_deceleration if _forward_speed > 0.0 else data.acceleration
		_forward_speed = move_toward(_forward_speed, -data.max_reverse_speed, rate * delta)
	else:
		_forward_speed = move_toward(_forward_speed, 0.0, data.engine_braking * delta)


## Steering authority falls off with speed, and vanishes at a crawl so the car
## never pivots on the spot.
func _update_steering(steer: float, handbrake: bool, delta: float) -> void:
	_steer_input = move_toward(_steer_input, steer, data.steer_response * delta)
	if is_zero_approx(_steer_input):
		return

	var speed := absf(_forward_speed)
	if speed < data.min_speed_to_steer:
		return

	var speed_ratio := clampf(speed / maxf(data.max_speed, 0.01), 0.0, 1.0)
	var rate := lerpf(data.steer_rate_low, data.steer_rate_high, speed_ratio)
	if handbrake:
		rate *= data.handbrake_steer_bonus

	# Ease steering in between min_speed_to_steer and full_steer_speed, so
	# pulling away from a kerb is smooth rather than a sudden snap.
	var authority := clampf(
		(speed - data.min_speed_to_steer)
		/ maxf(data.full_steer_speed - data.min_speed_to_steer, 0.01),
		0.0,
		1.0
	)
	# Reversing steers the other way, like a real car.
	var direction := signf(_forward_speed)
	rotate_y(_steer_input * rate * authority * direction * delta)


## Re-derives speed from the movement that actually happened, so hitting a wall
## scrubs speed instead of grinding along at full throttle, and glancing blows
## just slide.
func _resolve_collisions(speed_before: float, delta: float) -> void:
	var hardest_impact := 0.0

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var normal := collision.get_normal()
		# Ignore the ground; only walls and props count as impacts.
		if absf(normal.y) > 0.5:
			continue
		var into_wall := -normal.dot(-global_transform.basis.z) * speed_before
		hardest_impact = maxf(hardest_impact, into_wall)

	if hardest_impact <= 0.0:
		return

	var travelled := velocity * delta
	var actual_forward := (-global_transform.basis.z).dot(
		Vector3(travelled.x, 0.0, travelled.z)
	) / maxf(delta, 0.0001)
	# A head-on hit keeps only a fraction of the speed; a scrape keeps most of
	# whatever direction it actually managed to move.
	_forward_speed = lerpf(actual_forward, _forward_speed * data.impact_speed_retention, 0.5)

	collided.emit(hardest_impact)
	# Graded by how hard the hit was, and rate-limited inside the audio, so
	# scraping along a wall is one thump rather than one per physics frame.
	if _audio != null:
		_audio.report_impact(hardest_impact)
	# And a knock to the camera, but only for the car the player is in: a
	# traffic shunt three streets away should not move the view.
	if _driver != null and _driver == GameManager.player:
		var rig := get_tree().get_first_node_in_group(&"camera_rig") as TopDownCamera
		if rig != null:
			rig.add_shake(clampf(hardest_impact / 18.0, 0.0, 1.0))
	if hardest_impact > data.damage_speed_threshold:
		apply_damage((hardest_impact - data.damage_speed_threshold) * data.damage_per_impact_speed)


## Resolves contact with people. Polled rather than signalled, because
## `body_entered` only fires on the frame someone crosses the boundary — a
## pedestrian already stood in front of a parked car that then pulls away would
## never trigger one.
func _check_pedestrian_impacts(delta: float) -> void:
	_impact_timer -= delta
	if _impact_timer > 0.0:
		return
	_impact_timer = IMPACT_POLL_INTERVAL

	var speed := get_planar_speed()
	if speed < PEDESTRIAN_CONTACT_SPEED:
		return

	for body in _impact_zone.get_overlapping_bodies():
		var walker := body as Pedestrian
		if walker == null or walker.is_down():
			continue

		var direction := walker.global_position - global_position
		direction.y = 0.0
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()

		var floored := walker.knock_down(speed, direction)
		_forward_speed *= KNOCKDOWN_SPEED_RETENTION if floored else NUDGE_SPEED_RETENTION
		hit_pedestrian.emit(walker, speed)
		if floored:
			_report_pedestrian_incident(walker, speed)


## Running somebody over is filed as an incident, not a crime report: the brief
## is explicit that Phase F must not build the wanted response around it yet, and
## `report_crime` is what the witness system listens to.
func _report_pedestrian_incident(victim: Node3D, speed: float) -> void:
	if _driver == null or _driver != GameManager.player:
		return
	var scene := global_position
	CrimeManager.log_incident(
		CrimeManager.CrimeType.VEHICULAR_ASSAULT, scene, _driver, victim
	)
	GameManager.notify("PEDESTRIAN HIT", GameManager.Tone.BAD)
	_watch_for_hit_and_run(scene, victim)


## A hit only becomes a hit-and-run once the driver is demonstrably gone. Stop,
## or get out, and nothing further is filed.
func _watch_for_hit_and_run(scene: Vector3, victim: Node3D) -> void:
	await get_tree().create_timer(hit_and_run_grace).timeout
	if not is_inside_tree() or _driver == null:
		return
	if global_position.distance_to(scene) < hit_and_run_distance:
		return
	CrimeManager.log_incident(CrimeManager.CrimeType.HIT_AND_RUN, scene, _driver, victim)


## Front wheels visibly turn with the steering — cheap, and it reads clearly
## from the top-down camera.
func _update_wheels(delta: float) -> void:
	if _front_wheels.is_empty():
		return
	var target := _steer_input * 0.5
	for wheel in _front_wheels:
		wheel.rotation.y = lerp_angle(wheel.rotation.y, target, 12.0 * delta)


# --- Enter / exit helpers ------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _driver == null:
		return
	if event.is_action_pressed("enter_vehicle"):
		exit_driver()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("debug_reset_vehicle"):
		debug_reset()
		get_viewport().set_input_as_handled()


## Tries each candidate spot, keeping the first that has ground under it and no
## wall, prop or other car in the way. Falls back to the seat so the player can
## never be stranded inside geometry with no way out.
func _find_exit_point() -> Transform3D:
	var space := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.5

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# World + curbs + vehicles: everything solid a person could be pushed into.
	query.collision_mask = (1 << 0) | (1 << 3) | (1 << 5)
	query.exclude = [get_rid()]

	for offset in EXIT_OFFSETS:
		var candidate := global_transform * offset

		var ray := PhysicsRayQueryParameters3D.create(
			candidate + Vector3.UP * 2.0, candidate + Vector3.DOWN * 3.0
		)
		ray.collision_mask = (1 << 0) | (1 << 5)
		ray.exclude = [get_rid()]
		var ground := space.intersect_ray(ray)
		if ground.is_empty():
			continue

		var stand := (ground["position"] as Vector3) + Vector3.UP * 0.05
		query.transform = Transform3D(Basis(), stand + Vector3.UP * 0.9)
		if not space.intersect_shape(query, 1).is_empty():
			continue

		return Transform3D(global_transform.basis, stand)

	return Transform3D(global_transform.basis, _seat.global_position)


## Puts the person who was driving onto the pavement, frightened and about to
## run. They are a normal Pedestrian from this point on: they can be knocked
## down, they can witness what happens next, and they wander off if left alone.
func _eject_occupant(threat: Node3D) -> Pedestrian:
	var spot := _find_exit_point()

	if _occupant_scene == null:
		_occupant_scene = load(OCCUPANT_SCENE_PATH) as PackedScene
	var walker: Pedestrian = _occupant_scene.instantiate()
	walker.name = "EjectedDriver_%s" % (driver_id if driver_id != &"" else name)
	walker.body_color = driver_color
	walker.accent_color = driver_color.darkened(0.35)

	# Ejected drivers join the crowd if there is one, so they are recycled and
	# counted with everybody else rather than living under a car.
	var host := get_tree().get_first_node_in_group(&"crowd") as Node
	if host == null:
		host = get_parent()
	host.add_child(walker)
	walker.global_position = spot.origin + Vector3.UP * 0.05

	driver_state = DriverState.FLED
	_refresh_occupant()
	# A short fear beat first, so the player sees them react before they run.
	walker.enter_fear(threat.global_position if threat != null else global_position, 0.9)
	return walker


## Detaches whatever AI was driving and hands the car back to the enter/exit
## path. The node is stopped before it is freed, so it cannot feed one more
## frame of throttle after the player is in the seat.
func _release_ai_driver() -> void:
	for child in get_children():
		if child is TrafficDriver or child is PoliceDriver:
			child.set_physics_process(false)
			child.queue_free()
	controller = Controller.PLAYER
	set_ai_input(0.0, 0.0, false)
	halt()


func _hand_camera_to(target: Node3D) -> void:
	var rig := get_tree().get_first_node_in_group(&"camera_rig") as TopDownCamera
	if rig != null:
		# Not snapped: the rig eases across, which is the handover the brief asks
		# for in both directions.
		rig.set_target(target, false)


func _report_theft_if_needed(driver: Node3D) -> void:
	if owner_type != OwnerType.NPC or _theft_reported:
		return
	_theft_reported = true
	CrimeManager.report_crime(
		CrimeManager.CrimeType.VEHICLE_THEFT, global_position, driver, self
	)


# --- Placeholder body ----------------------------------------------------

## Builds the stand-in chassis from VehicleData dimensions. Every vehicle type
## gets a readable shape for free, and swapping in real art later means
## replacing this one method.
func _build_body() -> void:
	var clearance := data.ground_clearance
	var lower_y := clearance + data.body_height * 0.5
	var cabin_y := clearance + data.body_height + data.cabin_height * 0.5

	var body_mat := CityKit.make_material(data.body_color, 0.38, 0.28)
	var dark_mat := CityKit.make_material(data.body_color.darkened(0.35), 0.42, 0.22)
	var trim_mat := CityKit.make_material(data.trim_color, 0.62)
	var glass_mat := CityKit.make_material(data.glass_color, 0.08, 0.42)
	var head_mat := CityKit.make_emissive_material(Color(0.98, 0.94, 0.82), 1.4)
	var tail_mat := CityKit.make_emissive_material(Color(0.72, 0.14, 0.13), 1.6)
	var chrome := Palette.of(&"metal_pale")

	var length := data.body_length
	var width := data.body_width
	var shape := _profile_shape()

	# --- Lower body: a main box with a tapered nose and tail ---------------
	CityKit.add_box(
		_body_root, "Chassis", Vector3(0.0, lower_y, 0.0),
		Vector3(width, data.body_height, length * 0.90), body_mat, false
	)
	# Bonnet and boot are shallower than the body, which is what stops a car
	# reading as one long brick from the elevated camera.
	CityKit.add_box(
		_body_root, "Bonnet",
		Vector3(0.0, lower_y + data.body_height * float(shape["nose_rise"]), -length * 0.42),
		Vector3(width * 0.96, data.body_height * float(shape["nose_height"]), length * 0.22),
		body_mat, false
	)
	CityKit.add_box(
		_body_root, "Boot",
		Vector3(0.0, lower_y + data.body_height * float(shape["tail_rise"]), length * 0.42),
		Vector3(width * 0.96, data.body_height * float(shape["tail_height"]), length * 0.22),
		body_mat, false
	)
	# A skirt below the doors, in a darker shade. Two tones down the side is the
	# cheapest thing that stops a car looking like a painted box.
	CityKit.add_box(
		_body_root, "Sill", Vector3(0.0, clearance + 0.06, 0.0),
		Vector3(width * 1.01, 0.12, length * 0.72), trim_mat, false, false
	)

	# --- Greenhouse -------------------------------------------------------
	var cabin_z := length * data.cabin_offset
	var cabin_len: float = length * float(shape["cabin_length"])
	var cabin_w := width * 0.88
	# The glass box, then a body-coloured roof on top of it and pillars at the
	# corners: windows that read as windows rather than as a dark stripe.
	CityKit.add_box(
		_body_root, "Cabin", Vector3(0.0, cabin_y, cabin_z),
		Vector3(cabin_w, data.cabin_height, cabin_len), glass_mat, false
	)
	CityKit.add_box(
		_body_root, "Roof",
		Vector3(0.0, cabin_y + data.cabin_height * 0.5, cabin_z + length * 0.02),
		Vector3(cabin_w * 0.96, 0.10, cabin_len * float(shape["roof_length"])),
		body_mat, false
	)
	for side: float in [-1.0, 1.0]:
		# B-pillar: splits the side glass into a front and a rear window.
		CityKit.add_box(
			_body_root, "Pillar%d" % int(side),
			Vector3(side * cabin_w * 0.5, cabin_y, cabin_z),
			Vector3(0.05, data.cabin_height * 0.98, cabin_len * 0.10),
			body_mat, false, false
		)
		# Wing mirror. Tiny, and it is one of the strongest "this is a car"
		# cues there is in silhouette.
		CityKit.add_box(
			_body_root, "Mirror%d" % int(side),
			Vector3(
				side * (width * 0.5 + 0.07), cabin_y - data.cabin_height * 0.18,
				cabin_z - cabin_len * 0.44
			),
			Vector3(0.14, 0.07, 0.10), dark_mat, false, false
		)

	# --- Nose and tail furniture ------------------------------------------
	CityKit.add_box(
		_body_root, "Grille",
		Vector3(0.0, clearance + data.body_height * 0.42, -length * 0.5 - 0.01),
		Vector3(width * 0.52, data.body_height * 0.34, 0.06), trim_mat, false, false
	)
	for pair in [["BumperFront", -1.0], ["BumperRear", 1.0]]:
		CityKit.add_box(
			_body_root, pair[0],
			Vector3(0.0, clearance + 0.20, (length * 0.5 - 0.06) * float(pair[1])),
			Vector3(width * 1.02, 0.24, 0.22), trim_mat, false
		)
	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			_body_root, "Headlight%d" % int(side),
			Vector3(
				side * width * 0.33, clearance + data.body_height * 0.74,
				-length * 0.5 - 0.02
			),
			Vector3(width * 0.24, 0.14, 0.08), head_mat, false, false
		)
		CityKit.add_box(
			_body_root, "Taillight%d" % int(side),
			Vector3(
				side * width * 0.33, clearance + data.body_height * 0.74,
				length * 0.5 + 0.02
			),
			Vector3(width * 0.26, 0.12, 0.08), tail_mat, false, false
		)
	_tail_material = tail_mat

	if data.livery == VehicleData.Livery.POLICE:
		_build_police_livery(lower_y, cabin_y)

	_build_occupant(cabin_y)
	_build_wheels(trim_mat, chrome)


## Per-profile proportions. Everything here is a fraction of the numbers on the
## VehicleData, so a van and a coupe differ in shape without differing in units.
func _profile_shape() -> Dictionary:
	match data.body_profile:
		VehicleData.Profile.VAN:
			return {
				"nose_rise": 0.30, "nose_height": 0.72, "tail_rise": 0.34,
				"tail_height": 1.06, "cabin_length": 0.62, "roof_length": 1.02,
				"arch": 0.30,
			}
		VehicleData.Profile.SUV:
			return {
				"nose_rise": 0.24, "nose_height": 0.80, "tail_rise": 0.26,
				"tail_height": 0.92, "cabin_length": 0.52, "roof_length": 0.92,
				"arch": 0.34,
			}
		VehicleData.Profile.COUPE:
			return {
				"nose_rise": -0.10, "nose_height": 0.56, "tail_rise": -0.06,
				"tail_height": 0.60, "cabin_length": 0.36, "roof_length": 0.66,
				"arch": 0.26,
			}
		VehicleData.Profile.HATCHBACK:
			return {
				"nose_rise": 0.04, "nose_height": 0.66, "tail_rise": 0.16,
				"tail_height": 0.90, "cabin_length": 0.48, "roof_length": 0.86,
				"arch": 0.28,
			}
		VehicleData.Profile.CRUISER:
			return {
				"nose_rise": 0.02, "nose_height": 0.70, "tail_rise": 0.04,
				"tail_height": 0.72, "cabin_length": 0.46, "roof_length": 0.78,
				"arch": 0.28,
			}
		_:
			return {
				"nose_rise": 0.02, "nose_height": 0.68, "tail_rise": 0.04,
				"tail_height": 0.70, "cabin_length": 0.44, "roof_length": 0.76,
				"arch": 0.28,
			}


## Tail lamps glow harder while the car is slowing. Two lines, and it is what
## makes a queue of traffic at a red light read as traffic stopping rather than
## as cars that happen to be still.
func _update_brake_lights(throttle: float, handbrake: bool) -> void:
	if _tail_material == null:
		return
	var braking := handbrake or (throttle < -0.05 and _forward_speed > 0.4)
	if braking == _braking:
		return
	_braking = braking
	_tail_material.emission_energy_multiplier = 4.2 if braking else 1.6


## Police paint: white door panels down each side and a dark bonnet, which is
## what makes a patrol car identifiable from directly above before its lights
## are even on.
func _build_police_livery(lower_y: float, cabin_y: float) -> void:
	var white := Palette.of(&"metal_pale")
	var dark := CityKit.make_material(Color(0.114, 0.129, 0.176), 0.45, 0.20)
	var length := data.body_length
	var width := data.body_width

	for side: float in [-1.0, 1.0]:
		CityKit.add_box(
			_body_root, "LiveryDoor%d" % int(side),
			Vector3(side * (width * 0.5 + 0.01), lower_y + data.body_height * 0.06, 0.0),
			Vector3(0.03, data.body_height * 0.62, length * 0.44), white, false, false
		)
	CityKit.add_box(
		_body_root, "LiveryBonnet",
		Vector3(0.0, lower_y + data.body_height * 0.52, -length * 0.30),
		Vector3(width * 0.62, 0.03, length * 0.26), dark, false, false
	)
	CityKit.add_box(
		_body_root, "LiveryRoof",
		Vector3(0.0, cabin_y + data.cabin_height * 0.5 + 0.06, data.cabin_offset * length),
		Vector3(width * 0.60, 0.03, length * 0.16), white, false, false
	)


## A head and shoulders behind the glass. Without it an occupied car and a
## parked one look identical from the top-down camera, and the player has no way
## to tell which one they are walking up to.
func _build_occupant(cabin_y: float) -> void:
	var figure := Node3D.new()
	figure.name = "Occupant"
	# Forward of the roof panel, so the figure reads through the windscreen from
	# directly above rather than being hidden under the roof.
	figure.position = Vector3(-data.body_width * 0.2, cabin_y - 0.08, -data.body_length * 0.14)
	_body_root.add_child(figure)

	var cloth := CityKit.make_material(driver_color, 0.85)
	CityKit.add_box(figure, "Shoulders", Vector3.ZERO, Vector3(0.46, 0.3, 0.3), cloth, false, false)
	CityKit.add_box(
		figure, "Head", Vector3(0.0, 0.26, 0.0), Vector3(0.24, 0.24, 0.24),
		CityKit.make_material(driver_color.lightened(0.25), 0.9), false, false
	)
	_refresh_occupant()


func _refresh_occupant() -> void:
	var figure := _body_root.get_node_or_null("Occupant") as Node3D
	if figure != null:
		figure.visible = driver_state == DriverState.SEATED


func _build_wheels(wheel_mat: StandardMaterial3D, hub_mat: StandardMaterial3D) -> void:
	_front_wheels.clear()
	var axle_z := data.body_length * 0.32
	var track := data.body_width * 0.5 - data.wheel_width * 0.35

	for front in [true, false]:
		for side in [-1.0, 1.0]:
			# A holder so the front pair can be steered without rebuilding the
			# cylinder's own 90-degree roll.
			var holder := Node3D.new()
			holder.name = "Wheel%s%d" % ["F" if front else "R", int(side)]
			holder.position = Vector3(
				side * track, data.wheel_radius, (-axle_z if front else axle_z)
			)
			_body_root.add_child(holder)

			var spin := Node3D.new()
			spin.name = "Axle"
			# Cylinders are built along Y; roll 90 degrees so the axle runs across
			# the car.
			spin.rotation_degrees.z = 90.0
			holder.add_child(spin)

			CityKit.add_cylinder(
				spin, "Tyre", Vector3.ZERO, data.wheel_radius, data.wheel_width, wheel_mat, false
			)
			# A pale hub inside the tyre. From above it is the only part of a
			# wheel the camera sees, and it is what stops wheels reading as
			# black smudges under the body.
			CityKit.add_cylinder(
				spin, "Hub", Vector3(0.0, side * data.wheel_width * 0.30, 0.0),
				data.wheel_radius * 0.54, data.wheel_width * 0.42, hub_mat, false
			)
			# An arch over the wheel, in body colour, so the wheel sits in the
			# bodywork instead of beside it.
			CityKit.add_box(
				_body_root, "Arch%s%d" % ["F" if front else "R", int(side)],
				Vector3(
					side * (data.body_width * 0.5 - 0.02),
					data.ground_clearance + data.wheel_radius * 0.92,
					(-axle_z if front else axle_z)
				),
				Vector3(0.10, data.wheel_radius * 0.55, data.wheel_radius * 2.5),
				CityKit.make_material(data.body_color.darkened(0.45), 0.5), false, false
			)

			if front:
				_front_wheels.append(holder)


## One box, sized from the data, resting on the ground so the body has
## something to stand on. Kerbs are not in this body's collision mask (see the
## "curb" layer note in district_01.gd), so a low box is enough — the car drives
## over kerbs rather than being stopped by them.
func _build_collision() -> void:
	var shape := BoxShape3D.new()
	var height := data.ground_clearance + data.body_height + data.cabin_height * 0.5
	shape.size = Vector3(data.body_width, height, data.body_length)
	_collision.shape = shape
	_collision.position = Vector3(0.0, height * 0.5, 0.0)


## Slightly proud of the body all round, so a glancing pass still counts as
## contact rather than the pedestrian threading the gap.
func _build_impact_zone() -> void:
	var shape := BoxShape3D.new()
	var height := maxf(data.ground_clearance + data.body_height, 0.9)
	shape.size = Vector3(data.body_width + 0.35, height, data.body_length + 0.5)
	var volume := _impact_zone.get_node("Volume") as CollisionShape3D
	volume.shape = shape
	volume.position = Vector3(0.0, height * 0.5, 0.0)


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"health": health,
		"theft_reported": _theft_reported,
		"driver_state": int(driver_state),
	}


func load_state(state: Dictionary) -> void:
	var raw: Array = state.get("position", [])
	if raw.size() == 3:
		global_position = Vector3(raw[0], raw[1], raw[2])
	rotation = Vector3(0.0, float(state.get("yaw", rotation.y)), 0.0)
	health = clampf(float(state.get("health", health)), 0.0, data.max_health)
	_theft_reported = bool(state.get("theft_reported", _theft_reported))
	# Saves written before carjacking existed have no occupant recorded, and the
	# cars they describe are parked ones.
	driver_state = int(state.get("driver_state", driver_state)) as DriverState
	_refresh_occupant()
	_forward_speed = 0.0
	velocity = Vector3.ZERO
	health_changed.emit(health, data.max_health)
