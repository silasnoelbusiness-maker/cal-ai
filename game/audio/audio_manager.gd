extends Node
## Plays things. One place, so concurrency and priority can actually be
## enforced.
##
## Every sound in the game goes through here rather than each system owning an
## AudioStreamPlayer. That buys three things nothing else could: a hard cap on
## how many voices exist at once, a per-sound cooldown so a shower of tiny
## collisions is one thump rather than forty, and a pool of players that is
## allocated once instead of a node created and freed per footstep.
##
## Positional sounds use AudioStreamPlayer3D so distance does the mixing —
## a cashier in Harbour Row is inaudible from Central because the falloff says
## so, not because anything special-cases it.

## How many pooled players of each kind. Past these, the quietest or oldest
## sound is reused: a chase is allowed to be loud, not unbounded.
const POOL_2D := 12
const POOL_3D := 24

## Nothing further away than this is worth a voice at all.
const MAX_AUDIBLE := 90.0

## Default seconds before the same sound may retrigger. Overridden per call.
const DEFAULT_COOLDOWN := 0.04

var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _last_played: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Sound keeps running while the game is paused, so a menu click is audible
	# from the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure_layout()
	_rng.randomize()
	_build_pools()


func _build_pools() -> void:
	for i in POOL_2D:
		var player := AudioStreamPlayer.new()
		player.name = "Flat%d" % i
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_pool_2d.append(player)
	for i in POOL_3D:
		var player := AudioStreamPlayer3D.new()
		player.name = "Spatial%d" % i
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		# Falloff tuned so a sound is present within a few metres, thin by
		# twenty and gone by ninety.
		player.unit_size = 6.0
		player.max_distance = MAX_AUDIBLE
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_pool_3d.append(player)


# --- Playing ---------------------------------------------------------------

## A flat, non-positional sound: interface, notifications, anything the player
## caused directly.
func play(
	id: StringName, bus: StringName = AudioBuses.SFX, volume_db: float = 0.0,
	pitch: float = 1.0, cooldown: float = DEFAULT_COOLDOWN
) -> void:
	if not _may_play(id, cooldown):
		return
	var player := _free_2d()
	if player == null:
		return
	player.stream = ToneBank.get_stream(id)
	player.bus = String(bus)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


## A sound at a place in the world. Silently does nothing when it is too far
## from the listener to matter, which is the cheapest possible culling.
func play_at(
	id: StringName, position: Vector3, bus: StringName = AudioBuses.SFX,
	volume_db: float = 0.0, pitch: float = 1.0, cooldown: float = DEFAULT_COOLDOWN
) -> void:
	if not _within_earshot(position):
		return
	if not _may_play(id, cooldown):
		return
	var player := _free_3d()
	if player == null:
		return
	player.stream = ToneBank.get_stream(id)
	player.bus = String(bus)
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.global_position = position
	player.play()


## The same, with a little randomness on pitch and level. Anything that repeats
## — footsteps most of all — uses this, because the give-away for a synthesised
## sound is hearing the identical sample twice in a row.
func play_varied(
	id: StringName, position: Vector3, bus: StringName = AudioBuses.SFX,
	volume_db: float = 0.0, spread: float = 0.08
) -> void:
	play_at(
		id, position, bus,
		volume_db + _rng.randf_range(-1.5, 1.5),
		1.0 + _rng.randf_range(-spread, spread),
		0.0
	)


## An interface sound. Separate entry point so every screen does not have to
## remember which bus it belongs on.
func play_ui(id: StringName, volume_db: float = 0.0) -> void:
	play(id, AudioBuses.UI, volume_db, 1.0, 0.02)


# --- Bookkeeping -----------------------------------------------------------

func _may_play(id: StringName, cooldown: float) -> bool:
	if cooldown <= 0.0:
		return true
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = _last_played.get(id, -999.0)
	if now - last < cooldown:
		return false
	_last_played[id] = now
	return true


func _within_earshot(position: Vector3) -> bool:
	if not _has_listener():
		return true
	return position.distance_to(_listener_position()) <= MAX_AUDIBLE


## Where the player is hearing from. In a vehicle that is still the player node,
## which rides along inside the car, so getting in does not break spatial audio.
func _listener_position() -> Vector3:
	var player := GameManager.player
	return player.global_position if player != null else Vector3.ZERO


func _has_listener() -> bool:
	return GameManager.player != null


func _free_2d() -> AudioStreamPlayer:
	for player in _pool_2d:
		if not player.playing:
			return player
	# Everything is busy: take the oldest rather than dropping the sound, since
	# the pool is sized so this only happens in a genuine pile-up.
	return _pool_2d[0] if not _pool_2d.is_empty() else null


func _free_3d() -> AudioStreamPlayer3D:
	var furthest: AudioStreamPlayer3D = null
	var furthest_distance := -1.0
	var has_listener := _has_listener()
	var listener := _listener_position()
	for player in _pool_3d:
		if not player.playing:
			return player
		if not has_listener:
			continue
		# Steal from whatever is furthest away: a distant car losing its thump
		# is inaudible, the one beside the player is not.
		var distance: float = player.global_position.distance_to(listener)
		if distance > furthest_distance:
			furthest_distance = distance
			furthest = player
	return furthest


# --- For the debug panel ---------------------------------------------------

func active_voices() -> int:
	var count := 0
	for player in _pool_2d:
		if player.playing:
			count += 1
	for player in _pool_3d:
		if player.playing:
			count += 1
	return count


func pool_size() -> int:
	return _pool_2d.size() + _pool_3d.size()
