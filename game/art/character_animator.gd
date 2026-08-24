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

## Appended to, never reordered — Phase S saves and the crowd both store the
## integer. SIT through GYM are Phase T: the work the city was already doing
## without showing it.
enum State { IDLE, WALK, RUN, WORK, CARRY, ALERT, DOWN, SIT, EAT, CLEAN, GYM }

## Radians of swing at the hip and shoulder, per state.
const SWING := {
	State.IDLE: 0.04,
	State.WALK: 0.52,
	State.RUN: 0.86,
	State.WORK: 0.10,
	State.CARRY: 0.34,
	State.ALERT: 0.62,
	State.DOWN: 0.0,
	State.SIT: 0.0,
	State.EAT: 0.0,
	State.CLEAN: 0.0,
	State.GYM: 0.0,
}

## The pose an arm rests in when nothing else is asking for it: out from the
## body, a little behind, and bent at the elbow.
##
## Every one of these numbers is small. Together they are the whole difference
## between a person standing and a mannequin, which was the loudest thing wrong
## with the crowd — a straight line from shoulder to fingertip reads as plastic
## however good the rest of the figure is.
const REST_SHOULDER_SPLAY := 0.10
const REST_SHOULDER_BACK := 0.06
const REST_ELBOW_BEND := 0.22
## How much of the rest bend survives while walking. Arms straighten as they
## swing, which is what people do.
const WALKING_ELBOW := 0.45

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

	# Not while a pose owns the legs. SIT drives them to a fold in _apply_pose,
	# and writing the swing here first — zero, for a state with no swing — reset
	# that fold on every frame, so a seated figure crept a fifth of the way
	# there and stayed. The test caught it; the shape of the bug is that two
	# things were writing one rotation.
	if not _pose_owns_legs():
		_rig.leg_left.rotation.x = wave * swing
		_rig.leg_right.rotation.x = counter * swing
	# Arms swing against the legs. Half the amplitude reads as natural; equal
	# amplitude reads as a march.
	_rig.arm_left.rotation.x = counter * swing * 0.62 - REST_SHOULDER_BACK
	_rig.arm_right.rotation.x = wave * swing * 0.62 - REST_SHOULDER_BACK
	# Held out from the body, more so standing still than mid-stride: a walking
	# figure's arms pass close to the hips, a standing one's do not.
	var splay := REST_SHOULDER_SPLAY * (1.0 - _blend * 0.55)
	_rig.arm_left.rotation.z = splay
	_rig.arm_right.rotation.z = -splay
	_set_elbows(REST_ELBOW_BEND * lerpf(1.0, WALKING_ELBOW, _blend))

	_apply_pose(delta, wave)


## Whether the current state poses the legs itself rather than swinging them.
func _pose_owns_legs() -> bool:
	return _state == State.SIT


## Both elbows to the same bend. Negative rotation on x brings the forearm
## forward, which is the way an elbow actually goes.
func _set_elbows(bend: float) -> void:
	if _rig.fore_left == null or _rig.fore_right == null:
		return
	_rig.fore_left.rotation.x = -bend
	_rig.fore_right.rotation.x = -bend


## Everything that is not the swing: the bob, the lean, and the poses that are
## about what somebody is doing rather than how fast they are going.
func _apply_pose(delta: float, wave: float) -> void:
	var chest := _rig.chest
	var target_lean := 0.0
	var target_bob := 0.0
	var target_roll := 0.0
	var arm_lift := 0.0
	## Below zero means "leave the swing alone".
	var elbow := -1.0
	## Hip rotation for a seated figure, in radians.
	var leg_fold := 0.0

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
			# A slow weight shift rather than a bob. Standing perfectly still is
			# the other half of the mannequin problem; this is small enough to
			# be invisible until it is missing.
			target_bob = sin(_phase) * 0.006
			target_roll = sin(_phase * 0.5) * 0.022
		State.DOWN:
			target_lean = deg_to_rad(84.0)
			target_bob = -_rig.height * 0.42
		State.SIT:
			# Folded at the hip with the thighs forward. The seat itself is
			# whatever the person was sent to; this is only the shape of
			# somebody on it.
			target_lean = deg_to_rad(6.0)
			target_bob = -_rig.height * 0.20
			leg_fold = deg_to_rad(-78.0)
			elbow = 0.55
		State.EAT:
			# Both hands up near the chest, leant slightly in over the table.
			target_lean = deg_to_rad(11.0)
			arm_lift = deg_to_rad(-38.0)
			elbow = 1.25
		State.CLEAN:
			# One long low reach, sweeping side to side.
			target_lean = deg_to_rad(22.0)
			arm_lift = deg_to_rad(-24.0)
			elbow = 0.35
			target_roll = sin(_phase * 1.6) * 0.10
		State.GYM:
			# A repetition: both arms driving up and down together.
			arm_lift = deg_to_rad(-40.0) + sin(_phase * 1.8) * deg_to_rad(34.0)
			elbow = 1.05 + sin(_phase * 1.8) * 0.5

	chest.rotation.x = move_toward(chest.rotation.x, target_lean, delta * 4.0)
	chest.rotation.z = move_toward(chest.rotation.z, target_roll, delta * 3.0)
	_rig.hips.position.y = move_toward(
		_rig.hips.position.y, _hip_rest + target_bob, delta * 2.4
	)
	if leg_fold != 0.0:
		_rig.leg_left.rotation.x = move_toward(_rig.leg_left.rotation.x, leg_fold, delta * 5.0)
		_rig.leg_right.rotation.x = move_toward(_rig.leg_right.rotation.x, leg_fold, delta * 5.0)
	if elbow >= 0.0:
		_set_elbows(elbow)
	if arm_lift != 0.0 or _state == State.WORK or _state == State.CARRY:
		_rig.arm_left.rotation.x = move_toward(_rig.arm_left.rotation.x, arm_lift, delta * 6.0)
		_rig.arm_right.rotation.x = move_toward(_rig.arm_right.rotation.x, arm_lift, delta * 6.0)
	# The head stays level while the chest leans, so a running figure looks
	# where it is going instead of at the pavement.
	_rig.head.rotation.x = -chest.rotation.x * 0.7
