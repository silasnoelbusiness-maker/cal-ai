extends Node
## The bed the city sits on, and the crossfade between outside and inside.
##
## Four looping players, faded rather than switched: an exterior bed that
## changes with the time of day, an interior bed that changes with the kind of
## room, and a district layer that makes Central hum where Harbour Row is open.
## Fading matters more than the sounds do — a hard cut when a door opens is the
## single most artificial thing an ambience system can do.
##
## Everything routes to the Ambience bus, so the whole bed moves on one slider.

signal profile_changed(profile: StringName)

enum Space { EXTERIOR, STORE, CAFE, HOME }

## Seconds to cross from one bed to another.
const FADE := 1.4
## How loud each bed sits when it is the active one, in decibels.
const BED_DB := -14.0
const LAYER_DB := -20.0

var _space: Space = Space.EXTERIOR
var _profile: StringName = &"city_day"

var _exterior: AudioStreamPlayer = null
var _interior: AudioStreamPlayer = null
var _layer: AudioStreamPlayer = null
var _targets: Dictionary = {}
var _timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	AudioBuses.ensure_layout()
	_exterior = _make_player("Exterior")
	_interior = _make_player("Interior")
	_layer = _make_player("Layer")
	_space = _detect_space()
	_refresh_profile()


func _make_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = String(AudioBuses.AMBIENCE)
	player.volume_db = -80.0
	add_child(player)
	return player


## Forces a space, for tests and for anything that knows better than the
## detector does. Applied immediately; the next detection tick may replace it.
func set_space(space: Space) -> void:
	if space == _space:
		return
	_space = space
	_refresh_profile()


func get_space() -> Space:
	return _space


## What is currently playing, for the debug panel and for tests.
func current_profile() -> StringName:
	return _profile


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_space = _detect_space()
		_refresh_profile()
	_fade(delta)


## Picks the beds for where the player is and what time it is, and sets the
## levels the fade walks towards.
## Works out which room the player is standing in, so nothing has to remember to
## tell the ambience when a door is used.
##
## Asked once a second against the interiors' own bounds, which is cheap and —
## more importantly — cannot fall out of step with where the player actually is
## the way a "the last door you used" flag can.
func _detect_space() -> Space:
	var player := GameManager.player
	if player == null:
		return Space.EXTERIOR

	for node in get_tree().get_nodes_in_group(&"retail_unit"):
		var unit := node as RetailUnit
		if unit == null or not unit.is_player_inside():
			continue
		return Space.CAFE if unit.get_business() != null \
			and unit.get_business().type_id == &"coffee_shop" else Space.STORE

	for node in get_tree().get_nodes_in_group(&"interior_room"):
		var room := node as Node3D
		if room == null:
			continue
		if room.global_position.distance_to(player.global_position) < 9.0:
			return Space.HOME

	return Space.EXTERIOR


func _refresh_profile() -> void:
	var night := TimeManager.get_phase() == TimeManager.Phase.NIGHT
	var indoors := _space != Space.EXTERIOR

	var exterior_bed: StringName = &"amb_city_night" if night else &"amb_city_day"
	# Inside, the city is still there — through a window, three walls away.
	var exterior_db := BED_DB if not indoors else BED_DB - 16.0

	var interior_bed := &"amb_room"
	var interior_db := -80.0
	match _space:
		Space.STORE:
			interior_bed = &"amb_store"
			interior_db = BED_DB + 1.0
		Space.CAFE:
			interior_bed = &"amb_cafe"
			interior_db = BED_DB + 1.0
		Space.HOME:
			interior_bed = &"amb_room"
			# A flat is the quietest place in the game, on purpose.
			interior_db = BED_DB - 5.0
		_:
			interior_db = -80.0

	# The district layer: a park thins the traffic out, Central thickens it.
	var layer_bed := &"amb_park"
	var layer_db := -80.0
	if not indoors:
		var player := GameManager.player
		var district := WorldManager.district_at(
			player.global_position if player != null else Vector3.ZERO
		)
		if district != null and district.district_id == &"central":
			layer_bed = &"amb_city_day" if not night else &"amb_city_night"
			layer_db = LAYER_DB
		elif _near_park():
			layer_bed = &"amb_park"
			layer_db = LAYER_DB + 2.0

	_set_bed(_exterior, exterior_bed, exterior_db)
	_set_bed(_interior, interior_bed, interior_db)
	_set_bed(_layer, layer_bed, layer_db)

	var profile: StringName = StringName(
		"%s_%s" % [Space.keys()[_space].to_lower(), "night" if night else "day"]
	)
	if profile != _profile:
		_profile = profile
		profile_changed.emit(profile)


## True when the player is standing in a green space. Cheap: the park is one
## landmark and this is a distance test against it once a second.
func _near_park() -> bool:
	var player := GameManager.player
	if player == null:
		return false
	for node in get_tree().get_nodes_in_group(&"landmark"):
		var marker := node as Node3D
		if marker == null or not String(marker.name).contains("Park"):
			continue
		if marker.global_position.distance_to(player.global_position) < 34.0:
			return true
	return false


func _set_bed(player: AudioStreamPlayer, id: StringName, target_db: float) -> void:
	if player == null:
		return
	var stream := ToneBank.get_stream(id)
	if player.stream != stream:
		player.stream = stream
		# A bed that is being swapped starts silent and fades up, rather than
		# arriving at whatever level the previous one had reached.
		if not player.playing:
			player.volume_db = -80.0
			player.play()
		else:
			player.volume_db = -80.0
			player.play()
	elif not player.playing and target_db > -79.0:
		player.play()
	_targets[player] = target_db


func _fade(delta: float) -> void:
	var step := delta / FADE * 60.0
	for player in _targets:
		var node := player as AudioStreamPlayer
		if node == null:
			continue
		var target: float = _targets[player]
		node.volume_db = move_toward(node.volume_db, target, step)
		if node.volume_db <= -79.0 and node.playing and target <= -79.0:
			node.stop()
