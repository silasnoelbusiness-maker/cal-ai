class_name VehicleAudio
extends Node
## The noise one car makes.
##
## Attached to every vehicle, and cheap enough to be: one looping engine player
## whose pitch and volume follow the car, one tyre player that only runs while
## something is scrubbing, and — on a patrol car — one siren. Impacts and doors
## are one-shots through AudioManager, so they obey its pooling and cooldowns
## rather than each car owning players it uses twice a minute.
##
## The engine is a loop that is *pitched*, not a set of recordings crossfaded by
## RPM. At this camera distance the difference is inaudible, and the cost is one
## AudioStreamPlayer3D per car instead of three.

## Engine pitch at a standstill and at the model's top speed. Kept narrow: a car
## whose pitch doubles sounds like a toy.
const IDLE_PITCH := 0.62
const TOP_PITCH := 1.55
## Engine level at idle and under throttle, in decibels.
const IDLE_DB := -22.0
const DRIVE_DB := -9.0
## Past this from the listener a car is not worth a voice at all. This is what
## keeps a city of traffic down to the handful of engines actually near you.
const SLEEP_DISTANCE := 55.0

## Which engine loop suits which body. A van should not sound like a coupe, and
## this table is the whole of the difference.
const ENGINE_BY_PROFILE := {
	VehicleData.Profile.HATCHBACK: &"engine_loop_light",
	VehicleData.Profile.SALOON: &"engine_loop",
	VehicleData.Profile.VAN: &"engine_loop_heavy",
	VehicleData.Profile.SUV: &"engine_loop_heavy",
	VehicleData.Profile.COUPE: &"engine_loop_light",
	VehicleData.Profile.CRUISER: &"engine_loop",
}

var _vehicle: Vehicle = null
var _engine: AudioStreamPlayer3D = null
var _tyres: AudioStreamPlayer3D = null
var _siren: AudioStreamPlayer3D = null
var _siren_on: bool = false
var _last_impact: float = 0.0


func setup(vehicle: Vehicle) -> void:
	_vehicle = vehicle
	_engine = _make_player("Engine", 8.0, 80.0)
	_engine.stream = ToneBank.get_stream(
		ENGINE_BY_PROFILE.get(vehicle.data.body_profile, &"engine_loop")
	)
	_engine.volume_db = IDLE_DB
	_tyres = _make_player("Tyres", 6.0, 60.0)
	_tyres.stream = ToneBank.get_stream(&"skid")
	_tyres.volume_db = -80.0

	if vehicle.data.livery == VehicleData.Livery.POLICE:
		# A siren carries much further than an engine, on purpose: hearing one
		# before you can see it is the point of it.
		_siren = _make_player("Siren", 22.0, 170.0)
		_siren.stream = ToneBank.get_stream(&"siren")
		_siren.volume_db = -80.0


func _make_player(
	player_name: String, unit_size: float, max_distance: float
) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = player_name
	player.bus = String(AudioBuses.VEHICLES)
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	return player


func _physics_process(delta: float) -> void:
	if _vehicle == null or _engine == null:
		return

	# A parked car with nobody in it is silent, and a car nobody is near is
	# silent whatever it is doing. Between them, that is most of the traffic.
	var distance := _distance_to_listener()
	var running := _vehicle.is_engine_running()
	if not running or distance > SLEEP_DISTANCE:
		if _engine.playing:
			_engine.stop()
		if _tyres.playing:
			_tyres.stop()
		# The siren is the exception: a unit responding from three streets away
		# should still be audible, so it keeps its own range.
		_update_siren(delta)
		return

	if not _engine.playing:
		_engine.play()

	var ratio: float = clampf(
		_vehicle.get_planar_speed() / maxf(_vehicle.data.max_speed, 1.0), 0.0, 1.0
	)
	var throttle: float = absf(_vehicle.get_throttle_input())
	# Pitch follows speed; throttle adds a little on top, so pulling away sounds
	# like effort rather than only like motion.
	var target_pitch := lerpf(IDLE_PITCH, TOP_PITCH, ratio) + throttle * 0.08
	var target_db := lerpf(IDLE_DB, DRIVE_DB, maxf(ratio, throttle * 0.7))

	# Smoothed rather than set, so lifting off settles instead of stepping.
	_engine.pitch_scale = move_toward(_engine.pitch_scale, target_pitch, 0.9 * delta)
	_engine.volume_db = move_toward(_engine.volume_db, target_db, 24.0 * delta)

	_update_tyres(ratio, delta)
	_update_siren(delta)


## Tyres scrub when the handbrake is down at speed, or when the car is cornering
## hard enough to be sliding. Silent otherwise — a game that squeals on every
## corner stops meaning anything by the second corner.
func _update_tyres(ratio: float, delta: float) -> void:
	var handbrake := _vehicle.is_handbrake_down()
	var hard_turn := absf(_vehicle.get_steer_input()) > 0.75 and ratio > 0.55
	var scrubbing := (handbrake and ratio > 0.15) or hard_turn
	if scrubbing and not _tyres.playing:
		_tyres.play()
	_tyres.volume_db = move_toward(
		_tyres.volume_db, -14.0 if scrubbing else -80.0, 40.0 * delta
	)
	if _tyres.volume_db <= -79.0 and _tyres.playing:
		_tyres.stop()


## The siren follows the light bar exactly, so what the player hears and what
## they see can never disagree.
func _update_siren(delta: float) -> void:
	if _siren == null:
		return
	var driver := _vehicle.get_node_or_null("Driver") as PoliceDriver
	var wanted := driver != null and driver.is_siren_active()
	if wanted != _siren_on:
		_siren_on = wanted
		if wanted and not _siren.playing:
			_siren.play()
	_siren.volume_db = move_toward(
		_siren.volume_db, -8.0 if _siren_on else -80.0, 30.0 * delta
	)
	if _siren.volume_db <= -79.0 and _siren.playing:
		_siren.stop()


## Called by the vehicle when it hits something. Graded by impact speed, with a
## cooldown so scraping along a wall is one sound rather than thirty.
func report_impact(impact_speed: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_impact < 0.25:
		return
	_last_impact = now
	var id := &"impact_light"
	var loudness := -14.0
	if impact_speed > 12.0:
		id = &"impact_heavy"
		loudness = -4.0
	elif impact_speed > 6.0:
		id = &"impact_medium"
		loudness = -9.0
	AudioManager.play_at(
		id, _vehicle.global_position, AudioBuses.VEHICLES, loudness, 1.0, 0.0
	)


## True while this car's siren is audible. Read by the audio debug panel and by
## the tests, which cannot listen.
func is_siren_sounding() -> bool:
	return _siren_on


func _distance_to_listener() -> float:
	var player := GameManager.player
	if player == null or _vehicle == null:
		return 0.0
	return _vehicle.global_position.distance_to(player.global_position)
