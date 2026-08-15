class_name Player
extends CharacterBody3D
## On-foot player controller.
##
## Movement is camera-relative so it stays intuitive while the top-down camera
## is orbited. Acceleration and deceleration are separate so the character
## eases into a run but stops crisply. The controller owns movement only —
## interacting is delegated to the InteractionController child, and needs are
## owned by PlayerStats.

signal move_state_changed(state: MoveState)

enum MoveState { IDLE, WALK, RUN }

@export_group("Movement")
@export var walk_speed: float = 4.2
@export var sprint_speed: float = 7.8
## Units per second squared while input is held.
@export var acceleration: float = 30.0
## Units per second squared while input is released.
@export var deceleration: float = 38.0
## Fraction of ground control retained while airborne.
@export var air_control: float = 0.3
## Radians per second the body turns toward its heading.
@export var turn_speed: float = 12.0

@export_group("Sprint")
## Sprinting stops below this much energy.
@export var min_energy_to_sprint: float = 2.0

@onready var stats: PlayerStats = $Stats
@onready var inventory: Inventory = $Inventory
@onready var interaction: InteractionController = $InteractionController
@onready var _body_pivot: Node3D = $BodyPivot

var _move_state: MoveState = MoveState.IDLE
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 20.0)
var _is_sprinting: bool = false


func _ready() -> void:
	GameManager.register_player(self)


func _exit_tree() -> void:
	GameManager.unregister_player(self)


func get_stats() -> PlayerStats:
	return stats


func get_inventory() -> Inventory:
	return inventory


func get_move_state() -> MoveState:
	return _move_state


func is_sprinting() -> bool:
	return _is_sprinting


## Horizontal speed in units/second. The camera reads this to widen the view
## as the player speeds up; vehicles expose the same method later.
func get_planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var input_dir := _get_camera_relative_input()
	_update_sprint(input_dir, delta)

	var target_speed := sprint_speed if _is_sprinting else walk_speed
	var target_velocity := input_dir * target_speed

	var rate := acceleration if input_dir.length_squared() > 0.0 else deceleration
	if not is_on_floor():
		rate *= air_control

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	planar = planar.move_toward(target_velocity, rate * delta)
	velocity.x = planar.x
	velocity.z = planar.z

	_face_movement(planar, delta)
	move_and_slide()
	_update_move_state(planar.length())


## Maps WASD onto the ground plane using the active camera's yaw, so "forward"
## always means "away from the camera" no matter how the rig is orbited.
func _get_camera_relative_input() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO

	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var basis := camera.global_transform.basis
		forward = -Vector3(basis.z.x, 0.0, basis.z.z)
		right = Vector3(basis.x.x, 0.0, basis.x.z)
		if forward.length_squared() < 0.001:
			# Camera pointing almost straight down; fall back to world axes.
			forward = Vector3.FORWARD
			right = Vector3.RIGHT
		forward = forward.normalized()
		right = right.normalized()

	return (right * input.x + forward * -input.y).limit_length(1.0)


func _update_sprint(input_dir: Vector3, delta: float) -> void:
	var wants_sprint := Input.is_action_pressed("sprint") and input_dir.length_squared() > 0.01
	_is_sprinting = wants_sprint and stats.has_energy_to_sprint(min_energy_to_sprint)

	if _is_sprinting:
		stats.drain_sprint_energy(delta)
	elif input_dir.length_squared() < 0.01:
		stats.recover_idle_energy(delta)


func _face_movement(planar_velocity: Vector3, delta: float) -> void:
	if planar_velocity.length_squared() < 0.05:
		return
	var target_yaw := atan2(planar_velocity.x, planar_velocity.z)
	_body_pivot.rotation.y = lerp_angle(_body_pivot.rotation.y, target_yaw, turn_speed * delta)


func _update_move_state(speed: float) -> void:
	var new_state := MoveState.IDLE
	if speed > walk_speed + 0.5:
		new_state = MoveState.RUN
	elif speed > 0.2:
		new_state = MoveState.WALK

	if new_state == _move_state:
		return
	_move_state = new_state
	move_state_changed.emit(_move_state)
