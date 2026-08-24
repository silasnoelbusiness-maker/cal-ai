class_name TopDownCamera
extends Node3D
## Elevated top-down / isometric chase camera.
##
## The rig is a plain Node3D pivot that chases the target's position; a
## SpringArm3D holds the camera above and behind it and pulls in when a
## building would clip the view. Nothing here is player-specific — call
## set_target() with a vehicle in Phase D and the same rig follows it, blending
## smoothly because only the pivot's position is interpolated.

@export_group("Framing")
## Downward tilt in degrees. 50-70 gives the classic elevated look.
@export_range(20.0, 89.0, 1.0) var pitch_degrees: float = 56.0:
	set(value):
		pitch_degrees = value
		if is_inside_tree():
			_apply_pitch()
## Resting distance from the pivot to the camera.
##
## Phase T pulled this in from 22 metres and the pitch down from 64 degrees.
## The old framing was built for development — it showed a great deal of road
## and very little of anything worth looking at, and a person at that range was
## forty pixels tall. Closer and flatter shows façades, shopfronts and the
## shape of a figure, which is what the art is for. The zoom still reaches 38
## metres for anybody who wants the old view of the block.
@export_range(4.0, 80.0, 0.5) var distance: float = 17.0
@export_range(4.0, 80.0, 0.5) var min_distance: float = 9.0
@export_range(4.0, 80.0, 0.5) var max_distance: float = 38.0
## Pivot height above the target's origin, so the camera frames the torso.
@export var height_offset: float = 1.4

@export_group("Follow")
## Higher values snap harder. Position is smoothed exponentially so the camera
## never jerks when the target changes direction.
@export var follow_sharpness: float = 6.0
## Sharpness used for the first frames after a target swap, then it eases back
## to follow_sharpness. Keeps a player -> vehicle handover from lurching.
@export var handover_sharpness: float = 2.5

@export_group("Speed Zoom")
## Pull the camera back as the target speeds up.
@export var speed_zoom_enabled: bool = true
## Target speed (units/s) at which the full zoom-out is reached. Set to a car's
## top speed, so sprinting on foot only widens the view slightly and driving
## flat out opens it up enough to read the next junction.
@export var speed_zoom_reference: float = 23.0
## Extra distance added at the reference speed. Kept modest on purpose: the
## brief asks for the classic elevated framing, not an aerial view.
@export var speed_zoom_amount: float = 8.0
@export var speed_zoom_sharpness: float = 1.8

@export_group("Look Ahead")
## Shifts the pivot along the target's direction of travel at speed, so a car
## doing 60 shows the road it is about to reach rather than the one it has just
## left. Independent of the speed zoom — that changes how much you see, this
## changes what you are looking at — but they share a reference speed so the two
## come on together.
@export var look_ahead_enabled: bool = true
## Metres the pivot leads by at `speed_zoom_reference`. Deliberately modest: too
## much and the car sits at the bottom edge of the screen.
@export var look_ahead_distance: float = 7.0
## Below this speed there is no lead at all, so walking and parking are framed
## on the target exactly as before.
@export var look_ahead_min_speed: float = 3.0
## Eased more slowly than the zoom, because a lurching aim point is far more
## noticeable than a lurching distance.
@export var look_ahead_sharpness: float = 1.4

@export_group("Orbit")
## -90 looks east along Main Street from the starting apartment, which frames
## the street rather than the wall the player spawns against.
@export var yaw_degrees: float = -90.0
## Degrees per second when orbiting with the keyboard.
@export var key_orbit_speed: float = 110.0
## Degrees per pixel when orbiting by dragging with the right mouse button.
@export var mouse_sensitivity: float = 0.22
@export var zoom_step: float = 2.0

@export_group("Shake")
## How far the camera is knocked by a hard impact, before the player's own
## preference scales it. Restrained on purpose: this is a management game with
## chases in it, not a shooter.
@export var shake_metres: float = 0.35
@export var shake_decay: float = 6.0

@onready var _spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var _target: Node3D = null
var _speed_extra: float = 0.0
var _look_ahead: Vector3 = Vector3.ZERO
var _follow_blend: float = 1.0
## The exported framing, remembered so a temporary interior view can be undone.
var _default_distance: float = 0.0
var _shake: float = 0.0
var _shake_offset: Vector3 = Vector3.ZERO
var _default_pitch: float = 0.0
var _default_yaw: float = 0.0


func _ready() -> void:
	_default_distance = distance
	_default_pitch = pitch_degrees
	_default_yaw = yaw_degrees
	_apply_pitch()
	rotation_degrees.y = yaw_degrees
	GameManager.player_teleported.connect(_on_player_teleported)
	if _target != null:
		global_position = _desired_pivot_position()


## Temporarily reframes the camera — used by doorways into interiors, which are
## far too small for the street framing.
func apply_view(new_distance: float, new_pitch: float) -> void:
	distance = clampf(new_distance, min_distance, max_distance)
	pitch_degrees = new_pitch
	_speed_extra = 0.0
	if _spring_arm != null:
		_spring_arm.spring_length = distance


func reset_view() -> void:
	apply_view(_default_distance, _default_pitch)


## Puts the orbit back where it started. Bound to R, because E is interact and
## must stay that way.
func reset_orientation() -> void:
	yaw_degrees = _default_yaw
	rotation_degrees.y = yaw_degrees


## A teleport is a cut, not a move: re-seat the pivot instead of flying the
## camera across the map.
func _on_player_teleported(_destination: Transform3D) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_look_ahead = Vector3.ZERO
	global_position = _desired_pivot_position()
	_follow_blend = 1.0


