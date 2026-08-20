class_name CharacterAnimator
extends Node
## Moves a CharacterKit rig. No animation clips, no skeleton — four joints
## driven by a phase counter.
##
## That is a deliberate trade. A real AnimationPlayer per pedestrian means an
## imported rig, retargeting and forty animation trees on a street; a sine wave
## through the hip and shoulder joints costs a handful of float writes and, at
## the distance this camera sits, is the difference between "a person walking"
## and "a box sliding". The states are the ones the game already has, so
## nothing calls this that was not already tracking the same thing.

enum State { IDLE, WALK, RUN, WORK, CARRY, ALERT, DOWN }

## Radians of swing at the hip and shoulder, per state.
const SWING := {
	State.IDLE: 0.04,
	State.WALK: 0.52,
	State.RUN: 0.86,
	State.WORK: 0.10,
	State.CARRY: 0.34,
	State.ALERT: 0.62,
	State.DOWN: 0.0,
}

## Steps per second at one metre per second, so the legs keep up with the feet
## rather than running at a fixed rate whatever the speed.
@export var stride_rate: float = 1.05
## Idle breathing, in cycles per second.
@export var idle_rate: float = 0.55
@export var run_lean_degrees: float = 8.0

var _rig: CharacterKit.Rig = null
var _state: State = State.IDLE
var _phase: float = 0.0
var _speed: float = 0.0
var _blend: float = 0.0
var _hip_rest: float = 0.0


func setup(rig: CharacterKit.Rig) -> void:
	_rig = rig
	if _rig != null and _rig.hips != null:
		_hip_rest = _rig.hips.position.y
	# Everybody starts at a different point in the cycle, or a crowd marches.
	_phase = randf() * TAU


func set_state(state: State) -> void:
	_state = state


## How many strides have been taken. Whatever wants to put a footstep under a
## foot reads this rather than guessing from speed, so a sound lands when the
## leg is actually down and the cadence follows the walk cycle for free.
func stride_count() -> int:
	return int(_phase / PI)


func get_state() -> State:
	return _state


## Called by whatever is driving the figure, with its planar speed.
func set_speed(speed: float) -> void:
	_speed = maxf(speed, 0.0)


func _process(delta: float) -> void:
	if _rig == null or _rig.hips == null:
		return

	var walking := _state == State.WALK or _state == State.RUN or _state == State.ALERT
	# Blend towards the target swing rather than snapping, so stopping is a
	# stride that shortens instead of a leg that teleports to rest.
	_blend = move_toward(_blend, 1.0 if walking else 0.0, delta * 6.0)

	if walking:
		_phase += delta * TAU * stride_rate * maxf(_speed, 0.6)
	else:
		_phase += delta * TAU * idle_rate

	var swing: float = float(SWING.get(_state, 0.0)) * _blend
	var wave := sin(_phase)
	var counter := sin(_phase + PI)

	_rig.leg_left.rotation.x = wave * swing
	_rig.leg_right.rotation.x = counter * swing
	# Arms swing against the legs. Half the amplitude reads as natural; equal
	# amplitude reads as a march.
	_rig.arm_left.rotation.x = counter * swing * 0.62
	_rig.arm_right.rotation.x = wave * swing * 0.62

	_apply_pose(delta, wave)


## Everything that is not the swing: the bob, the lean, and the poses that are
## about what somebody is doing rather than how fast they are going.
func _apply_pose(delta: float, wave: float) -> void:
	var chest := _rig.chest
	var target_lean := 0.0
	var target_bob := 0.0
	var arm_lift := 0.0

	match _state:
		State.RUN, State.ALERT:
			target_lean = deg_to_rad(run_lean_degrees)
			target_bob = absf(wave) * 0.035
		State.WALK:
			target_bob = absf(wave) * 0.018
		State.WORK:
			# Leant slightly over the counter with both hands in front of them,
			# which from above is what tells the player somebody is serving.
			target_lean = deg_to_rad(9.0)
			arm_lift = deg_to_rad(-62.0)
		State.CARRY:
			arm_lift = deg_to_rad(-48.0)
		State.IDLE:
			target_bob = sin(_phase) * 0.006
		State.DOWN:
			target_lean = deg_to_rad(84.0)
			target_bob = -_rig.height * 0.42

	chest.rotation.x = move_toward(chest.rotation.x, target_lean, delta * 4.0)
	_rig.hips.position.y = move_toward(
		_rig.hips.position.y, _hip_rest + target_bob, delta * 2.4
	)
	if arm_lift != 0.0 or _state == State.WORK or _state == State.CARRY:
		_rig.arm_left.rotation.x = move_toward(_rig.arm_left.rotation.x, arm_lift, delta * 6.0)
		_rig.arm_right.rotation.x = move_toward(_rig.arm_right.rotation.x, arm_lift, delta * 6.0)
	# The head stays level while the chest leans, so a running figure looks
	# where it is going instead of at the pavement.
	_rig.head.rotation.x = -chest.rotation.x * 0.7
