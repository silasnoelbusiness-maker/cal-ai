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
@export_range(20.0, 89.0, 1.0) var pitch_degrees: float = 64.0:
	set(value):
		pitch_degrees = value
		if is_inside_tree():
			_apply_pitch()
## Resting distance from the pivot to the camera.
@export_range(4.0, 80.0, 0.5) var distance: float = 22.0
@export_range(4.0, 80.0, 0.5) var min_distance: float = 11.0
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

@export_group("Orbit")
## -90 looks east along Main Street from the starting apartment, which frames
## the street rather than the wall the player spawns against.
@export var yaw_degrees: float = -90.0
## Degrees per second when orbiting with the keyboard.
@export var key_orbit_speed: float = 110.0
## Degrees per pixel when orbiting by dragging with the right mouse button.
@export var mouse_sensitivity: float = 0.22
@export var zoom_step: float = 2.0

@onready var _spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

var _target: Node3D = null
var _speed_extra: float = 0.0
var _follow_blend: float = 1.0
## The exported framing, remembered so a temporary interior view can be undone.
var _default_distance: float = 0.0
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
	global_position = _desired_pivot_position()
	_follow_blend = 1.0


func set_target(new_target: Node3D, snap: bool = false) -> void:
	if _target == new_target:
		return
	_target = new_target
	if _target == null:
		return
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
		distance = clampf(distance - zoom_step, min_distance, max_distance)
	elif event.is_action_pressed("camera_zoom_out"):
		distance = clampf(distance + zoom_step, min_distance, max_distance)
	elif event.is_action_pressed("camera_reset"):
		reset_orientation()
	elif event is InputEventMouseMotion and Input.is_action_pressed("camera_look"):
		yaw_degrees -= event.relative.x * mouse_sensitivity


func _process(delta: float) -> void:
	_update_orbit(delta)
	_update_speed_zoom(delta)
	_update_follow(delta)


func _update_orbit(delta: float) -> void:
	var orbit := Input.get_axis("camera_rotate_right", "camera_rotate_left")
	if not is_zero_approx(orbit):
		yaw_degrees += orbit * key_orbit_speed * delta
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
	)


func _desired_pivot_position() -> Vector3:
	return _target.global_position + Vector3.UP * height_offset


## Frame-rate independent exponential smoothing factor.
func _smoothing(sharpness: float, delta: float) -> float:
	return 1.0 - exp(-maxf(sharpness, 0.0) * delta)


func _apply_pitch() -> void:
	if _spring_arm == null:
		_spring_arm = get_node_or_null("SpringArm3D") as SpringArm3D
	if _spring_arm != null:
		_spring_arm.rotation_degrees.x = -pitch_degrees
