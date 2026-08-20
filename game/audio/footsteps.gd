class_name Footsteps
extends Node
## Puts a sound under a walking figure.
##
## Driven by the character animator's stride counter rather than by a timer, so
## a step lands when the leg is actually down and the cadence follows the walk
## cycle for free — walk and run differ because the animation differs, not
## because a second set of numbers says so.
##
## Attached to the player always, and to nearby pedestrians within a limit, so a
## crowd of forty does not become forty footstep sources.

## Beyond this from the listener an NPC's footsteps are not worth a voice.
@export var npc_audible_distance: float = 26.0
## How many NPCs may have audible footsteps at once, city-wide.
@export var npc_voice_limit: int = 6
@export var volume_db: float = -6.0
## NPC steps sit under the player's, so the player's own movement stays legible.
@export var npc_volume_db: float = -15.0

## True for the player's own feet: always audible, never counted against the
## crowd limit.
@export var is_player: bool = false

static var _npc_voices: int = 0

var _body: CharacterBody3D = null
var _animator: CharacterAnimator = null
var _last_stride: int = 0
var _counted: bool = false


func setup(body: CharacterBody3D, animator: CharacterAnimator) -> void:
	_body = body
	_animator = animator
	if _animator != null:
		_last_stride = _animator.stride_count()


func _process(_delta: float) -> void:
	if _body == null or _animator == null:
		return

	var state := _animator.get_state()
	var moving := (
		state == CharacterAnimator.State.WALK
		or state == CharacterAnimator.State.RUN
		or state == CharacterAnimator.State.ALERT
	)
	# Standing still makes no sound, however long the idle animation runs.
	if not moving or not _body.is_on_floor():
		_last_stride = _animator.stride_count()
		_release()
		return

	var stride := _animator.stride_count()
	if stride == _last_stride:
		return
	_last_stride = stride

	if not is_player and not _claim():
		return

	var surface := SurfaceMap.under(_body)
	var loudness := volume_db if is_player else npc_volume_db
	if state == CharacterAnimator.State.RUN:
		loudness += 2.5
	AudioManager.play_varied(
		SurfaceMap.sound_for(surface), _body.global_position,
		AudioBuses.SFX, loudness
	)


## Takes one of the shared NPC footstep slots, if there is one going and the
## listener is close enough to care.
func _claim() -> bool:
	var player := GameManager.player
	if player == null:
		return false
	if _body.global_position.distance_to(player.global_position) > npc_audible_distance:
		_release()
		return false
	if _counted:
		return true
	if _npc_voices >= npc_voice_limit:
		return false
	_npc_voices += 1
	_counted = true
	return true


func _release() -> void:
	if not _counted:
		return
	_counted = false
	_npc_voices = maxi(_npc_voices - 1, 0)


func _exit_tree() -> void:
	_release()


## Development and testing entry point.
static func active_npc_voices() -> int:
	return _npc_voices
