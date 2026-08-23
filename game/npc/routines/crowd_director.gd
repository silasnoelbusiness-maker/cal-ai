class_name CrowdDirector
extends Node

## Keeps a district's pavements as busy as the hour deserves.
##
## §145 asks for a population budget rather than unlimited spawning, and §144
## that more life must not cost frames. So no pedestrian is ever created or
## destroyed after the district is built: the crowd is a fixed pool, and this
## decides how many of them are *out*. The rest are stood down — invisible, not
## processing, costing nothing — exactly as if they were indoors, because as far
## as the city is concerned they are.
##
## That makes the difference between four in the morning and lunchtime a matter
## of how many people are on the street, which is what it is in a real city, and
## costs one loop an hour.

## Which district this pool belongs to, for the density table.
var district_id: StringName = &"harbour_row"

var _pool: Array[Pedestrian] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(district_id)
	TimeManager.hour_passed.connect(_on_hour_passed)
	# Sleeping eight hours skips the clock rather than running it, so without
	# this the player woke to whatever crowd was on the street when they went
	# to bed. Loading a save and the debug clock come through the same signal.
	TimeManager.time_skipped.connect(_on_time_skipped)
	TimeManager.clock_synced.connect(_apply)
	# The world is built before the clock ticks, so set the opening crowd once.
	call_deferred("_apply")


func register(walker: Pedestrian) -> void:
	if walker != null and not _pool.has(walker):
		_pool.append(walker)


func pool_size() -> int:
	return _pool.size()


func out_count() -> int:
	var found := 0
	for walker in _pool:
		if is_instance_valid(walker) and not walker.is_stood_down():
			found += 1
	return found


func _on_hour_passed(_hour: int) -> void:
	_apply()


func _on_time_skipped(_minutes: int) -> void:
	_apply()


## Stands the right number of people up and the rest down.
##
## Deliberately blunt: it does not care which people, only how many, and it
## leaves anybody the player is currently looking at alone — somebody blinking
## out three metres away is worse than a slightly wrong headcount.
func _apply() -> void:
	if _pool.is_empty():
		return
	var target: int = mini(
		RoutineManager.density_for(district_id), _pool.size()
	)
	var player := GameManager.player
	var out := 0
	for walker in _pool:
		if not is_instance_valid(walker):
			continue
		var near := (
			player != null
			and walker.global_position.distance_to(player.global_position) < 45.0
		)
		var wanted := out < target
		if wanted:
			out += 1
		if near:
			# Never pop somebody in or out in front of the player.
			continue
		_set_out(walker, wanted)
		# Anybody out of earshot is simulated at the only fidelity that costs
		# nothing: when the hour turns they are simply where their day says
		# they are. Close to the player they walk there properly instead. This
		# is what fills the plaza at three o'clock — before it, a park only
		# ever collected the handful of people already standing beside it.
		if wanted and not walker.is_active():
			walker.place_at_routine()


func _set_out(walker: Pedestrian, out: bool) -> void:
	# Somebody coming back onto the street arrives where their day says they
	# should be, not where they were standing when they left it. Only ever for
	# people far from the player, which `_apply` has already checked.
	if out and walker.is_stood_down():
		walker.place_at_routine()
	# Asked, not done to them. Setting the processing flags from here fought
	# with the pedestrian's own distance check and left people walking about
	# unattended in an empty district.
	walker.stand_down(not out)
