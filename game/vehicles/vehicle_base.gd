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

enum OwnerType { PLAYER, NPC, PUBLIC, COMPANY }

## Speeds above this (m/s) are too fast to step out of.
const SAFE_EXIT_SPEED := 6.0
## Beam strength once the headlights are lit.
const HEADLIGHT_ENERGY := 5.0
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

@export_group("Ownership")
@export var owner_type: OwnerType = OwnerType.NPC
## Who owns it. "player" for the player's own car; anything else for NPCs.
@export var owner_id: StringName = &"npc"
## Stable id for the save file. Empty means this vehicle is not persisted.
@export var save_id: StringName = &""

@onready var _body_root: Node3D = $Body
@onready var _collision: CollisionShape3D = $Collision
@onready var _seat: Marker3D = $Seat
@onready var _door: VehicleDoor = $Door
@onready var _headlights: SpotLight3D = $Headlights

var health: float = 100.0
var _driver: Node3D = null
## Signed speed along the car's forward axis. Negative is reverse.
var _forward_speed: float = 0.0
var _steer_input: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _front_wheels: Array[Node3D] = []
## Theft is reported once per vehicle, not once per time the player gets in.
var _theft_reported: bool = false


func _ready() -> void:
	if data == null:
		push_error("Vehicle '%s' has no VehicleData." % name)
		set_physics_process(false)
		return

	health = data.max_health
	add_to_group(&"vehicle")
	if save_id != &"":
		add_to_group(&"saveable")

	_build_body()
	_build_collision()
	_door.setup(self)
	health_changed.emit(health, data.max_health)


# --- Public API ----------------------------------------------------------

func get_driver() -> Node3D:
	return _driver


func has_driver() -> bool:
	return _driver != null


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


func get_display_name() -> String:
	return data.display_name if data != null else "Vehicle"


func can_be_entered_by(_who: Node3D) -> bool:
	return _driver == null and not is_disabled()


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

	if _driver != null and not is_disabled():
		throttle = Input.get_axis("move_back", "move_forward")
		steer = Input.get_axis("move_right", "move_left")
		handbrake = Input.is_action_pressed("handbrake")
	elif _driver != null:
		# Wrecked but occupied: the car coasts to a stop, it does not lock up.
		handbrake = false

	_update_speed(throttle, handbrake, delta)
	_update_steering(steer, handbrake, delta)

	var forward := -global_transform.basis.z
	var speed_before := _forward_speed
	velocity = forward * _forward_speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - _gravity * delta

	move_and_slide()
	_resolve_collisions(speed_before, delta)
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
	if hardest_impact > data.damage_speed_threshold:
		apply_damage((hardest_impact - data.damage_speed_threshold) * data.damage_per_impact_speed)


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

	var body_mat := CityKit.make_material(data.body_color, 0.45, 0.25)
	var trim_mat := CityKit.make_material(data.trim_color, 0.7)
	var glass_mat := CityKit.make_material(data.glass_color, 0.15, 0.35)
	var head_mat := CityKit.make_emissive_material(Color(0.86, 0.84, 0.72), 1.1)
	var tail_mat := CityKit.make_emissive_material(Color(0.55, 0.11, 0.11), 1.4)

	CityKit.add_box(
		_body_root,
		"Chassis",
		Vector3(0.0, lower_y, 0.0),
		Vector3(data.body_width, data.body_height, data.body_length),
		body_mat,
		false
	)
	# Greenhouse: dark glass box with a body-coloured roof panel on top, which
	# is what actually reads as "car" from directly above.
	CityKit.add_box(
		_body_root,
		"Cabin",
		Vector3(0.0, cabin_y, 0.15),
		Vector3(data.body_width * 0.86, data.cabin_height, data.body_length * 0.46),
		glass_mat,
		false
	)
	CityKit.add_box(
		_body_root,
		"Roof",
		Vector3(0.0, cabin_y + data.cabin_height * 0.5, 0.3),
		Vector3(data.body_width * 0.74, 0.09, data.body_length * 0.28),
		body_mat,
		false
	)
	# Bumpers tell front from rear even in silhouette.
	for pair in [["BumperFront", -1.0], ["BumperRear", 1.0]]:
		CityKit.add_box(
			_body_root,
			pair[0],
			Vector3(0.0, clearance + 0.22, (data.body_length * 0.5 - 0.1) * float(pair[1])),
			Vector3(data.body_width * 1.02, 0.26, 0.24),
			trim_mat,
			false
		)
	# Lights: white at the nose, red at the tail. Emissive, so the car stays
	# readable after dark.
	for side in [-1.0, 1.0]:
		CityKit.add_box(
			_body_root,
			"Headlight%d" % int(side),
			Vector3(
				side * data.body_width * 0.32,
				clearance + data.body_height * 0.72,
				-data.body_length * 0.5 - 0.02
			),
			Vector3(data.body_width * 0.26, 0.16, 0.1),
			head_mat,
			false,
			false
		)
		CityKit.add_box(
			_body_root,
			"Taillight%d" % int(side),
			Vector3(
				side * data.body_width * 0.32,
				clearance + data.body_height * 0.72,
				data.body_length * 0.5 + 0.02
			),
			Vector3(data.body_width * 0.26, 0.14, 0.1),
			tail_mat,
			false,
			false
		)

	_build_wheels(trim_mat)


func _build_wheels(wheel_mat: StandardMaterial3D) -> void:
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


# --- Save ----------------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"health": health,
		"theft_reported": _theft_reported,
	}


func load_state(state: Dictionary) -> void:
	var raw: Array = state.get("position", [])
	if raw.size() == 3:
		global_position = Vector3(raw[0], raw[1], raw[2])
	rotation = Vector3(0.0, float(state.get("yaw", rotation.y)), 0.0)
	health = clampf(float(state.get("health", health)), 0.0, data.max_health)
	_theft_reported = bool(state.get("theft_reported", _theft_reported))
	_forward_speed = 0.0
	velocity = Vector3.ZERO
	health_changed.emit(health, data.max_health)
