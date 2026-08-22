extends Node

## Where the police are looking, and for how much longer.
##
## When line of sight breaks, the chase does not stop — it becomes a search of
## the area around where the player was last seen. §23 asks that the player be
## able to understand roughly where police attention is concentrated, and §25
## that the search grow with the wanted level without ever becoming the whole
## city. So a search is a circle: a centre the police were given, a radius that
## widens as they look, and a clock.
##
## What this deliberately does not own is the clock. WantedManager has counted
## the escape down since Phase J and the whole game is built on it, so
## `seconds_left` here reads through to that rather than keeping a second
## number beside it — two clocks that must agree is two clocks that eventually
## will not. What is owned here is the *area*: where they are looking and how
## far that has spread. §20 still holds, because the countdown this reads is
## itself cancelled the moment anybody sees the player.

signal search_started(centre: Vector3, radius: float)
signal search_expanded(radius: float)
signal search_ended(escaped: bool)

## How wide the police look, per wanted level. The first entry is unused.
## Deliberately bounded: five stars searches several streets, not a district.
const RADIUS_BY_LEVEL: Array[float] = [0.0, 45.0, 65.0, 90.0, 120.0, 150.0]
## The circle widens as they work outwards from the last sighting.
const EXPANSION_PER_SECOND := 1.6
const MAX_EXPANSION := 1.8

var save_id: StringName = &"police_search"
var reset_on_missing_save: bool = true

var centre: Vector3 = Vector3.ZERO
var radius: float = 0.0
var _base_radius: float = 0.0
var _open: bool = false
## Whole seconds of search elapsed, for the statistics.
var _elapsed: float = 0.0


func _ready() -> void:
	add_to_group(&"saveable")


func _process(delta: float) -> void:
	if not _open or GameManager.is_paused():
		return
	# The wanted level cleared underneath us: the player got away.
	if not WantedManager.is_wanted():
		end(true)
		return
	if not WantedManager.is_escaping():
		# Spotted. The chase is back on and there is nothing to search.
		end(false)
		return
	if PoliceMemory.has_fresh_sighting():
		return
	_elapsed += delta
	var widened := minf(_base_radius * MAX_EXPANSION, radius + EXPANSION_PER_SECOND * delta)
	if widened - radius > 0.5:
		radius = widened
		search_expanded.emit(radius)
	else:
		radius = widened


## Opens a search around wherever the police were last told the player was.
func begin(at: Vector3, level: int) -> void:
	centre = at
	_base_radius = _lookup(RADIUS_BY_LEVEL, level, 45.0)
	radius = _base_radius
	_elapsed = 0.0
	_open = true
	search_started.emit(centre, radius)


## A fresh crime or a fresh sighting while searching moves the search rather
## than starting a second one. §106.
func relocate(at: Vector3, level: int) -> void:
	if not active:
		begin(at, level)
		return
	centre = at
	_base_radius = maxf(_base_radius, _lookup(RADIUS_BY_LEVEL, level, 45.0))
	radius = _base_radius
	search_started.emit(centre, radius)


func end(escaped: bool) -> void:
	if not _open:
		return
	_open = false
	radius = 0.0
	search_ended.emit(escaped)


## Whether the police are currently looking for somebody they cannot see.
var active: bool:
	get:
		return _open


## How long is left, read through to the one countdown the game has always had.
var seconds_left: float:
	get:
		return WantedManager.get_escape_seconds_left()


func contains(point: Vector3) -> bool:
	if not active:
		return false
	var flat := point - centre
	flat.y = 0.0
	return flat.length() <= radius


## A point inside the search area for a unit to go and look at. Spread around
## the circle by index so units do not all drive to the same kerb. §53.
func search_point(index: int, total: int) -> Vector3:
	if not active:
		return centre
	var count := maxi(total, 1)
	var angle := TAU * (float(index % count) / float(count)) + float(index) * 0.7
	var reach := radius * lerpf(0.35, 0.95, float((index * 7) % 5) / 4.0)
	return centre + Vector3(cos(angle), 0.0, sin(angle)) * reach


func elapsed_seconds() -> float:
	return _elapsed


func clear() -> void:
	_open = false
	centre = Vector3.ZERO
	radius = 0.0
	_base_radius = 0.0
	_elapsed = 0.0


static func _lookup(table: Array, index: int, fallback: float) -> float:
	if index < 0 or index >= table.size():
		return fallback
	return float(table[index])


func save_state() -> Dictionary:
	return {
		"active": _open,
		"centre": [centre.x, centre.y, centre.z],
		"radius": radius,
		"base_radius": _base_radius,
	}


func load_state(state: Dictionary) -> void:
	clear()
	var point: Array = state.get("centre", [])
	if point.size() == 3:
		centre = Vector3(float(point[0]), float(point[1]), float(point[2]))
	radius = float(state.get("radius", 0.0))
	_base_radius = float(state.get("base_radius", radius))
	_open = bool(state.get("active", false))
