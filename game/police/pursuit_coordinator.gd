extends Node

## Who does what during a chase.
##
## Before this, every police car answered the same question — "where is the
## suspect" — and drove at the same answer, which is how you get four patrol
## cars in a queue behind one player and nothing between them and the next
## junction. §39 asks for units to be assigned rather than to each decide, and
## §42 for them to stop stacking on the primary.
##
## The assignment is deliberately simple. One car is PRIMARY and follows. The
## next are SECONDARY and hang back on their own approach. Above three stars
## some become INTERCEPT and aim where the player is going rather than where
## they are. During a search everybody is SEARCH and takes a different corner of
## the circle. §43 is explicit that this is game AI prediction, not an evasion
## model, and it is: a heading and a guess.
##
## No unit is created here and none is destroyed. This hands out roles to the
## units WantedManager has already dispatched, which keeps the budget in one
## place — the one that already enforces it.

signal roles_changed()

enum Role { NONE, PRIMARY, SECONDARY, INTERCEPT, SEARCH, ROADBLOCK }

const ROLE_NAMES := {
	Role.NONE: "NONE",
	Role.PRIMARY: "PRIMARY",
	Role.SECONDARY: "SECONDARY",
	Role.INTERCEPT: "INTERCEPT",
	Role.SEARCH: "SEARCH",
	Role.ROADBLOCK: "ROADBLOCK",
}

## Wanted level at which units start trying to cut the player off rather than
## follow. Below this a chase is a queue, which is correct for one star.
const INTERCEPT_FROM_LEVEL := 3
## Of the units on a call, how many may be intercepting. Never all of them:
## somebody has to actually be behind the player.
const MAX_INTERCEPTORS := 2
## How far ahead an interceptor aims, in seconds of the player's travel.
const INTERCEPT_LEAD_SECONDS := 3.4
## How far off the primary's line secondaries sit, so they arrive on their own
## approach rather than in convoy.
const SECONDARY_OFFSET := 18.0
## Roles are worked out this often. Cheap, but not per-frame cheap.
const REVIEW_INTERVAL := 0.6

## unit -> Role
var _roles: Dictionary = {}
var _review_timer: float = 0.0


func _process(delta: float) -> void:
	_review_timer -= delta
	if _review_timer > 0.0:
		return
	_review_timer = REVIEW_INTERVAL
	_review()


func active_units() -> int:
	return _roles.size()


func role_of(unit: Node) -> Role:
	return _roles.get(unit, Role.NONE)


func role_name(unit: Node) -> String:
	return String(ROLE_NAMES.get(role_of(unit), "NONE"))


func count_in_role(role: Role) -> int:
	var total := 0
	for unit: Node in _roles:
		if _roles[unit] == role:
			total += 1
	return total


## Where a given unit should be going, given its role. The one call a police
## driver makes; everything above is how the answer is decided.
##
## Note that none of these is the player's position. Even PRIMARY routes on the
## last *known* position, which is the same value the player's own pursuers had
## a moment ago and the whole reason breaking line of sight works.
func target_for(unit: Node) -> Vector3:
	var origin := PoliceMemory.search_origin()
	match role_of(unit):
		Role.PRIMARY:
			return origin
		Role.SECONDARY:
			return _offset_point(unit, origin, SECONDARY_OFFSET)
		Role.INTERCEPT:
			return PoliceMemory.predicted_position(INTERCEPT_LEAD_SECONDS)
		Role.SEARCH:
			return SearchManager.search_point(_index_of(unit), maxi(_roles.size(), 1))
		_:
			return origin


func clear() -> void:
	if _roles.is_empty():
		return
	_roles.clear()
	roles_changed.emit()


# --- Assignment ----------------------------------------------------------

func _review() -> void:
	var units := _live_units()
	if units.is_empty():
		clear()
		return

	var before := _roles.duplicate()
	_roles.clear()

	if PoliceResponseManager.is_searching():
		for unit in units:
			_roles[unit] = Role.SEARCH
	else:
		# Nearest to what the police believe is the suspect's position leads.
		var origin := PoliceMemory.search_origin()
		units.sort_custom(func(a: Node, b: Node) -> bool:
			return _distance(a, origin) < _distance(b, origin)
		)
		var interceptors := 0
		var may_intercept := (
			WantedManager.level >= INTERCEPT_FROM_LEVEL
			and PoliceResponseManager.profile().intercepts
			and PoliceMemory.has_fresh_sighting()
		)
		for i in units.size():
			var unit: Node = units[i]
			if i == 0:
				_roles[unit] = Role.PRIMARY
				continue
			# §43 — some units go where the player is going. Never the closest
			# one, which is the only car actually keeping them honest.
			if may_intercept and interceptors < MAX_INTERCEPTORS and i % 2 == 0:
				_roles[unit] = Role.INTERCEPT
				interceptors += 1
				continue
			_roles[unit] = Role.SECONDARY

	if _roles != before:
		roles_changed.emit()


## The units WantedManager currently has out, filtered to the ones still in the
## tree. Nothing is spawned or despatched here.
func _live_units() -> Array[Node]:
	var found: Array[Node] = []
	for unit in WantedManager.get_responders():
		if unit != null and is_instance_valid(unit):
			found.append(unit)
	return found


func _distance(unit: Node, point: Vector3) -> float:
	var body := _body_of(unit)
	return body.global_position.distance_to(point) if body != null else INF


func _body_of(unit: Node) -> Node3D:
	if unit == null:
		return null
	if unit.has_method("get_car"):
		var car = unit.call("get_car")
		if car is Node3D:
			return car
	return unit as Node3D


## A point to one side of the approach, so a second car comes in from a
## different direction instead of tailgating the first.
func _offset_point(unit: Node, origin: Vector3, distance: float) -> Vector3:
	var index := _index_of(unit)
	var angle := TAU * (float(index) / 6.0) + 0.9
	return origin + Vector3(cos(angle), 0.0, sin(angle)) * distance


func _index_of(unit: Node) -> int:
	var index := 0
	for other: Node in _roles:
		if other == unit:
			return index
		index += 1
	return 0