func set_target(new_target: Node3D, snap: bool = false) -> void:
	if _target == new_target:
		return
	_target = new_target
	if _target == null:
		return
	_look_ahead = Vector3.ZERO
	if snap:
		global_position = _desired_pivot_position()
		_follow_blend = 1.0
	else:
		# Ease into the new target instead of whipping across to it.
		_follow_blend = 0.0


func get_target() -> Node3D:
	return _target


## Distance the arm is actually holding right now, i.e. `distance` plus whatever
## the speed zoom has added. What you want when checking how far out the camera
## has pulled, rather than what it was configured to sit at.
func get_effective_distance() -> float:
	return _spring_arm.spring_length if _spring_arm != null else distance


func get_yaw() -> float:
	return deg_to_rad(yaw_degrees)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		distance = clampf(distance - zoom_step * _zoom_scale(), min_distance, max_distance)
	elif event.is_action_pressed("camera_zoom_out"):
		distance = clampf(distance + zoom_step * _zoom_scale(), min_distance, max_distance)
	elif event.is_action_pressed("camera_reset"):
		# R turns the equipment while a placement is running.
		if GameManager.placement_active:
			return
		reset_orientation()
	elif event is InputEventMouseMotion and Input.is_action_pressed("camera_look"):
		yaw_degrees -= event.relative.x * mouse_sensitivity * _look_scale()


## The player's own sensitivity, from settings. Read rather than cached so a
## change in the pause menu takes effect without leaving the menu.
func _look_scale() -> float:
	return float(SettingsManager.gameplay("camera_sensitivity"))


func _zoom_scale() -> float:
	return float(SettingsManager.gameplay("zoom_sensitivity"))


## Knocks the camera, scaled by the player's preference — which may be zero, and
## then this does nothing at all.
func add_shake(strength: float) -> void:
	var allowance := float(SettingsManager.gameplay("camera_shake"))
	if allowance <= 0.001:
		return
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0) * allowance)


func _update_shake(delta: float) -> void:
	if _shake <= 0.001:
		# The offset is re-applied from scratch every frame rather than
		# accumulated, so clearing it is all that settling takes.
		_shake_offset = Vector3.ZERO
		return
	_shake = move_toward(_shake, 0.0, shake_decay * delta * _shake)
	# Applied to the pivot rather than the camera, so the shake survives the
	# spring arm doing its own smoothing.
	_shake_offset = Vector3(
		randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)
	) * _shake * shake_metres


func get_shake() -> float:
	return _shake


func _process(delta: float) -> void:
	_update_shake(delta)
	_update_orbit(delta)
	_update_speed_zoom(delta)
	_update_look_ahead(delta)
	_update_follow(delta)


## How far the pivot is currently leading the target by. Zero when standing
## still, and what a test reads to check the lead comes on and goes away again.
func get_look_ahead_distance() -> float:
	return _look_ahead.length()


func _update_orbit(delta: float) -> void:
	var orbit := Input.get_axis("camera_rotate_right", "camera_rotate_left")
	if not is_zero_approx(orbit):
		yaw_degrees += orbit * key_orbit_speed * _look_scale() * delta
	yaw_degrees = wrapf(yaw_degrees, -180.0, 180.0)
	rotation_degrees.y = yaw_degrees


## Reads the target's speed if it exposes one; anything without the method
## simply never triggers a speed zoom.
func _update_speed_zoom(delta: float) -> void:
	var wanted := 0.0
	if speed_zoom_enabled and _target != null and _target.has_method("get_planar_speed"):
		var speed: float = _target.call("get_planar_speed")
		wanted = clampf(speed / maxf(speed_zoom_reference, 0.01), 0.0, 1.0) * speed_zoom_amount
	_speed_extra = lerpf(_speed_extra, wanted, _smoothing(speed_zoom_sharpness, delta))
	_spring_arm.spring_length = distance + _speed_extra


func _update_follow(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	_follow_blend = minf(_follow_blend + delta * 0.8, 1.0)
	var sharpness := lerpf(handover_sharpness, follow_sharpness, _follow_blend)
	global_position = global_position.lerp(
		_desired_pivot_position(), _smoothing(sharpness, delta)
	) + _shake_offset


## The lead comes from the target's own `get_facing()` — the player's body pivot
## turns while the player node itself never rotates, so reading the node's basis
## would aim the camera at a fixed compass point.
func _update_look_ahead(delta: float) -> void:
	var wanted := Vector3.ZERO
	if (
		look_ahead_enabled
		and _target != null
		and _target.has_method("get_planar_speed")
		and _target.has_method("get_facing")
	):
		var speed: float = _target.call("get_planar_speed")
		if speed > look_ahead_min_speed:
			var reach := (speed - look_ahead_min_speed) / maxf(
				speed_zoom_reference - look_ahead_min_speed, 0.01
			)
			var forward: Vector3 = _target.call("get_facing")
			forward.y = 0.0
			if forward.length_squared() > 0.01:
				wanted = forward.normalized() * clampf(reach, 0.0, 1.0) * look_ahead_distance
	_look_ahead = _look_ahead.lerp(wanted, _smoothing(look_ahead_sharpness, delta))


func _desired_pivot_position() -> Vector3:
	return _target.global_position + Vector3.UP * height_offset + _look_ahead


## Frame-rate independent exponential smoothing factor.
func _smoothing(sharpness: float, delta: float) -> float:
	return 1.0 - exp(-maxf(sharpness, 0.0) * delta)


func _apply_pitch() -> void:
	if _spring_arm == null:
		_spring_arm = get_node_or_null("SpringArm3D") as SpringArm3D
	if _spring_arm != null:
		_spring_arm.rotation_degrees.x = -pitch_degrees
